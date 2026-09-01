#!/bin/bash

release_usage() {
  printf '%s\n' \
    'Usage: scripts/release.sh --output-dir <directory>' \
    '' \
    'Build and verify the СберВакансии Release app, then publish a DMG and evidence sidecars.'
}

release_error() {
  printf 'Release gate failed: %s\n' "$*" >&2
}

release_python() {
  /usr/bin/python3 -I - "$@" <<'PY'
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import pwd
import re
import stat
import sys


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def canonical(value):
    if not value:
        fail("path is empty")
    return os.path.realpath(os.path.abspath(value))


CONSUMER_REQUIRED_RELEASE_SETTING_KEYS = frozenset(
    {
        "ARCHS",
        "CODE_SIGN_ENTITLEMENTS",
        "CODE_SIGN_IDENTITY",
        "CODE_SIGN_INJECT_BASE_ENTITLEMENTS",
        "CODE_SIGN_STYLE",
        "DEVELOPMENT_TEAM",
        "ENABLE_APP_SANDBOX",
        "ENABLE_HARDENED_RUNTIME",
        "EXECUTABLE_NAME",
        "MACOSX_DEPLOYMENT_TARGET",
        "ONLY_ACTIVE_ARCH",
        "PRODUCT_BUNDLE_IDENTIFIER",
        "PRODUCT_NAME",
        "PROVISIONING_PROFILE_SPECIFIER",
        "TARGET_BUILD_DIR",
        "WRAPPER_NAME",
    }
)

MANDATORY_RELEASE_SETTING_KEYS = CONSUMER_REQUIRED_RELEASE_SETTING_KEYS - {
    "DEVELOPMENT_TEAM",
    "PROVISIONING_PROFILE_SPECIFIER",
}


def parse_settings(path, target, evidence_path=None):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    header = re.compile(
        r"^Build settings for action [^:\r\n]+ and target ([^:\r\n]+):$"
    )
    setting = re.compile(r"^    ([A-Za-z_][A-Za-z0-9_]*) = ?(.*)$")
    lines = text.splitlines()
    section_starts = []
    for index, line in enumerate(lines):
        match = header.fullmatch(line)
        if match and match.group(1) == target:
            section_starts.append(index + 1)
    if len(section_starts) != 1:
        fail("expected exactly one build-settings section for target " + target)

    current = {}
    block_started = False
    block_start_line = None
    termination_line = None
    termination_reason = "end-of-file"
    assignment_count = 0
    required_duplicate_count = 0
    ignored_case_counts = {"lowercase": 0, "mixed-case": 0, "uppercase": 0}
    request_records_observed = sum(
        1
        for line in lines
        if (setting.fullmatch(line) and setting.fullmatch(line).group(1) == "request")
    )

    def write_evidence():
        if evidence_path is None:
            return
        evidence = {
            "assignment_block_start_line": block_start_line,
            "consumer_required_key_count": len(
                CONSUMER_REQUIRED_RELEASE_SETTING_KEYS
            ),
            "mandatory_key_count": len(MANDATORY_RELEASE_SETTING_KEYS),
            "ignored_key_case_counts": ignored_case_counts,
            "recognized_assignment_count": assignment_count,
            "request_records_accepted": 0,
            "request_records_observed": request_records_observed,
            "required_key_duplicate_count": required_duplicate_count,
            "required_keys_accepted": sorted(current),
            "target": target,
            "target_header_count": len(section_starts),
            "termination_line": termination_line,
            "termination_reason": termination_reason,
        }
        Path(evidence_path).write_bytes(canonical_json_bytes(evidence))

    for line_number, line in enumerate(
        lines[section_starts[0]:], section_starts[0] + 1
    ):
        match = setting.fullmatch(line)
        if not match:
            if block_started:
                termination_line = line_number
                termination_reason = (
                    "next-build-settings-header"
                    if header.fullmatch(line)
                    else "first-non-assignment"
                )
                break
            if header.fullmatch(line):
                termination_line = line_number
                termination_reason = "next-build-settings-header"
                break
            continue
        if not block_started:
            block_started = True
            block_start_line = line_number
        assignment_count += 1
        key, value = match.groups()
        if key not in CONSUMER_REQUIRED_RELEASE_SETTING_KEYS:
            if key.isupper():
                ignored_case_counts["uppercase"] += 1
            elif key.islower():
                ignored_case_counts["lowercase"] += 1
            else:
                ignored_case_counts["mixed-case"] += 1
            continue
        if key in current:
            required_duplicate_count += 1
            write_evidence()
            fail("duplicate build setting in application target: " + key)
        current[key] = value

    missing = sorted(MANDATORY_RELEASE_SETTING_KEYS - current.keys())
    if missing:
        write_evidence()
        fail("required Release setting is missing: " + ", ".join(missing))
    write_evidence()
    return current


def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail("invalid JSON: " + str(error))


def validate_settings(settings):
    exact = {
        "ARCHS": "arm64",
        "ONLY_ACTIVE_ARCH": "NO",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "ENABLE_APP_SANDBOX": "YES",
        "ENABLE_HARDENED_RUNTIME": "YES",
        "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "NO",
    }
    for key, expected in exact.items():
        observed = settings.get(key)
        if observed != expected:
            fail("Release setting mismatch: %s=%r (required %r)" % (key, observed, expected))
    for key in ("DEVELOPMENT_TEAM", "PROVISIONING_PROFILE_SPECIFIER"):
        if settings.get(key, "") != "":
            fail("Release setting must be empty: " + key)
    required = (
        "CODE_SIGN_IDENTITY",
        "CODE_SIGN_STYLE",
        "CODE_SIGN_ENTITLEMENTS",
        "PRODUCT_NAME",
        "WRAPPER_NAME",
        "TARGET_BUILD_DIR",
        "EXECUTABLE_NAME",
        "PRODUCT_BUNDLE_IDENTIFIER",
    )
    for key in required:
        value = settings.get(key)
        if not isinstance(value, str) or not value:
            fail("required Release setting is missing: " + key)
    if settings["CODE_SIGN_IDENTITY"] != "-":
        fail("Release CODE_SIGN_IDENTITY does not select ad-hoc signing")
    if settings["PRODUCT_NAME"] != "СберВакансии":
        fail("unexpected PRODUCT_NAME")
    if settings["WRAPPER_NAME"] != "СберВакансии.app":
        fail("unexpected WRAPPER_NAME")


def iter_entries(root, excluded=()):
    root = Path(root)
    excluded_set = set(excluded)
    records = []
    for directory, directory_names, file_names in os.walk(str(root), topdown=True, followlinks=False):
        directory_path = Path(directory)
        retained = []
        for name in directory_names:
            path = directory_path / name
            relative = path.relative_to(root).as_posix()
            if relative in excluded_set:
                continue
            if path.is_symlink():
                records.append((relative, path))
            else:
                retained.append(name)
        directory_names[:] = retained
        for name in file_names:
            path = directory_path / name
            relative = path.relative_to(root).as_posix()
            if relative not in excluded_set:
                records.append((relative, path))
    records.sort(key=lambda item: item[0])
    return records


def hash_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        while True:
            block = stream.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def payload_records(root):
    records = []
    for relative, path in iter_entries(
        root,
        (".DS_Store", "RELEASE-MANIFEST.json"),
    ):
        info = os.lstat(path)
        mode = "%04o" % stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            if mode != "0777":
                fail("payload symlink mode is not 0777: " + relative)
            records.append({
                "mode": mode,
                "path": relative,
                "target": os.readlink(path),
                "type": "symlink",
            })
        elif stat.S_ISREG(info.st_mode):
            records.append({
                "mode": mode,
                "path": relative,
                "sha256": hash_file(path),
                "type": "file",
            })
        else:
            fail("unsupported payload entry: " + relative)
    return records


def exact_entries(root, expected):
    if not expected or len(expected) != len(set(expected)):
        fail("expected root-entry contract is empty or duplicated")
    for name in expected:
        pure = PurePosixPath(name)
        if (
            not name
            or pure.is_absolute()
            or len(pure.parts) != 1
            or "." in pure.parts
            or ".." in pure.parts
            or pure.as_posix() != name
        ):
            fail("unsafe expected root entry: " + repr(name))
    observed = os.listdir(root)
    if len(observed) != len(set(observed)) or set(observed) != set(expected):
        fail("payload root entries mismatch: " + repr(sorted(observed)))
    hidden = sorted(name for name in observed if name.startswith("."))
    print("ROOT_PHYSICAL_ENTRY_COUNT=%d" % len(observed))
    print("ROOT_HIDDEN_ENTRY_COUNT=%d" % len(hidden))
    print("ROOT_HIDDEN_ENTRIES=" + ",".join(hidden))


def exact_root(root):
    exact_entries(
        root,
        [
            ".DS_Store",
            "Applications",
            "СберВакансии.app",
            "README.txt",
            "RELEASE-MANIFEST.json",
        ],
    )
    ds_store = Path(root) / ".DS_Store"
    info = os.lstat(ds_store)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_size <= 0:
        fail(".DS_Store is not a nonempty regular file")


def validate_payload_path(value):
    if not isinstance(value, str) or not value:
        fail("manifest payload path is empty")
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts or "." in pure.parts:
        fail("unsafe manifest payload path: " + value)
    if pure.as_posix() != value:
        fail("non-canonical manifest payload path: " + value)


def canonical_json_bytes(value):
    return (json.dumps(
        value,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ) + "\n").encode("utf-8")


def expected_metadata(commit, bundle_identifier, short_version, bundle_version):
    return {
        "app_sandbox": True,
        "architecture": ["arm64"],
        "bundle_identifier": bundle_identifier,
        "bundle_short_version": short_version,
        "bundle_version": bundle_version,
        "configuration": "Release",
        "excluded_presentation_metadata": {
            ".DS_Store": "excluded_from_logical_payload_hashes",
        },
        "forbidden_entitlements_absent": [
            "com.apple.security.get-task-allow",
        ],
        "hardened_runtime": True,
        "minimum_macos": "13.0",
        "product": "СберВакансии",
        "required_entitlements": {
            "com.apple.security.app-sandbox": True,
            "com.apple.security.files.user-selected.read-write": True,
            "com.apple.security.network.client": True,
        },
        "schema_version": 1,
        "signing": "ad-hoc",
        "source_commit": commit,
    }


def generate_manifest(root, destination, commit, bundle_identifier, short_version, bundle_version):
    manifest = expected_metadata(commit, bundle_identifier, short_version, bundle_version)
    manifest["payload"] = payload_records(root)
    Path(destination).write_bytes(canonical_json_bytes(manifest))


def verify_manifest(root, manifest_path, commit, bundle_identifier, short_version, bundle_version):
    source_entries = {
        "Applications",
        "СберВакансии.app",
        "README.txt",
        "RELEASE-MANIFEST.json",
    }
    presented_entries = source_entries | {".DS_Store"}
    observed_entries = set(os.listdir(root))
    if observed_entries not in (source_entries, presented_entries):
        fail("payload root entries mismatch: " + repr(sorted(observed_entries)))
    if ".DS_Store" in observed_entries:
        ds_store = Path(root) / ".DS_Store"
        info = os.lstat(ds_store)
        if (
            stat.S_ISLNK(info.st_mode)
            or not stat.S_ISREG(info.st_mode)
            or info.st_size <= 0
        ):
            fail(".DS_Store is not a nonempty regular file")
    raw = Path(manifest_path).read_bytes()
    try:
        manifest = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        fail("manifest is not valid UTF-8 JSON: " + str(error))
    if raw != canonical_json_bytes(manifest):
        fail("manifest JSON is not canonical")
    expected = expected_metadata(commit, bundle_identifier, short_version, bundle_version)
    payload = manifest.get("payload")
    if not isinstance(payload, list):
        fail("manifest payload is not a list")
    observed_metadata = dict(manifest)
    observed_metadata.pop("payload", None)
    if observed_metadata != expected:
        fail("manifest metadata contract mismatch")
    paths = []
    for record in payload:
        if not isinstance(record, dict):
            fail("manifest payload record is not an object")
        path = record.get("path")
        validate_payload_path(path)
        paths.append(path)
        record_type = record.get("type")
        keys = set(record)
        if record_type == "file":
            if keys != {"mode", "path", "sha256", "type"}:
                fail("invalid regular-file manifest record: " + path)
            if not re.fullmatch(r"[0-9a-f]{64}", str(record.get("sha256", ""))):
                fail("invalid SHA-256 in manifest: " + path)
        elif record_type == "symlink":
            if keys != {"mode", "path", "target", "type"}:
                fail("invalid symlink manifest record: " + path)
            if not isinstance(record.get("target"), str):
                fail("invalid symlink target in manifest: " + path)
        else:
            fail("invalid manifest record type: " + path)
        if not re.fullmatch(r"[0-7]{4}", str(record.get("mode", ""))):
            fail("invalid mode in manifest: " + path)
    if paths != sorted(paths) or len(paths) != len(set(paths)):
        fail("manifest payload paths are unsorted or duplicated")
    actual = payload_records(root)
    if payload != actual:
        fail("manifest payload does not match actual files, modes, hashes, or symlinks")
    applications = Path(root) / "Applications"
    if not applications.is_symlink() or os.readlink(applications) != "/Applications":
        fail("Applications symlink contract mismatch")


def snapshot(root):
    return canonical_json_bytes(payload_records(root))


def repository_snapshot(root):
    root = Path(root)
    records = []

    def relative_path(path):
        relative = Path(path).relative_to(root).as_posix()
        pure = PurePosixPath(relative)
        if (not relative or pure.is_absolute() or "." in pure.parts or
                ".." in pure.parts or pure.as_posix() != relative):
            fail("unable to snapshot repository path=<invalid> operation=path")
        return relative

    def snapshot_error(relative, operation):
        fail("unable to snapshot repository path=%s operation=%s" % (
            relative,
            operation,
        ))

    def visit(directory):
        try:
            children = sorted(os.scandir(directory), key=lambda item: item.name)
        except OSError:
            if Path(directory) == root:
                snapshot_error("<repository-root>", "read-directory")
            snapshot_error(relative_path(directory), "read-directory")
        for child in children:
            if Path(directory) == root and child.name == ".git":
                continue
            path = Path(child.path)
            relative = relative_path(path)
            try:
                info = os.lstat(path)
            except OSError:
                snapshot_error(relative, "classify")
            mode = "%04o" % stat.S_IMODE(info.st_mode)
            if stat.S_ISDIR(info.st_mode):
                records.append({"mode": mode, "path": relative, "type": "directory"})
                visit(path)
            elif stat.S_ISLNK(info.st_mode):
                try:
                    target = os.readlink(path)
                except OSError:
                    snapshot_error(relative, "read-symlink")
                records.append({
                    "mode": mode,
                    "path": relative,
                    "target": target,
                    "type": "symlink",
                })
            elif stat.S_ISREG(info.st_mode):
                try:
                    digest = hash_file(path)
                except OSError:
                    snapshot_error(relative, "read-file")
                records.append({
                    "mode": mode,
                    "path": relative,
                    "sha256": digest,
                    "size": info.st_size,
                    "type": "file",
                })
            else:
                snapshot_error(relative, "unsupported-type")

    visit(root)
    records.sort(key=lambda record: record["path"])
    paths = [record["path"] for record in records]
    if paths != sorted(paths) or len(paths) != len(set(paths)):
        fail("unable to snapshot repository path=<invalid> operation=ordering")
    return canonical_json_bytes(records)


def repository_snapshot_changes(baseline_path, current_path):
    baseline = load_json(baseline_path)
    current = load_json(current_path)
    if not isinstance(baseline, list) or not isinstance(current, list):
        fail("repository snapshot is not a list")

    def indexed(records):
        result = {}
        previous = None
        for record in records:
            if not isinstance(record, dict):
                fail("repository snapshot record is not an object")
            path = record.get("path")
            if not isinstance(path, str) or not path or path in result:
                fail("repository snapshot contains an invalid path")
            if previous is not None and path <= previous:
                fail("repository snapshot paths are not strictly sorted")
            result[path] = record
            previous = path
        return result

    before = indexed(baseline)
    after = indexed(current)
    changes = []
    semantic_fields = ("mode", "sha256", "size", "target", "type")
    for path in sorted(set(before) | set(after)):
        if path not in before:
            changes.append((path, "added", ()))
        elif path not in after:
            changes.append((path, "removed", ()))
        else:
            fields = tuple(
                field for field in semantic_fields
                if before[path].get(field) != after[path].get(field)
            )
            if fields:
                changes.append((path, "modified", fields))
    return changes


def repository_snapshot_check(baseline_path, current_path, checkpoint):
    changes = repository_snapshot_changes(baseline_path, current_path)
    if not changes:
        return
    print(
        "Release gate failed: source repository content changed during release packaging",
        file=sys.stderr,
    )
    print("SOURCE_SNAPSHOT_CHECKPOINT=" + checkpoint, file=sys.stderr)
    print("SOURCE_SNAPSHOT_CHANGE_COUNT=%d" % len(changes), file=sys.stderr)
    for path, change, fields in changes:
        if change == "modified":
            print(
                "SOURCE_SNAPSHOT_CHANGE=modified path=%s fields=%s" % (
                    path,
                    ",".join(fields),
                ),
                file=sys.stderr,
            )
        else:
            print(
                "SOURCE_SNAPSHOT_CHANGE=%s path=%s" % (change, path),
                file=sys.stderr,
            )
    raise SystemExit(1)


def verifier_check(path, main_executable):
    report = load_json(path)
    if report.get("success") is not True:
        fail("release entitlement verifier did not report success")
    if report.get("signature_valid") is not True:
        fail("release entitlement verifier did not validate the signature")
    if report.get("forbidden_entitlements_found") != []:
        fail("release entitlement verifier found a forbidden entitlement")
    if report.get("required_entitlements_missing") != []:
        fail("release entitlement verifier found a missing entitlement")
    nested = report.get("nested_code")
    if not isinstance(nested, list):
        fail("release entitlement verifier nested-code report is invalid")
    for item in nested:
        path_value = item.get("path") if isinstance(item, dict) else None
        if not isinstance(path_value, str):
            fail("release entitlement verifier nested-code path is invalid")
        try:
            duplicated = os.path.samefile(path_value, main_executable)
        except OSError:
            duplicated = canonical(path_value) == canonical(main_executable)
        if duplicated:
            fail("main executable is duplicated in nested_code")


def entitlements_check(path, require_main):
    try:
        raw = Path(path).read_bytes()
    except OSError as error:
        fail("invalid entitlement plist: " + str(error))
    if not raw:
        if require_main:
            fail("main executable entitlement plist is empty")
        entitlements = {}
    else:
        try:
            entitlements = plistlib.loads(raw)
        except (plistlib.InvalidFileException, ValueError, TypeError) as error:
            fail("invalid entitlement plist: " + str(error))
    if not isinstance(entitlements, dict):
        fail("entitlements are not a dictionary")
    forbidden = ("com.apple.security.get-task-allow",)
    for key in forbidden:
        if key in entitlements:
            fail("forbidden entitlement present: " + key)
    if require_main:
        required = (
            "com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.network.client",
        )
        for key in required:
            if entitlements.get(key) is not True:
                fail("required entitlement is not true: " + key)


def signature_check(path, app):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    if not re.search(r"(?m)^Signature=adhoc\s*$", text):
        fail("signature metadata is not ad hoc")
    flags = re.search(r"(?m)^CodeDirectory .*? flags=([^\n]+)$", text)
    if not flags or "adhoc" not in flags.group(1).lower():
        fail("signature flags do not contain adhoc")
    if "runtime" not in flags.group(1).lower():
        fail("Hardened Runtime signature flag is absent")
    if not re.search(r"(?m)^TeamIdentifier=not set\s*$", text):
        fail("TeamIdentifier is set or unavailable")
    for directory, _names, files in os.walk(app):
        for name in files:
            if name.lower() == "embedded.provisionprofile":
                fail("embedded provisioning profile is present")


def list_regular_files(root):
    paths = []
    for relative, path in iter_entries(root):
        try:
            info = os.lstat(path)
        except OSError as error:
            fail("unable to inspect application entry: " + str(error))
        if stat.S_ISREG(info.st_mode):
            paths.append(relative)
    for relative in paths:
        sys.stdout.buffer.write(relative.encode("utf-8") + b"\0")


def vtool_check(path, kind):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    platforms = re.findall(r"(?mi)^\s*platform\s+([^\s]+)\s*$", text)
    minimums = re.findall(r"(?mi)^\s*minos\s+([0-9]+(?:\.[0-9]+){1,2})\s*$", text)
    if not platforms or not minimums:
        fail("Mach-O build-version record is missing")
    if any(value.lower() not in ("macos", "macosx") for value in platforms):
        fail("Mach-O platform is not macOS")
    def version(value):
        parts = [int(item) for item in value.split(".")]
        return tuple((parts + [0, 0, 0])[:3])
    if kind == "main":
        if any(version(value) != (13, 0, 0) for value in minimums):
            fail("main executable minimum macOS is not 13.0")
    elif any(version(value) > (13, 0, 0) for value in minimums):
        fail("nested Mach-O requires a newer macOS version")


def scan_controls(root, destination):
    identifiers = (
        b"HHVACANCYSBER_UI_TEST_MODE",
        b"HHVACANCYSBER_UI_TEST_SCENARIO",
    )
    findings = []
    regular = [(relative, path) for relative, path in iter_entries(root)
               if stat.S_ISREG(os.lstat(path).st_mode)]
    for identifier in identifiers:
        matches = []
        for relative, path in regular:
            try:
                data = Path(path).read_bytes()
            except OSError as error:
                fail("unable to scan Release file: " + str(error))
            if identifier in data:
                matches.append(relative)
        findings.append({
            "identifier": identifier.decode("ascii"),
            "matching_paths": matches,
            "present": bool(matches),
        })
    Path(destination).write_bytes(canonical_json_bytes(findings))
    if any(item["present"] for item in findings):
        raise SystemExit(1)


def attach_device(path, expected_mount):
    try:
        with open(path, "rb") as stream:
            data = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError) as error:
        fail("invalid hdiutil attach plist: " + str(error))
    entities = data.get("system-entities") if isinstance(data, dict) else None
    if not isinstance(entities, list):
        fail("hdiutil attach plist has no system entities")
    expected = canonical(expected_mount)
    expected_raw = expected_mount.rstrip("/") or "/"
    mounted_entities = []
    for entity in entities:
        if not isinstance(entity, dict):
            continue
        mount = entity.get("mount-point")
        device = entity.get("dev-entry")
        if isinstance(mount, str):
            mounted_entities.append((mount, device))
    if len(mounted_entities) != 1:
        fail("hdiutil attach plist does not identify exactly one mounted entity")
    mount, device = mounted_entities[0]
    observed_raw = mount.rstrip("/") or "/"
    if (
        not isinstance(device, str)
        or observed_raw != expected_raw
        or canonical(mount) != expected
        or not re.fullmatch(r"/dev/disk[0-9]+(?:s[0-9]+)?", device)
    ):
        fail("unable to identify the uniquely mounted DMG device")
    print(device)


def strings_in(value):
    if isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)
    elif isinstance(value, str):
        yield value


def imageinfo_check(path, expected_format):
    try:
        with open(path, "rb") as stream:
            data = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError) as error:
        fail("invalid hdiutil imageinfo plist: " + str(error))
    if expected_format not in ("UDRW", "UDZO"):
        fail("unsupported expected image format")
    if not isinstance(data, dict) or data.get("Format") != expected_format:
        fail("DMG image format is not " + expected_format)


READ_ONLY_KEYS = (
    "ReadOnlyVolume",
    "Writable",
    "WritableVolume",
    "WritableMedia",
)


def normalized_read_only_values(data):
    normalized = {}
    for key in READ_ONLY_KEYS:
        if key not in data:
            normalized[key] = "absent"
        elif type(data[key]) is bool:
            normalized[key] = "true" if data[key] else "false"
        else:
            normalized[key] = "invalid"
    return normalized


def reject_read_only_evidence(normalized):
    print("Release gate failed: DMG is not mounted read-only", file=sys.stderr)
    print("DMG_READ_ONLY_SCHEMA=invalid", file=sys.stderr)
    for key in READ_ONLY_KEYS:
        label = re.sub(r"(?<!^)(?=[A-Z])", "_", key).upper()
        print("DMG_%s=%s" % (label, normalized[key]), file=sys.stderr)
    raise SystemExit(1)


def reject_writable_evidence(normalized):
    print(
        "Release gate failed: writable image is not mounted read-write",
        file=sys.stderr,
    )
    print("DMG_WRITABLE_SCHEMA=invalid", file=sys.stderr)
    for key in READ_ONLY_KEYS:
        label = re.sub(r"(?<!^)(?=[A-Z])", "_", key).upper()
        print("DMG_%s=%s" % (label, normalized[key]), file=sys.stderr)
    raise SystemExit(1)


def read_only_schema(data):
    normalized = normalized_read_only_values(data)
    if "invalid" in normalized.values():
        reject_read_only_evidence(normalized)

    writable = tuple(normalized[key] for key in READ_ONLY_KEYS[1:])
    if "true" in writable or normalized["ReadOnlyVolume"] == "false":
        reject_read_only_evidence(normalized)

    if normalized["ReadOnlyVolume"] == "true":
        return "explicit-read-only"
    if normalized["ReadOnlyVolume"] == "absent" and writable == (
        "false", "false", "false",
    ):
        return "macos13-writable-flags"
    reject_read_only_evidence(normalized)


def writable_schema(data):
    normalized = normalized_read_only_values(data)
    if "invalid" in normalized.values():
        reject_writable_evidence(normalized)
    if normalized["ReadOnlyVolume"] not in ("absent", "false"):
        reject_writable_evidence(normalized)
    writable = tuple(normalized[key] for key in READ_ONLY_KEYS[1:])
    if writable != ("true", "true", "true"):
        reject_writable_evidence(normalized)
    if normalized["ReadOnlyVolume"] == "false":
        return "explicit-read-write"
    return "macos13-writable-flags"


def load_diskinfo(path):
    try:
        with open(path, "rb") as stream:
            data = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError) as error:
        fail("invalid mounted-image disk information: " + str(error))
    if not isinstance(data, dict):
        fail("mounted-image disk information is not a dictionary")
    return data


def diskinfo_common(data, device, mountpoint):
    mounted = data.get("Mounted", None)
    if mounted is not None and (type(mounted) is not bool or mounted is not True):
        fail("mounted DMG is not reported as mounted")
    if data.get("VolumeName") != "СберВакансии":
        fail("mounted DMG volume name mismatch")
    filesystem_values = " ".join(str(data.get(key, "")) for key in (
        "FilesystemType", "FileSystemPersonality", "FilesystemName",
    )).lower()
    if "hfs" not in filesystem_values:
        fail("mounted DMG filesystem is not HFS+")
    observed_mount = data.get("MountPoint")
    expected_raw = mountpoint.rstrip("/") or "/"
    observed_raw = observed_mount.rstrip("/") or "/" if isinstance(observed_mount, str) else ""
    if (
        not isinstance(observed_mount, str)
        or observed_raw != expected_raw
        or canonical(observed_mount) != canonical(mountpoint)
    ):
        fail("mounted DMG mountpoint mismatch")
    observed_device = data.get("DeviceNode")
    if observed_device != device:
        fail("mounted DMG device mismatch")


def diskinfo_check(path, device, mountpoint):
    try:
        data = load_diskinfo(path)
    except SystemExit:
        reject_read_only_evidence({key: "invalid" for key in READ_ONLY_KEYS})
    diskinfo_common(data, device, mountpoint)
    print("DMG_READ_ONLY_SCHEMA=" + read_only_schema(data))


def writable_diskinfo_check(path, device, mountpoint):
    try:
        data = load_diskinfo(path)
    except SystemExit:
        reject_writable_evidence({key: "invalid" for key in READ_ONLY_KEYS})
    diskinfo_common(data, device, mountpoint)
    print("DMG_WRITABLE_SCHEMA=" + writable_schema(data))


def ds_store_check(path, expected_hash):
    if not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
        fail("invalid expected .DS_Store SHA-256")
    try:
        info = os.lstat(path)
    except OSError as error:
        fail("unable to inspect .DS_Store: " + str(error))
    if (
        stat.S_ISLNK(info.st_mode)
        or not stat.S_ISREG(info.st_mode)
        or info.st_size <= 0
    ):
        fail(".DS_Store is not a nonempty regular file")
    observed_hash = hash_file(path)
    if observed_hash != expected_hash:
        fail(".DS_Store SHA-256 differs from writable presentation metadata")
    print("DS_STORE_SIZE=%d" % info.st_size)
    print("DS_STORE_SHA256=" + observed_hash)


def checksum_check(path, expected_hash, expected_basename):
    raw = Path(path).read_bytes()
    expected = (expected_hash + "  " + expected_basename + "\n").encode("ascii")
    if raw != expected:
        fail("checksum sidecar syntax or content mismatch")


def link_exclusive(source, destination):
    try:
        os.link(source, destination)
    except OSError as error:
        fail("exclusive hard link failed: " + str(error))


command = sys.argv[1] if len(sys.argv) > 1 else ""
arguments = sys.argv[2:]
if command == "canonical":
    print(canonical(arguments[0]))
elif command == "home":
    print(canonical(pwd.getpwuid(os.getuid()).pw_dir))
elif command == "parse-settings":
    evidence_path = arguments[2] if len(arguments) > 2 else None
    settings = parse_settings(arguments[0], arguments[1], evidence_path)
    sys.stdout.buffer.write(canonical_json_bytes(settings))
elif command == "settings-validate":
    settings = load_json(arguments[0])
    if not isinstance(settings, dict):
        fail("build settings are not an object")
    validate_settings(settings)
elif command == "json-get":
    value = load_json(arguments[0]).get(arguments[1], "")
    if not isinstance(value, str):
        fail("build setting is not a string: " + arguments[1])
    print(value)
elif command == "manifest-generate":
    generate_manifest(*arguments)
elif command == "manifest-verify":
    verify_manifest(*arguments)
elif command == "exact-entries":
    exact_entries(arguments[0], arguments[1:])
elif command == "exact-root":
    exact_root(arguments[0])
elif command == "snapshot":
    sys.stdout.buffer.write(snapshot(arguments[0]))
elif command == "repository-snapshot":
    sys.stdout.buffer.write(repository_snapshot(arguments[0]))
elif command == "repository-snapshot-check":
    repository_snapshot_check(arguments[0], arguments[1], arguments[2])
elif command == "verifier-check":
    verifier_check(arguments[0], arguments[1])
elif command == "entitlements-check":
    entitlements_check(arguments[0], arguments[1] == "main")
elif command == "signature-check":
    signature_check(arguments[0], arguments[1])
elif command == "regular-files0":
    list_regular_files(arguments[0])
elif command == "vtool-check":
    vtool_check(arguments[0], arguments[1])
elif command == "scan-controls":
    scan_controls(arguments[0], arguments[1])
elif command == "attach-device":
    attach_device(arguments[0], arguments[1])
elif command == "imageinfo-check":
    imageinfo_check(arguments[0], arguments[1])
elif command == "diskinfo-check":
    diskinfo_check(arguments[0], arguments[1], arguments[2])
elif command == "writable-diskinfo-check":
    writable_diskinfo_check(arguments[0], arguments[1], arguments[2])
elif command == "ds-store-check":
    ds_store_check(arguments[0], arguments[1])
elif command == "same-file":
    try:
        equal = os.path.samefile(arguments[0], arguments[1])
    except OSError:
        equal = canonical(arguments[0]) == canonical(arguments[1])
    raise SystemExit(0 if equal else 1)
elif command == "checksum-check":
    checksum_check(arguments[0], arguments[1], arguments[2])
elif command == "link-exclusive":
    link_exclusive(arguments[0], arguments[1])
else:
    fail("unknown release helper operation")
PY
}

release_canonical_path() {
  release_python canonical "$1"
}

release_reject_unsafe_environment() {
  if [[ -n "${GIT_INDEX_FILE+x}" ||
        -n "${GIT_DIR+x}" ||
        -n "${GIT_WORK_TREE+x}" ||
        -n "${GIT_COMMON_DIR+x}" ||
        -n "${GIT_OBJECT_DIRECTORY+x}" ||
        -n "${GIT_ALTERNATE_OBJECT_DIRECTORIES+x}" ||
        -n "${GIT_CONFIG_COUNT+x}" ||
        -n "${GIT_CONFIG_PARAMETERS+x}" ||
        -n "${GIT_NAMESPACE+x}" ||
        -n "${GIT_CEILING_DIRECTORIES+x}" ||
        -n "${XCODE_XCCONFIG_FILE+x}" ||
        -n "${DEVELOPER_DIR+x}" ||
        -n "${TOOLCHAINS+x}" ||
        -n "${SDKROOT+x}" ||
        -n "${SWIFT_EXEC+x}" ||
        -n "${SWIFT_DRIVER_SWIFT_FRONTEND_EXEC+x}" ||
        -n "${CC+x}" ||
        -n "${CXX+x}" ||
        -n "${CFLAGS+x}" ||
        -n "${CXXFLAGS+x}" ||
        -n "${LDFLAGS+x}" ||
        -n "${OTHER_SWIFT_FLAGS+x}" ||
        -n "${OTHER_CFLAGS+x}" ||
        -n "${OTHER_LDFLAGS+x}" ||
        -n "${OTHER_CODE_SIGN_FLAGS+x}" ||
        -n "${ARCHS+x}" ||
        -n "${ONLY_ACTIVE_ARCH+x}" ||
        -n "${MACOSX_DEPLOYMENT_TARGET+x}" ||
        -n "${CODE_SIGN_IDENTITY+x}" ||
        -n "${CODE_SIGN_STYLE+x}" ||
        -n "${DEVELOPMENT_TEAM+x}" ||
        -n "${PROVISIONING_PROFILE_SPECIFIER+x}" ||
        -n "${CODE_SIGN_ENTITLEMENTS+x}" ||
        -n "${CODE_SIGN_INJECT_BASE_ENTITLEMENTS+x}" ||
        -n "${ENABLE_APP_SANDBOX+x}" ||
        -n "${ENABLE_HARDENED_RUNTIME+x}" ]]; then
    release_error 'unsafe Git or Xcode override environment is present'
    return 1
  fi
}

validate_version_component() {
  local value="${1-}"
  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

validate_executable_name() {
  [[ "${1-}" == "СберВакансии" ]]
}

validate_output_directory() {
  local repository_root="${1-}"
  local candidate="${2-}"
  local canonical_repository canonical_candidate canonical_home candidate_parent

  if [[ -z "$repository_root" || -z "$candidate" ]]; then
    release_error 'output-directory validation received an empty path'
    return 1
  fi
  canonical_repository="$(release_canonical_path "$repository_root")" || return 1
  canonical_candidate="$(release_canonical_path "$candidate")" || return 1
  canonical_home="$(release_python home)" || return 1

  if [[ "$canonical_candidate" == "/" ||
        "$canonical_candidate" == "/Users" ||
        "$canonical_candidate" == "$canonical_home" ||
        "$canonical_candidate" == "$canonical_repository" ||
        "$canonical_candidate" == "$canonical_repository/"* ]]; then
    release_error 'output directory is unsafe or inside the source repository'
    return 1
  fi
  if [[ -e "$canonical_candidate" && ! -d "$canonical_candidate" ]]; then
    release_error 'output path exists and is not a directory'
    return 1
  fi
  if [[ ! -e "$canonical_candidate" ]]; then
    candidate_parent="$(release_canonical_path "$(dirname "$canonical_candidate")")" || return 1
    if [[ ! -d "$candidate_parent" ]]; then
      release_error 'output directory parent does not exist'
      return 1
    fi
  fi
  printf '%s\n' "$canonical_candidate"
}

release_materialize_build_source() {
  local canonical_repository canonical_work observed_identity
  local expected_source archive gitlink_count project_candidate verifier_candidate
  local project_path verifier_path

  if [[ ! "${RELEASE_SOURCE_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]]; then
    release_error 'build-source materialization requires a full source commit OID'
    return 1
  fi
  if [[ -z "${REPOSITORY_ROOT:-}" || -z "${RELEASE_WORK_ROOT:-}" ||
        -z "${RELEASE_WORK_IDENTITY:-}" || -z "${RELEASE_LOG_DIR:-}" ]]; then
    release_error 'build-source materialization is missing owned release context'
    return 1
  fi
  if [[ ! -d "$REPOSITORY_ROOT" || -L "$REPOSITORY_ROOT" ||
        ! -d "$RELEASE_WORK_ROOT" || -L "$RELEASE_WORK_ROOT" ]]; then
    release_error 'build-source repository or work root has an unsafe type'
    return 1
  fi
  canonical_repository="$(release_canonical_path "$REPOSITORY_ROOT")" || return 1
  canonical_work="$(release_canonical_path "$RELEASE_WORK_ROOT")" || return 1
  if [[ "$canonical_repository" != "$REPOSITORY_ROOT" ||
        "$canonical_work" != "$RELEASE_WORK_ROOT" ||
        "$canonical_work" == "$canonical_repository" ||
        "$canonical_work" == "$canonical_repository/"* ]]; then
    release_error 'build-source work root is not distinct from the authoritative repository'
    return 1
  fi
  observed_identity="$(/usr/bin/stat -f '%d:%i' "$canonical_work")" || return 1
  if [[ "$observed_identity" != "$RELEASE_WORK_IDENTITY" ]]; then
    release_error 'build-source work-root identity changed'
    return 1
  fi

  expected_source="$canonical_work/source"
  if [[ -e "$expected_source" || -L "$expected_source" ]]; then
    release_error 'isolated build source already exists'
    return 1
  fi
  /bin/mkdir -m 700 "$expected_source" || return 1
  BUILD_SOURCE_ROOT="$(release_canonical_path "$expected_source")" || return 1
  if [[ "$BUILD_SOURCE_ROOT" != "$expected_source" ||
        "$BUILD_SOURCE_ROOT" != "$canonical_work/"* ||
        "$BUILD_SOURCE_ROOT" == "$canonical_repository" ||
        "$BUILD_SOURCE_ROOT" == "$canonical_repository/"* ||
        -L "$BUILD_SOURCE_ROOT" ]]; then
    release_error 'isolated build source escaped the owned work root'
    return 1
  fi

  gitlink_count="$(/usr/bin/git -C "$canonical_repository" ls-tree -r --full-tree \
      "$RELEASE_SOURCE_COMMIT" | /usr/bin/awk '$1 == "160000" { count += 1 } END { print count + 0 }')" || return 1
  if [[ "$gitlink_count" != "0" ]]; then
    release_error 'source commit contains a gitlink; isolated materialization refused'
    return 1
  fi

  archive="$canonical_work/source.tar"
  if [[ -e "$archive" || -L "$archive" ]]; then
    release_error 'build-source archive path already exists'
    return 1
  fi
  if ! /usr/bin/git -C "$canonical_repository" archive --format=tar \
      --output="$archive" "$RELEASE_SOURCE_COMMIT"; then
    release_error 'committed build-source archive creation failed'
    return 1
  fi
  if ! /usr/bin/tar -xf "$archive" -C "$BUILD_SOURCE_ROOT"; then
    release_error 'committed build-source archive extraction failed'
    return 1
  fi
  if [[ ! -d "$BUILD_SOURCE_ROOT" || -L "$BUILD_SOURCE_ROOT" ]]; then
    release_error 'isolated build source changed type after extraction'
    return 1
  fi
  if /usr/bin/find "$BUILD_SOURCE_ROOT" -name .git -print -quit | /usr/bin/grep -q .; then
    release_error 'isolated build source unexpectedly contains .git'
    return 1
  fi
  project_candidate="$BUILD_SOURCE_ROOT/HHVacancySber/HHVacancySber.xcodeproj"
  verifier_candidate="$BUILD_SOURCE_ROOT/scripts/verify_release_entitlements.py"
  project_path="$(release_canonical_path "$project_candidate")" || return 1
  verifier_path="$(release_canonical_path "$verifier_candidate")" || return 1
  if [[ ! -d "$project_candidate" || -L "$project_candidate" ||
        "$project_path" != "$BUILD_SOURCE_ROOT/"* ||
        ! -f "$verifier_candidate" || -L "$verifier_candidate" ||
        "$verifier_path" != "$BUILD_SOURCE_ROOT/"* ]]; then
    release_error 'isolated project or verifier provenance check failed'
    return 1
  fi
  {
    printf 'SOURCE_COMMIT=%s\n' "$RELEASE_SOURCE_COMMIT"
    printf 'PROJECT_PATH=HHVacancySber/HHVacancySber.xcodeproj\n'
    printf 'VERIFIER_PATH=scripts/verify_release_entitlements.py\n'
    printf 'MATERIALIZED=yes\n'
    printf 'AUTHORITATIVE_DISTINCT=yes\n'
    printf 'BUILD_SOURCE_WITHIN_WORK_ROOT=yes\n'
    printf 'GIT_DIRECTORY=absent\n'
  } > "$RELEASE_LOG_DIR/build-source-materialization.txt"
}

release_xcodebuild() {
  /usr/bin/xcodebuild "$@"
}

release_run_show_build_settings() {
  (cd "$BUILD_SOURCE_ROOT" && release_xcodebuild \
    -project HHVacancySber/HHVacancySber.xcodeproj \
    -scheme HHVacancySber \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$RELEASE_WORK_ROOT/DerivedData" \
    -disableAutomaticPackageResolution \
    -showBuildSettings)
}

release_run_strict_release_build() {
  (cd "$BUILD_SOURCE_ROOT" && release_xcodebuild -quiet \
    -project HHVacancySber/HHVacancySber.xcodeproj \
    -scheme HHVacancySber \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$RELEASE_WORK_ROOT/DerivedData" \
    -disableAutomaticPackageResolution \
    SWIFT_STRICT_CONCURRENCY=complete \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    build)
}

release_create_work_root() {
  local repository_root="${1-}"
  local output_root="${2-}"
  local canonical_repository canonical_output canonical_parent candidate
  local output_device work_device base

  if [[ -z "$repository_root" || -z "$output_root" ||
        ! -d "$output_root" || -L "$output_root" ]]; then
    release_error 'work-root creation received an unsafe path'
    return 1
  fi
  canonical_repository="$(release_canonical_path "$repository_root")" || return 1
  canonical_output="$(release_canonical_path "$output_root")" || return 1
  canonical_parent="$(release_canonical_path "$(dirname "$canonical_output")")" || return 1
  output_device="$(/usr/bin/stat -f '%d' "$canonical_output")" || return 1

  candidate="$(/usr/bin/mktemp -d "$canonical_parent/.hhvacancysber-release.XXXXXX")" || return 1
  RELEASE_WORK_ROOT="$(release_canonical_path "$candidate")" || return 1
  base="$(basename "$RELEASE_WORK_ROOT")"
  work_device="$(/usr/bin/stat -f '%d' "$RELEASE_WORK_ROOT")" || return 1
  if [[ "$RELEASE_WORK_ROOT" != "$candidate" ||
        "$(dirname "$RELEASE_WORK_ROOT")" != "$canonical_parent" ||
        "$base" != .hhvacancysber-release.* ||
        ! -d "$RELEASE_WORK_ROOT" || -L "$RELEASE_WORK_ROOT" ||
        "$RELEASE_WORK_ROOT" == "$canonical_output" ||
        "$RELEASE_WORK_ROOT" == "$canonical_output/"* ||
        "$canonical_output" == "$RELEASE_WORK_ROOT/"* ||
        "$RELEASE_WORK_ROOT" == "$canonical_repository" ||
        "$RELEASE_WORK_ROOT" == "$canonical_repository/"* ||
        "$canonical_repository" == "$RELEASE_WORK_ROOT/"* ||
        "$work_device" != "$output_device" ]]; then
    release_error "created work root failed topology authentication and is retained: $candidate"
    return 1
  fi
  /bin/chmod 700 "$RELEASE_WORK_ROOT" || return 1
  RELEASE_WORK_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$RELEASE_WORK_ROOT")" || return 1
  printf '%s\n' "$RELEASE_WORK_ROOT"
}

release_report_retained_work() {
  local categories="" item label
  if [[ "${RELEASE_RETENTION_REPORTED:-0}" -eq 1 ||
        -z "${RELEASE_WORK_ROOT:-}" ]]; then
    return 0
  fi
  RELEASE_RETENTION_REPORTED=1
  for item in \
      'source:source' \
      'DerivedData:DerivedData' \
      'source-payload:source-payload' \
      'logs:audit-logs' \
      'writable-mount:writable-mountpoint' \
      'readonly-mount:readonly-mountpoint' \
      'source.tar:source-archive'; do
    label="${item#*:}"
    item="${item%%:*}"
    if [[ -e "$RELEASE_WORK_ROOT/$item" || -L "$RELEASE_WORK_ROOT/$item" ]]; then
      if [[ -n "$categories" ]]; then categories="$categories,"; fi
      categories="$categories$label"
    fi
  done
  if [[ -f "$RELEASE_WORK_ROOT/HHVacancySber-writable.dmg" &&
        ! -L "$RELEASE_WORK_ROOT/HHVacancySber-writable.dmg" ]]; then
    if [[ -n "$categories" ]]; then categories="$categories,"; fi
    categories="${categories}writable-UDRW-image"
  fi
  if /usr/bin/find "$RELEASE_WORK_ROOT" -mindepth 1 -maxdepth 1 -type f \
      -name '*.dmg' ! -name 'HHVacancySber-writable.dmg' \
      -print -quit | /usr/bin/grep -q .; then
    if [[ -n "$categories" ]]; then categories="$categories,"; fi
    categories="${categories}converted-UDZO-image"
  fi
  if /usr/bin/find "$RELEASE_WORK_ROOT" -mindepth 1 -maxdepth 1 -type f \
      \( -name '*.sha256' -o -name '*.manifest.json' \) -print -quit | /usr/bin/grep -q .; then
    if [[ -n "$categories" ]]; then categories="$categories,"; fi
    categories="${categories}release-sidecars"
  fi
  if [[ -z "$categories" ]]; then categories=empty; fi
  printf '%s\n' 'SAFE AUTOMATIC CLEANUP NOT IMPLEMENTED — MACOS 13 PRIMITIVES INSUFFICIENT'
  printf 'MANUAL_CLEANUP_REQUIRED=yes\n'
  printf 'RETAINED_WORK_ROOT=%s\n' "$RELEASE_WORK_ROOT"
  printf 'RETAINED_WORK_ROOT_KIND=release-build-and-packaging-evidence\n'
  printf 'RETAINED_WORK_ROOT_CONTAINS=%s\n' "$categories"
}

release_authenticate_work_root() {
  local work_root="${1-}" canonical_work observed_identity
  if [[ -z "$work_root" ||
        -z "${RELEASE_WORK_ROOT:-}" ||
        -z "${RELEASE_WORK_IDENTITY:-}" ||
        ! -d "$work_root" || -L "$work_root" ]]; then
    release_error 'invocation-owned work-root context is incomplete or unsafe'
    return 1
  fi
  canonical_work="$(release_canonical_path "$work_root")" || return 1
  observed_identity="$(/usr/bin/stat -f '%d:%i' "$canonical_work")" || return 1
  if [[ "$canonical_work" != "$work_root" ||
        "$canonical_work" != "$RELEASE_WORK_ROOT" ||
        "$observed_identity" != "$RELEASE_WORK_IDENTITY" ]]; then
    release_error 'invocation-owned work-root identity changed'
    return 1
  fi
}

release_authenticate_owned_image_path() {
  local image_path="${1-}" owned_root="${2-}" expected_leaf="${3-}"
  local required_state="${4-}" canonical_image canonical_owned
  if [[ -z "$image_path" || -z "$owned_root" || -z "$expected_leaf" ||
        ! -d "$owned_root" || -L "$owned_root" ||
        "$expected_leaf" == */* ]]; then
    release_error 'owned image-path authentication received invalid context'
    return 1
  fi
  release_authenticate_work_root "$owned_root" || return 1
  canonical_image="$(release_canonical_path "$image_path")" || return 1
  canonical_owned="$(release_canonical_path "$owned_root")" || return 1
  if [[ "$canonical_image" != "$canonical_owned/$expected_leaf" ]]; then
    release_error 'image path is outside its invocation-owned location'
    return 1
  fi
  case "$required_state" in
    absent)
      if [[ -e "$image_path" || -L "$image_path" ]]; then
        release_error "image destination already exists and is retained: $image_path"
        return 1
      fi
      ;;
    file)
      if [[ ! -f "$image_path" || -L "$image_path" ]]; then
        release_error "owned image is missing, linked, or not regular: $image_path"
        return 1
      fi
      ;;
    *)
      release_error 'owned image-path authentication requires absent or file state'
      return 1
      ;;
  esac
}

release_prepare_mountpoint() {
  local mountpoint="${1-}" work_root="${2-}" expected_leaf="${3-}"
  local canonical_mount canonical_work
  if [[ -z "$mountpoint" || -z "$work_root" || -z "$expected_leaf" ||
        ! -d "$work_root" || -L "$work_root" ||
        "${RELEASE_ATTACH_SUCCEEDED:-0}" -ne 0 ||
        "$expected_leaf" == */* ||
        -e "$mountpoint" || -L "$mountpoint" ]]; then
    release_error "mountpoint destination is not fresh and safe: $mountpoint"
    return 1
  fi
  release_authenticate_work_root "$work_root" || return 1
  canonical_mount="$(release_canonical_path "$mountpoint")" || return 1
  canonical_work="$(release_canonical_path "$work_root")" || return 1
  if [[ "$canonical_mount" != "$canonical_work/$expected_leaf" ]]; then
    release_error 'mountpoint destination is outside the invocation-owned work root'
    return 1
  fi
  /bin/mkdir -m 700 "$mountpoint" || return 1
  if [[ ! -d "$mountpoint" || -L "$mountpoint" ||
        "$(release_canonical_path "$mountpoint")" != "$canonical_mount" ]]; then
    release_error "created mountpoint failed authentication and is retained: $mountpoint"
    return 1
  fi
  RELEASE_MOUNTPOINT="$canonical_mount"
  RELEASE_MOUNTPOINT_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$canonical_mount")" || return 1
  RELEASE_MOUNTED_ROOT_IDENTITY=""
  printf 'MOUNTPOINT=%s\nMOUNTPOINT_UNDERLAY_IDENTITY=%s\n' \
    "$RELEASE_MOUNTPOINT" "$RELEASE_MOUNTPOINT_IDENTITY"
}

release_detach_attached_image() {
  local label="${1-}" log_prefix="${2-}"
  local detached_device expected_leaf observed_underlay observation detach_status
  if [[ -z "$label" || -z "$log_prefix" ||
        "${RELEASE_ATTACH_SUCCEEDED:-0}" -ne 1 ||
        "${RELEASE_DETACH_ATTEMPTED:-0}" -ne 0 ||
        ! "${RELEASE_ATTACHED_DEVICE:-}" =~ ^/dev/disk[0-9]+(s[0-9]+)?$ ||
        -z "${RELEASE_MOUNTED_ROOT_IDENTITY:-}" ]]; then
    release_error "$label detach context is incomplete or already attempted"
    return 1
  fi
  case "${RELEASE_ATTACHMENT_KIND:-}:$label" in
    writable:writable-image)
      expected_leaf=writable-mount
      ;;
    readonly:readonly-image)
      expected_leaf=readonly-mount
      ;;
    *)
      release_error "$label does not match the authenticated attachment phase"
      return 1
      ;;
  esac
  release_authenticate_presentation_root \
    "$RELEASE_MOUNTPOINT" "$RELEASE_WORK_ROOT" \
    "$expected_leaf" "$RELEASE_MOUNTED_ROOT_IDENTITY" || return 1
  detached_device="$RELEASE_ATTACHED_DEVICE"
  printf '/usr/bin/hdiutil detach %s\n' "$detached_device" \
    > "$RELEASE_LOG_DIR/${log_prefix}.command" || return 1
  RELEASE_DETACH_ATTEMPTED=1
  if /usr/bin/hdiutil detach "$detached_device" \
      > "$RELEASE_LOG_DIR/${log_prefix}.stdout" \
      2> "$RELEASE_LOG_DIR/${log_prefix}.stderr"; then
    printf 'EXIT_STATUS=0\n' > "$RELEASE_LOG_DIR/${log_prefix}.status" || return 1
  else
    detach_status=$?
    printf 'EXIT_STATUS=%s\n' "$detach_status" \
      > "$RELEASE_LOG_DIR/${log_prefix}.status" || {
        release_error "$label detach status evidence could not be written"
        return "$detach_status"
      }
    release_error "$label normal detach failed for $detached_device"
    return "$detach_status"
  fi

  for ((observation = 1; observation <= 20; observation++)); do
    observed_underlay=""
    if [[ ! -e "$detached_device" && ! -L "$detached_device" &&
          -d "$RELEASE_MOUNTPOINT" && ! -L "$RELEASE_MOUNTPOINT" ]]; then
      observed_underlay="$(/usr/bin/stat -f '%d:%i' "$RELEASE_MOUNTPOINT")" || return 1
      if [[ "$observed_underlay" == "$RELEASE_MOUNTPOINT_IDENTITY" ]]; then
        break
      fi
    fi
    if [[ "$observation" -lt 20 ]]; then /bin/sleep 0.1; fi
  done
  if [[ "$observation" -gt 20 ]]; then
    release_error "$label device remains present or mountpoint underlay was not restored after normal detach"
    return 1
  fi
  observed_underlay="$(/usr/bin/stat -f '%d:%i' "$RELEASE_MOUNTPOINT")" || return 1
  if [[ "$observed_underlay" != "$RELEASE_MOUNTPOINT_IDENTITY" ]]; then
    release_error "$label mountpoint underlay identity was not restored"
    return 1
  fi
  if ! release_remove_empty_mountpoint \
      "$RELEASE_MOUNTPOINT" "$RELEASE_MOUNTPOINT_IDENTITY" "$RELEASE_WORK_ROOT"; then
    return 1
  fi
  {
    printf 'DETACH_LABEL=%s\n' "$label"
    printf 'DETACHED_DEVICE=%s\n' "$detached_device"
    printf 'DEVICE_ABSENT=yes\n'
    printf 'MOUNTPOINT_UNMOUNTED=yes\n'
    printf 'MOUNTPOINT_UNDERLAY_IDENTITY_RESTORED=yes\n'
    printf 'MOUNTPOINT_RMDIR=authenticated-empty-success\n'
  } > "$RELEASE_LOG_DIR/${log_prefix}-evidence.txt" || return 1
  RELEASE_ATTACH_SUCCEEDED=0
  RELEASE_ATTACHED_DEVICE=""
  RELEASE_MOUNTED_ROOT_IDENTITY=""
  RELEASE_ATTACHMENT_KIND=""
  RELEASE_MOUNTPOINT=""
  RELEASE_MOUNTPOINT_IDENTITY=""
  RELEASE_DETACH_ATTEMPTED=0
}

release_remove_empty_mountpoint() {
  local mountpoint="${1-}" expected_identity="${2-}" work_root="${3-}"
  local canonical_mount canonical_work observed_identity
  if [[ -z "$mountpoint" || -z "$expected_identity" || -z "$work_root" ||
        ! -d "$mountpoint" || -L "$mountpoint" ]]; then
    release_error "mountpoint is missing or has an unsafe type; retained: $mountpoint"
    return 1
  fi
  release_authenticate_work_root "$work_root" || return 1
  canonical_mount="$(release_canonical_path "$mountpoint")" || return 1
  canonical_work="$(release_canonical_path "$work_root")" || return 1
  observed_identity="$(/usr/bin/stat -f '%d:%i' "$canonical_mount")" || return 1
  if [[ "$canonical_mount" != "$mountpoint" ||
        "$canonical_mount" != "$canonical_work/"* ||
        "$observed_identity" != "$expected_identity" ]]; then
    release_error "mountpoint identity authentication failed; retained: $mountpoint"
    return 1
  fi
  if /usr/bin/find "$canonical_mount" -mindepth 1 -maxdepth 1 -print -quit | /usr/bin/grep -q .; then
    release_error "mountpoint is not empty; retained: $mountpoint"
    return 1
  fi
  if ! /bin/rmdir "$canonical_mount" || [[ -e "$canonical_mount" || -L "$canonical_mount" ]]; then
    release_error "exact empty mountpoint removal failed; retained: $mountpoint"
    return 1
  fi
}

release_create_lock_owner() {
  local source_commit="${1-}" owner_path canonical_lock observed_lock_identity
  if [[ "${RELEASE_LOCK_ACQUIRED:-0}" -ne 1 ||
        -z "${RELEASE_LOCK_DIR:-}" || -z "${RELEASE_LOCK_IDENTITY:-}" ]]; then
    release_error 'lock-owner creation is missing an authenticated lock directory'
    return 1
  fi
  canonical_lock="$(release_canonical_path "$RELEASE_LOCK_DIR")" || return 1
  observed_lock_identity="$(/usr/bin/stat -f '%d:%i' "$canonical_lock")" || return 1
  if [[ "$canonical_lock" != "$RELEASE_LOCK_DIR" || -L "$RELEASE_LOCK_DIR" ||
        ! -d "$RELEASE_LOCK_DIR" ||
        "$observed_lock_identity" != "$RELEASE_LOCK_IDENTITY" ]]; then
    release_error 'lock-directory identity changed before owner creation'
    return 1
  fi
  RELEASE_LOCK_OWNER_PARENT="$canonical_lock"
  RELEASE_LOCK_OWNER_NAME=owner
  owner_path="$RELEASE_LOCK_OWNER_PARENT/$RELEASE_LOCK_OWNER_NAME"
  if [[ -e "$owner_path" || -L "$owner_path" ]]; then
    release_error "lock owner path already exists; lock retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  RELEASE_LOCK_OWNER_NONCE="$(/usr/bin/uuidgen)"
  ( umask 077
    set -o noclobber
    printf 'PID=%s\nSOURCE_COMMIT=%s\nOWNER_NONCE=%s\n' \
      "$$" "$source_commit" "$RELEASE_LOCK_OWNER_NONCE" > "$owner_path"
  ) || return 1
  if [[ ! -f "$owner_path" || -L "$owner_path" ]]; then
    release_error "created lock owner is not a regular file; lock retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  RELEASE_LOCK_OWNER_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$owner_path")" || return 1
  RELEASE_LOCK_OWNER_LINK_COUNT="$(/usr/bin/stat -f '%l' "$owner_path")" || return 1
  RELEASE_LOCK_OWNER_SHA256="$(/usr/bin/shasum -a 256 "$owner_path" | /usr/bin/awk '{print $1}')" || return 1
  if [[ "$RELEASE_LOCK_OWNER_LINK_COUNT" != "1" ||
        ! "$RELEASE_LOCK_OWNER_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    release_error "created lock owner has unsafe identity; lock retained: $RELEASE_LOCK_DIR"
    return 1
  fi
}

release_acquire_lock() {
  local lock_directory="${1-}"
  if [[ -z "$lock_directory" ]]; then
    release_error 'release lock path is empty'
    return 1
  fi
  RELEASE_LOCK_DIR="$lock_directory"
  if ! /bin/mkdir -m 700 "$RELEASE_LOCK_DIR"; then
    release_error "release lock already exists; manual inspection required: $RELEASE_LOCK_DIR"
    return 1
  fi
  RELEASE_LOCK_ACQUIRED=1
  RELEASE_LOCK_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$RELEASE_LOCK_DIR")" || return 1
}

release_release_lock_owner() {
  local owner_path observed_lock_identity observed_owner_identity
  local observed_link_count observed_sha256
  if [[ "${RELEASE_LOCK_ACQUIRED:-0}" -ne 1 ]]; then return 0; fi
  if [[ "${RELEASE_ALLOW_LOCK_RELEASE:-0}" -ne 1 ]]; then
    release_error "release lock retained for manual inspection: $RELEASE_LOCK_DIR"
    release_error 'MANUAL_LOCK_RECOVERY_REQUIRED=yes'
    return 0
  fi
  if [[ -z "${RELEASE_LOCK_OWNER_PARENT:-}" ||
        "${RELEASE_LOCK_OWNER_NAME:-}" != owner ||
        "$RELEASE_LOCK_OWNER_PARENT" != "$RELEASE_LOCK_DIR" ||
        ! -d "$RELEASE_LOCK_DIR" || -L "$RELEASE_LOCK_DIR" ]]; then
    release_error "lock-owner context authentication failed; lock retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  observed_lock_identity="$(/usr/bin/stat -f '%d:%i' "$RELEASE_LOCK_DIR")" || return 1
  if [[ "$observed_lock_identity" != "$RELEASE_LOCK_IDENTITY" ]]; then
    release_error "lock-directory identity authentication failed; lock retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  owner_path="$RELEASE_LOCK_OWNER_PARENT/$RELEASE_LOCK_OWNER_NAME"
  if [[ ! -f "$owner_path" || -L "$owner_path" ]]; then
    release_error "lock owner is missing or not a regular file; lock retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  observed_owner_identity="$(/usr/bin/stat -f '%d:%i' "$owner_path")" || return 1
  observed_link_count="$(/usr/bin/stat -f '%l' "$owner_path")" || return 1
  observed_sha256="$(/usr/bin/shasum -a 256 "$owner_path" | /usr/bin/awk '{print $1}')" || return 1
  if [[ "$observed_owner_identity" != "$RELEASE_LOCK_OWNER_IDENTITY" ||
        "$observed_link_count" != "$RELEASE_LOCK_OWNER_LINK_COUNT" ||
        "$observed_link_count" != "1" ||
        "$observed_sha256" != "$RELEASE_LOCK_OWNER_SHA256" ||
        -z "$RELEASE_LOCK_OWNER_NONCE" ]] ||
     ! /usr/bin/grep -Fqx "OWNER_NONCE=$RELEASE_LOCK_OWNER_NONCE" "$owner_path"; then
    release_error "lock-owner exact-file authentication failed; lock retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  if [[ -n "${RELEASE_LOG_DIR:-}" && -d "$RELEASE_LOG_DIR" && ! -L "$RELEASE_LOG_DIR" ]]; then
    {
      printf 'LOCK_DIRECTORY=%s\n' "$RELEASE_LOCK_DIR"
      printf 'LOCK_DIRECTORY_IDENTITY_MATCH=yes\n'
      printf 'OWNER_PARENT_CONTAINMENT_MATCH=yes\n'
      printf 'OWNER_TYPE=regular-file\n'
      printf 'OWNER_IDENTITY_MATCH=yes\n'
      printf 'OWNER_LINK_COUNT_MATCH=yes\n'
      printf 'OWNER_NONCE_MATCH=yes\n'
      printf 'OWNER_SHA256_MATCH=yes\n'
    } > "$RELEASE_LOG_DIR/lock-owner-release-authentication.txt"
  fi
  if ! (cd "$RELEASE_LOCK_DIR" && /bin/rm -f -- "$RELEASE_LOCK_OWNER_NAME") ||
        [[ -e "$owner_path" || -L "$owner_path" ]]; then
    release_error "authenticated lock owner unlink failed; lock retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  observed_lock_identity="$(/usr/bin/stat -f '%d:%i' "$RELEASE_LOCK_DIR")" || return 1
  if [[ "$observed_lock_identity" != "$RELEASE_LOCK_IDENTITY" ]] ||
     /usr/bin/find "$RELEASE_LOCK_DIR" -mindepth 1 -maxdepth 1 -print -quit | /usr/bin/grep -q .; then
    release_error "release lock is changed or nonempty; retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  if ! /bin/rmdir "$RELEASE_LOCK_DIR" || [[ -e "$RELEASE_LOCK_DIR" || -L "$RELEASE_LOCK_DIR" ]]; then
    release_error "exact empty release-lock removal failed; retained: $RELEASE_LOCK_DIR"
    return 1
  fi
  RELEASE_LOCK_ACQUIRED=0
  if [[ -n "${RELEASE_LOG_DIR:-}" && -d "$RELEASE_LOG_DIR" && ! -L "$RELEASE_LOG_DIR" ]]; then
    printf 'OWNER_UNLINK=authenticated-success\nLOCK_RMDIR=authenticated-empty-success\n' \
      > "$RELEASE_LOG_DIR/lock-release-result.txt"
  fi
}

parse_target_build_settings() {
  local settings_file="${1-}"
  local target="${2-HHVacancySber}"
  local evidence_file="${3-}"
  if [[ -n "$evidence_file" ]]; then
    release_python parse-settings "$settings_file" "$target" "$evidence_file"
  else
    release_python parse-settings "$settings_file" "$target"
  fi
}

validate_release_settings() {
  local settings_file="${1-}"
  local parsed
  parsed="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/hhvacancysber-settings.XXXXXX")" || return 1
  if ! parse_target_build_settings "$settings_file" HHVacancySber > "$parsed"; then
    /bin/rm -f -- "$parsed"
    return 1
  fi
  if ! release_python settings-validate "$parsed"; then
    /bin/rm -f -- "$parsed"
    return 1
  fi
  /bin/rm -f -- "$parsed"
}

write_release_readme() {
  local destination="${1-}"
  printf '%s\n' \
    'СберВакансии' \
    '=============' \
    '' \
    'СберВакансии — настольное приложение для macOS, предназначенное для поиска,' \
    'просмотра и сохранения вакансий HeadHunter.' \
    '' \
    'Приложение не является официальным продуктом HeadHunter.' \
    '' \
    'ВОЗМОЖНОСТИ' \
    '-----------' \
    '' \
    '• поиск вакансий и просмотр результатов в единой вертикальной ленте;' \
    '• загрузка подробного описания вакансии по запросу;' \
    '• сохранение избранных вакансий на этом Mac;' \
    '• экспорт отдельной вакансии в PDF;' \
    '• пакетный экспорт выбранных вакансий в PDF;' \
    '• автоматическое разбиение больших PDF-подборок на несколько файлов.' \
    '' \
    'УСТАНОВКА' \
    '---------' \
    '' \
    '1. Перетащите приложение «СберВакансии» на значок «Программы».' \
    '2. Откройте папку «Программы».' \
    '3. Запустите «СберВакансии».' \
    '' \
    'СИСТЕМНЫЕ ТРЕБОВАНИЯ' \
    '--------------------' \
    '' \
    '• macOS 13 или новее;' \
    '• Mac с Apple silicon (arm64);' \
    '• подключение к интернету для поиска и загрузки вакансий.' \
    '' \
    'ЛОКАЛЬНЫЕ ДАННЫЕ' \
    '----------------' \
    '' \
    'Избранные вакансии и пользовательские настройки сохраняются локально на этом' \
    'Mac.' \
    '' \
    'ПОДПИСЬ СБОРКИ' \
    '--------------' \
    '' \
    'Эта сборка подписана ad hoc и не нотарифицирована Apple. При первом запуске' \
    'macOS может показать стандартное предупреждение безопасности. Используйте' \
    'только сборку, полученную из доверенного источника.' \
    > "$destination"
}

release_authenticate_presentation_root() {
  local candidate="${1-}" owned_root="${2-}" expected_leaf="${3-}"
  local expected_identity="${4-}"
  local canonical_candidate canonical_owned observed_identity
  if [[ -z "$candidate" || -z "$owned_root" || -z "$expected_leaf" ||
        ! -d "$candidate" || -L "$candidate" ||
        ! -d "$owned_root" || -L "$owned_root" ]]; then
    release_error 'Finder presentation root is missing, linked, or invalid'
    return 1
  fi
  release_authenticate_work_root "$owned_root" || return 1
  canonical_candidate="$(release_canonical_path "$candidate")" || return 1
  canonical_owned="$(release_canonical_path "$owned_root")" || return 1
  if [[ "$canonical_candidate" != "$canonical_owned/$expected_leaf" ]]; then
    release_error 'Finder presentation root is outside the invocation-owned location'
    return 1
  fi
  if [[ -n "$expected_identity" ]]; then
    observed_identity="$(/usr/bin/stat -f '%d:%i' "$canonical_candidate")" || return 1
    if [[ "$observed_identity" != "$expected_identity" ]]; then
      release_error 'Finder presentation root identity changed'
      return 1
    fi
  fi
}

release_run_with_timeout() {
  local timeout_seconds="${1-}"
  shift || return 2
  if [[ ! "$timeout_seconds" =~ ^[0-9]+([.][0-9]+)?$ || "$#" -eq 0 ]]; then
    release_error 'external timeout runner received invalid arguments'
    return 2
  fi
  /usr/bin/python3 -I -c '
import subprocess
import sys

timeout = float(sys.argv[1])
try:
    completed = subprocess.run(sys.argv[2:], timeout=timeout, check=False)
except subprocess.TimeoutExpired:
    print("EXTERNAL_PROCESS_TIMEOUT_SECONDS=" + sys.argv[1], file=sys.stderr)
    raise SystemExit(124)
raise SystemExit(completed.returncode)
' "$timeout_seconds" "$@"
}

release_customize_finder_layout() {
  local target="${1-}" owned_root="${2-}" expected_leaf="${3-}"
  local expected_identity="${4-}"
  release_authenticate_presentation_root \
    "$target" "$owned_root" "$expected_leaf" "$expected_identity" || return 1
  release_run_with_timeout 310 /usr/bin/osascript - "$target" <<'APPLESCRIPT'
on run argv
  if (count of argv) is not 1 then error "expected one mounted-volume path"
  set presentationPath to item 1 of argv
  set presentationFolder to POSIX file presentationPath as alias
  with timeout of 300 seconds
    tell application "Finder"
      set matchingWindowCount to 0
      repeat with windowIndex from 1 to count of Finder windows
        try
          set candidateWindow to Finder window windowIndex
          set candidatePath to POSIX path of (target of candidateWindow as alias)
          if candidatePath is presentationPath or candidatePath is (presentationPath & "/") then
            set matchingWindowCount to matchingWindowCount + 1
          end if
        end try
      end repeat
      if matchingWindowCount is not 0 then error "presentation window is already open"
      set presentationWindow to make new Finder window to presentationFolder
      set current view of presentationWindow to icon view
      set toolbar visible of presentationWindow to false
      set statusbar visible of presentationWindow to false
      set pathbar visible of presentationWindow to false
      set presentationOptions to icon view options of presentationWindow
      set icon size of presentationOptions to 48
      set arrangement of presentationOptions to arranged by name
      set shows item info of presentationOptions to true
      set shows icon preview of presentationOptions to true
      set bounds of presentationWindow to {100, 100, 1500, 1000}
    end tell
  end timeout
end run
APPLESCRIPT
}

release_persist_live_finder_layout() {
  local target="${1-}" owned_root="${2-}" expected_leaf="${3-}"
  local expected_identity="${4-}"
  release_authenticate_presentation_root \
    "$target" "$owned_root" "$expected_leaf" "$expected_identity" || return 1
  release_run_with_timeout 310 /usr/bin/osascript - "$target" <<'APPLESCRIPT'
on run argv
  if (count of argv) is not 1 then error "expected one presentation path"
  set presentationPath to item 1 of argv
  set presentationFolder to POSIX file presentationPath as alias
  with timeout of 60 seconds
    tell application "Finder"
      set matchingWindowCount to 0
      repeat with windowIndex from 1 to count of Finder windows
        try
          set candidateWindow to Finder window windowIndex
          set candidatePath to POSIX path of (target of candidateWindow as alias)
          if candidatePath is presentationPath or candidatePath is (presentationPath & "/") then
            set matchingWindowCount to matchingWindowCount + 1
          end if
        end try
      end repeat
      if matchingWindowCount is not 1 then error "expected exactly one presentation window"
      ignoring application responses
        update presentationFolder without registering applications
      end ignoring
    end tell
    delay 2
  end timeout
end run
APPLESCRIPT
}

release_classify_finder_customization_result() {
  local exit_status="${1-}" stderr_path="${2-}"
  local nonempty_lines error_numbers
  if [[ ! "$exit_status" =~ ^[0-9]+$ ||
        -z "$stderr_path" || ! -f "$stderr_path" || -L "$stderr_path" ]]; then
    printf 'FINDER_CUSTOMIZATION_STATUS=fatal_error\nFINDER_CUSTOMIZATION_RETRY_COUNT=0\n'
    return 1
  fi
  if [[ "$exit_status" -eq 0 ]]; then
    printf 'FINDER_CUSTOMIZATION_STATUS=success\nFINDER_CUSTOMIZATION_RETRY_COUNT=0\n'
    return 0
  fi
  nonempty_lines="$(/usr/bin/awk 'NF { count += 1 } END { print count + 0 }' "$stderr_path")"
  error_numbers="$(/usr/bin/grep -Eo -- '-[0-9]+' "$stderr_path" || true)"
  if [[ "$nonempty_lines" == "1" &&
        "$error_numbers" == "-1712" ]] &&
     /usr/bin/grep -Eq \
       '^([0-9]+:[0-9]+: )?execution error: .+\(-1712\)[[:space:]]*$' \
       "$stderr_path" &&
     /usr/bin/grep -Eqi 'AppleEvent' "$stderr_path" &&
     ! /usr/bin/grep -Eqi \
       'automation|permission|denied|syntax|invalid|missing|not running|not authorized|not permitted' \
       "$stderr_path"; then
    printf 'FINDER_CUSTOMIZATION_STATUS=indeterminate_timeout\nFINDER_CUSTOMIZATION_RETRY_COUNT=0\n'
    return 0
  fi
  printf 'FINDER_CUSTOMIZATION_STATUS=fatal_error\nFINDER_CUSTOMIZATION_RETRY_COUNT=0\n'
  return 1
}

release_wait_for_stable_ds_store() {
  local target="${1-}" owned_root="${2-}"
  local maximum_observations="${3-20}" observation_delay="${4-0.25}"
  local expected_leaf="${5-}" expected_identity="${6-}"
  local required_stable_observations="${7-2}" stable_observations=0
  local ds_store observation identity identity_after device inode mode size digest
  local first_observed_utc=""
  local previous_device="" previous_inode="" previous_mode="" previous_size="" previous_digest=""
  release_authenticate_presentation_root \
    "$target" "$owned_root" "$expected_leaf" "$expected_identity" || return 1
  if [[ ! "$maximum_observations" =~ ^[1-9][0-9]*$ ||
        ! "$required_stable_observations" =~ ^[2-9][0-9]*$ ||
        "$required_stable_observations" -gt "$maximum_observations" ]]; then
    release_error 'invalid .DS_Store observation bound'
    return 1
  fi
  ds_store="$target/.DS_Store"
  for ((observation = 1; observation <= maximum_observations; observation++)); do
    release_authenticate_presentation_root \
      "$target" "$owned_root" "$expected_leaf" "$expected_identity" || return 1
    if [[ -L "$ds_store" ]]; then
      release_error '.DS_Store is a symlink'
      return 1
    fi
    if [[ -f "$ds_store" ]]; then
      identity="$(/usr/bin/stat -f '%d:%i:%p:%z' "$ds_store")" || return 1
      IFS=: read -r device inode mode size <<< "$identity"
      if [[ "$size" -gt 0 ]]; then
        if [[ -z "$first_observed_utc" ]]; then
          first_observed_utc="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" || return 1
        fi
        digest="$(/usr/bin/shasum -a 256 "$ds_store" | /usr/bin/awk '{print $1}')" || return 1
        identity_after="$(/usr/bin/stat -f '%d:%i:%p:%z' "$ds_store")" || return 1
        if [[ "$identity" == "$identity_after" ]]; then
          if [[ "$device" == "$previous_device" &&
                "$inode" == "$previous_inode" &&
                "$mode" == "$previous_mode" &&
                "$size" == "$previous_size" &&
                "$digest" == "$previous_digest" ]]; then
            stable_observations=$((stable_observations + 1))
            if [[ "$stable_observations" -ge "$required_stable_observations" ]]; then
              printf '%s\n' \
                "DS_STORE_OBSERVATIONS=$observation" \
                "DS_STORE_STABLE_OBSERVATIONS=$stable_observations" \
                "DS_STORE_FIRST_OBSERVED_UTC=$first_observed_utc" \
                "DS_STORE_DEVICE=$device" \
                "DS_STORE_INODE=$inode" \
                "DS_STORE_MODE=$mode" \
                "DS_STORE_SIZE=$size" \
                "DS_STORE_SHA256=$digest"
              return 0
            fi
          else
            stable_observations=1
          fi
          previous_device="$device"
          previous_inode="$inode"
          previous_mode="$mode"
          previous_size="$size"
          previous_digest="$digest"
        else
          stable_observations=0
          previous_device=""
          previous_inode=""
          previous_mode=""
          previous_size=""
          previous_digest=""
        fi
      else
        stable_observations=0
        previous_device=""
        previous_inode=""
        previous_mode=""
        previous_size=""
        previous_digest=""
      fi
    elif [[ -e "$ds_store" ]]; then
      release_error '.DS_Store is not a regular file'
      return 1
    else
      stable_observations=0
      previous_device=""
      previous_inode=""
      previous_mode=""
      previous_size=""
      previous_digest=""
    fi
    if [[ "$observation" -lt "$maximum_observations" ]]; then
      /bin/sleep "$observation_delay"
    fi
  done
  release_error '.DS_Store did not become nonempty and stable within the bounded observation period'
  return 1
}

release_read_finder_layout() {
  local target="${1-}" owned_root="${2-}" expected_leaf="${3-}"
  local window_mode="${4-existing}" expected_identity="${5-}"
  release_authenticate_presentation_root \
    "$target" "$owned_root" "$expected_leaf" "$expected_identity" || return 1
  if [[ "$window_mode" != "existing" && "$window_mode" != "open" ]]; then
    release_error 'invalid Finder readback window mode'
    return 1
  fi
  release_run_with_timeout 310 /usr/bin/osascript - "$target" "$window_mode" <<'APPLESCRIPT'
on run argv
  if (count of argv) is not 2 then error "expected presentation path and window mode"
  set presentationPath to item 1 of argv
  set windowMode to item 2 of argv
  set presentationFolder to POSIX file presentationPath as alias
  with timeout of 60 seconds
    tell application "Finder"
      if windowMode is "open" then
        set reviewWindow to make new Finder window to presentationFolder
      else
        set reviewWindow to missing value
        set matchingWindowCount to 0
        repeat with windowIndex from 1 to count of Finder windows
          try
            set candidateWindow to Finder window windowIndex
            set candidatePath to POSIX path of (target of candidateWindow as alias)
            if candidatePath is presentationPath or candidatePath is (presentationPath & "/") then
              set reviewWindow to candidateWindow
              set matchingWindowCount to matchingWindowCount + 1
            end if
          end try
        end repeat
        if matchingWindowCount is not 1 then error "expected exactly one presentation window"
      end if
      set observedView to current view of reviewWindow
      set observedToolbar to toolbar visible of reviewWindow
      set observedStatusbar to statusbar visible of reviewWindow
      set observedPathbar to pathbar visible of reviewWindow
      set observedBounds to bounds of reviewWindow
      set reviewOptions to icon view options of reviewWindow
      set observedIconSize to icon size of reviewOptions
      set observedArrangement to arrangement of reviewOptions
      set observedItemInfo to shows item info of reviewOptions
      set observedPreview to shows icon preview of reviewOptions
      set observedLeft to item 1 of observedBounds
      set observedTop to item 2 of observedBounds
      set observedRight to item 3 of observedBounds
      set observedBottom to item 4 of observedBounds
      set observedWidth to observedRight - observedLeft
      set observedHeight to observedBottom - observedTop
      if observedView is not icon view then error "current view is not icon view"
      if observedIconSize is not 48 then error "icon size is not 48"
      if observedArrangement is not arranged by name then error "arrangement is not by name"
      if observedToolbar then error "toolbar is visible"
      if observedStatusbar then error "status bar is visible"
      if observedPathbar then error "path bar is visible"
      if not observedItemInfo then error "item information is hidden"
      if not observedPreview then error "icon preview is disabled"
      if observedWidth < 1400 then error "window width is below 1400"
      if observedHeight < 900 then error "window height is below 900"
      set evidenceText to "CURRENT_VIEW=icon view" & linefeed & ¬
        "ICON_SIZE=48" & linefeed & ¬
        "ARRANGEMENT=arranged by name" & linefeed & ¬
        "TOOLBAR_VISIBLE=false" & linefeed & ¬
        "STATUS_BAR_VISIBLE=false" & linefeed & ¬
        "PATH_BAR_VISIBLE=false" & linefeed & ¬
        "ITEM_INFORMATION_VISIBLE=true" & linefeed & ¬
        "ICON_PREVIEW_ENABLED=true" & linefeed & ¬
        "WINDOW_BOUNDS=" & (observedLeft as text) & "," & (observedTop as text) & "," & (observedRight as text) & "," & (observedBottom as text) & linefeed & ¬
        "WINDOW_WIDTH=" & (observedWidth as text) & linefeed & ¬
        "WINDOW_HEIGHT=" & (observedHeight as text) & linefeed & ¬
        "READBACK_STATUS=pass"
      return evidenceText
    end tell
  end timeout
end run
APPLESCRIPT
}

release_close_finder_window() {
  local target="${1-}" owned_root="${2-}" expected_leaf="${3-}"
  local expected_identity="${4-}" close_status
  release_authenticate_presentation_root \
    "$target" "$owned_root" "$expected_leaf" "$expected_identity" || return 1
  release_run_with_timeout 310 /usr/bin/osascript - "$target" <<'APPLESCRIPT'
on run argv
  if (count of argv) is not 1 then error "expected one presentation path"
  set presentationPath to item 1 of argv
  with timeout of 60 seconds
    tell application "Finder"
      set exactWindow to missing value
      set matchingWindowCount to 0
      repeat with windowIndex from 1 to count of Finder windows
        try
          set candidateWindow to Finder window windowIndex
          set candidatePath to POSIX path of (target of candidateWindow as alias)
          if candidatePath is presentationPath or candidatePath is (presentationPath & "/") then
            set exactWindow to candidateWindow
            set matchingWindowCount to matchingWindowCount + 1
          end if
        end try
      end repeat
      if matchingWindowCount is not 1 then error "expected exactly one presentation window"
      ignoring application responses
        close exactWindow
      end ignoring
    end tell
  end timeout
  return "CLOSE_REQUESTED=true"
end run
APPLESCRIPT
  close_status=$?
  if [[ "$close_status" -eq 0 ]]; then
    /bin/sleep 1
  fi
  return "$close_status"
}

release_validate_finder_lifecycle() {
  local customization_status="${1-}" writable_readback="${2-}"
  local close_count="${3-}" post_close_stability="${4-}"
  local writable_detach="${5-}" conversion="${6-}"
  local final_readback="${7-}" final_detach="${8-}"
  if [[ "$customization_status" != "success" &&
        "$customization_status" != "indeterminate_timeout" ]] ||
     [[ "$writable_readback" != "pass" ||
        "$close_count" != "1" ||
        "$post_close_stability" != "pass" ||
        "$writable_detach" != "pass" ||
        "$conversion" != "pass" ||
        "$final_readback" != "pass" ||
        "$final_detach" != "pass" ]]; then
    release_error 'Finder lifecycle evidence is incomplete or invalid'
    return 1
  fi
  printf 'FINDER_LIFECYCLE_ACCEPTED=yes\n'
}

release_validate_finder_readback() {
  local readback_status="${1-}" view="${2-}" icon_size="${3-}" arrangement="${4-}"
  local toolbar="${5-}" statusbar="${6-}" pathbar="${7-}"
  local item_information="${8-}" icon_preview="${9-}"
  local window_width="${10-}" window_height="${11-}"
  if [[ "$readback_status" != "pass" ||
        "$view" != "icon view" ||
        "$icon_size" != "48" ||
        "$arrangement" != "arranged by name" ||
        "$toolbar" != "false" ||
        "$statusbar" != "false" ||
        "$pathbar" != "false" ||
        "$item_information" != "true" ||
        "$icon_preview" != "true" ||
        ! "$window_width" =~ ^[0-9]+$ ||
        ! "$window_height" =~ ^[0-9]+$ ]] ||
     [[ "$window_width" -lt 1400 || "$window_height" -lt 900 ]]; then
    release_error 'Finder readback evidence is incomplete or invalid'
    return 1
  fi
  printf 'FINDER_READBACK_ACCEPTED=yes\n'
}

generate_release_manifest() {
  release_python manifest-generate "$@"
}

verify_release_manifest() {
  release_python manifest-verify "$@"
}

verify_exact_payload_root() {
  release_python exact-root "$1"
}

release_link_exclusive() {
  release_python link-exclusive "$1" "$2"
}

release_same_file() {
  release_python same-file "$1" "$2"
}

release_remove_owned_link() {
  local source="${1-}"
  local destination="${2-}"
  if [[ -e "$destination" || -L "$destination" ]]; then
    if release_same_file "$source" "$destination"; then
      if ! /bin/rm -f -- "$destination"; then
        release_error "failed to remove invocation-owned publication link: $destination"
        return 1
      fi
    fi
  fi
}

publish_no_clobber() {
  local source_one="${1-}" destination_one="${2-}"
  local source_two="${3-}" destination_two="${4-}"
  local source_three="${5-}" destination_three="${6-}"

  if [[ -e "$destination_one" || -L "$destination_one" ||
        -e "$destination_two" || -L "$destination_two" ||
        -e "$destination_three" || -L "$destination_three" ]]; then
    release_error 'publication collision detected before linking'
    return 1
  fi
  if ! release_link_exclusive "$source_one" "$destination_one"; then
    release_error 'DMG publication link failed'
    return 1
  fi
  if ! release_link_exclusive "$source_two" "$destination_two"; then
    if release_remove_owned_link "$source_one" "$destination_one"; then
      release_error 'checksum publication link failed; invocation-owned link rolled back'
    else
      release_error 'checksum publication link failed; invocation-owned rollback incomplete'
    fi
    return 1
  fi
  if ! release_link_exclusive "$source_three" "$destination_three"; then
    local rollback_status=0
    if ! release_remove_owned_link "$source_two" "$destination_two"; then
      rollback_status=1
    fi
    if ! release_remove_owned_link "$source_one" "$destination_one"; then
      rollback_status=1
    fi
    if [[ "$rollback_status" -eq 0 ]]; then
      release_error 'manifest publication link failed; invocation-owned links rolled back'
    else
      release_error 'manifest publication link failed; invocation-owned rollback incomplete'
    fi
    return 1
  fi
}

release_rollback_publication() {
  local rollback_status=0
  if ! release_remove_owned_link "$5" "$6"; then
    rollback_status=1
  fi
  if ! release_remove_owned_link "$3" "$4"; then
    rollback_status=1
  fi
  if ! release_remove_owned_link "$1" "$2"; then
    rollback_status=1
  fi
  return "$rollback_status"
}

release_cancel_pending_publication() {
  if [[ "${RELEASE_PUBLICATION_PENDING:-0}" -eq 0 ]]; then
    return 0
  fi
  if release_rollback_publication \
      "$RELEASE_TEMP_DMG" "$RELEASE_FINAL_DMG" \
      "$RELEASE_TEMP_CHECKSUM" "$RELEASE_FINAL_CHECKSUM" \
      "$RELEASE_TEMP_MANIFEST" "$RELEASE_FINAL_MANIFEST"; then
    RELEASE_PUBLICATION_PENDING=0
    return 0
  fi
  release_error 'invocation-owned publication rollback is incomplete'
  return 1
}

release_validate_repository_status_text() {
  local repository_root="$1" status_text="$2"
  local line relative candidate

  if [[ ! -d "$repository_root" || -L "$repository_root" ]]; then
    release_error 'repository-status validation received an unsafe repository path'
    return 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    case "$line" in
      '?? scripts/release.sh')
        relative='scripts/release.sh'
        ;;
      '?? scripts/tests/test_release_script.py')
        relative='scripts/tests/test_release_script.py'
        ;;
      *)
        release_error 'Source repository is not clean; release packaging refused.'
        return 1
        ;;
    esac
    candidate="$repository_root/$relative"
    if [[ ! -f "$candidate" || -L "$candidate" ]]; then
      release_error 'approved untracked release-pipeline path has an unsafe type'
      return 1
    fi
  done <<< "$status_text"
}

release_validate_repository_status_file() {
  local repository_root="$1" status_file="$2" status_text
  if [[ ! -f "$status_file" || -L "$status_file" ]]; then
    release_error 'repository-status validation received an unsafe status path'
    return 1
  fi
  status_text="$(< "$status_file")"
  release_validate_repository_status_text "$repository_root" "$status_text"
}

release_capture_and_validate_repository_status() {
  local destination="$1" status_text
  if ! status_text="$(/usr/bin/git -C "$REPOSITORY_ROOT" status \
      --porcelain=v1 --untracked-files=all)"; then
    release_error 'unable to inspect source repository status'
    return 1
  fi
  if [[ "$destination" != /dev/null ]]; then
    printf '%s\n' "$status_text" > "$destination"
  fi
  release_validate_repository_status_text "$REPOSITORY_ROOT" "$status_text"
}

release_record_repository_status() {
  local checkpoint="$1"
  local safe_checkpoint
  safe_checkpoint="${checkpoint//[^A-Za-z0-9._-]/-}"
  release_capture_and_validate_repository_status \
    "$RELEASE_LOG_DIR/repository-${safe_checkpoint}.porcelain"
  /usr/bin/git -C "$REPOSITORY_ROOT" diff --exit-code \
    > "$RELEASE_LOG_DIR/repository-${safe_checkpoint}.diff" 2>&1 || {
      release_error 'tracked source changes detected during release packaging'
      return 1
    }
  /usr/bin/git -C "$REPOSITORY_ROOT" diff --cached --exit-code \
    > "$RELEASE_LOG_DIR/repository-${safe_checkpoint}.cached.diff" 2>&1 || {
      release_error 'staged source changes detected during release packaging'
      return 1
    }
  /usr/bin/git -C "$REPOSITORY_ROOT" diff --exit-code -- Package.resolved \
    > "$RELEASE_LOG_DIR/repository-${safe_checkpoint}.package.diff" 2>&1 || {
      release_error 'Package.resolved changed during release packaging'
      return 1
    }
  if [[ "$(/usr/bin/git -C "$REPOSITORY_ROOT" rev-parse HEAD)" != "$RELEASE_SOURCE_COMMIT" ]]; then
    release_error 'source HEAD changed during release packaging'
    return 1
  fi
  if [[ -n "${REPOSITORY_BASELINE_SNAPSHOT:-}" ]]; then
    release_python repository-snapshot "$REPOSITORY_ROOT" \
      > "$RELEASE_LOG_DIR/repository-${safe_checkpoint}.snapshot.json"
    if ! release_python repository-snapshot-check \
        "$REPOSITORY_BASELINE_SNAPSHOT" \
        "$RELEASE_LOG_DIR/repository-${safe_checkpoint}.snapshot.json" \
        "$safe_checkpoint"; then
      return 1
    fi
  fi
  {
    printf 'CHECKPOINT=%s\n' "$safe_checkpoint"
    printf 'GIT_STATUS=clean-or-approved-untracked-release-pipeline\n'
    printf 'TRACKED_DIFF=clean\n'
    printf 'CACHED_DIFF=clean\n'
    printf 'HEAD=unchanged\n'
    printf 'SEMANTIC_SNAPSHOT=match\n'
  } > "$RELEASE_LOG_DIR/repository-${safe_checkpoint}.integrity"
}

release_attest_environment() {
  local macos_version macos_major architecture xcode_output xcode_version swift_version
  macos_version="$(/usr/bin/sw_vers -productVersion)"
  macos_major="${macos_version%%.*}"
  architecture="$(/usr/bin/uname -m)"
  if ! xcode_output="$(/usr/bin/xcodebuild -version 2> "$RELEASE_LOG_DIR/xcode-version.stderr")"; then
    release_error 'Xcode version inspection failed'
    return 1
  fi
  xcode_version="$(printf '%s\n' "$xcode_output" | /usr/bin/awk '/^Xcode / { print $2 }')"
  swift_version="$(/usr/bin/xcrun swift --version 2>&1)"
  {
    printf 'macOS=%s\n' "$macos_version"
    printf 'architecture=%s\n' "$architecture"
    printf 'Xcode=%s\n' "$xcode_version"
    printf 'Swift=%s\n' "$swift_version"
  } > "$RELEASE_LOG_DIR/environment.txt"
  if [[ "$macos_major" != "13" ]]; then
    release_error 'acceptance requires macOS 13.x'
    return 1
  fi
  if [[ "$architecture" != "arm64" ]]; then
    release_error 'acceptance requires arm64 hardware'
    return 1
  fi
  if [[ "$xcode_version" != "15.2" ]]; then
    release_error 'acceptance requires Xcode 15.2'
    return 1
  fi
  if [[ "$swift_version" != *"Swift version 5.9"* ]]; then
    release_error 'acceptance requires Swift 5.9.x'
    return 1
  fi
}

release_plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

release_validate_app() {
  local app="$1" label="$2"
  local expected_bundle="$3" expected_executable="$4"
  local expected_short="$5" expected_build="$6"
  local info_plist main_executable bundle_id short_version build_version executable
  local verifier_json entitlement_plist signature_metadata
  local relative path description architectures index kind
  local macho_count=0 main_found=0

  if [[ ! -d "$app" ]]; then
    release_error "$label application bundle is missing"
    return 1
  fi
  info_plist="$app/Contents/Info.plist"
  if [[ ! -f "$info_plist" ]]; then
    release_error "$label Info.plist is missing"
    return 1
  fi
  bundle_id="$(release_plist_value "$info_plist" CFBundleIdentifier)" || return 1
  short_version="$(release_plist_value "$info_plist" CFBundleShortVersionString)" || return 1
  build_version="$(release_plist_value "$info_plist" CFBundleVersion)" || return 1
  executable="$(release_plist_value "$info_plist" CFBundleExecutable)" || return 1
  if [[ -z "$bundle_id" || -z "$short_version" || -z "$build_version" || -z "$executable" ]]; then
    release_error "$label bundle identity contains an empty value"
    return 1
  fi
  if [[ "$bundle_id" != "$expected_bundle" ||
        "$executable" != "$expected_executable" ||
        "$short_version" != "$expected_short" ||
        "$build_version" != "$expected_build" ]]; then
    release_error "$label bundle identity does not match the built product contract"
    return 1
  fi
  if ! validate_version_component "$short_version" ||
     ! validate_version_component "$build_version" ||
     ! validate_executable_name "$executable"; then
    release_error "$label bundle contains an unsafe version or executable component"
    return 1
  fi
  main_executable="$app/Contents/MacOS/$executable"
  if [[ ! -f "$main_executable" || ! -x "$main_executable" ]]; then
    release_error "$label main executable is missing or not executable"
    return 1
  fi
  {
    printf 'CFBundleIdentifier=%s\n' "$bundle_id"
    printf 'CFBundleShortVersionString=%s\n' "$short_version"
    printf 'CFBundleVersion=%s\n' "$build_version"
    printf 'CFBundleExecutable=%s\n' "$executable"
  } > "$RELEASE_LOG_DIR/${label}.bundle.txt"

  verifier_json="$RELEASE_LOG_DIR/${label}.verifier.json"
  if ! /usr/bin/python3 -I "$BUILD_SOURCE_ROOT/scripts/verify_release_entitlements.py" \
      --app "$app" > "$verifier_json" 2> "$RELEASE_LOG_DIR/${label}.verifier.stderr"; then
    release_error "$label failed the committed release-entitlement verifier"
    return 1
  fi
  if ! release_python verifier-check "$verifier_json" "$main_executable"; then
    release_error "$label verifier JSON did not satisfy the Release contract"
    return 1
  fi

  if ! /usr/bin/codesign --verify --strict --deep --verbose=4 "$app" \
      > "$RELEASE_LOG_DIR/${label}.codesign-verify.stdout" \
      2> "$RELEASE_LOG_DIR/${label}.codesign-verify.stderr"; then
    release_error "$label failed strict/deep signature verification"
    return 1
  fi
  entitlement_plist="$RELEASE_LOG_DIR/${label}.entitlements.plist"
  if ! /usr/bin/codesign -d --entitlements :- --xml "$app" \
      > "$entitlement_plist" 2> "$RELEASE_LOG_DIR/${label}.entitlements.stderr"; then
    release_error "$label entitlements could not be extracted independently"
    return 1
  fi
  if ! release_python entitlements-check "$entitlement_plist" main; then
    release_error "$label independent entitlement contract failed"
    return 1
  fi
  signature_metadata="$RELEASE_LOG_DIR/${label}.signature.txt"
  if ! /usr/bin/codesign -dvv "$app" > /dev/null 2> "$signature_metadata"; then
    release_error "$label signature metadata inspection failed"
    return 1
  fi
  if ! release_python signature-check "$signature_metadata" "$app"; then
    release_error "$label signing model is not ad hoc with hardened runtime and without team/provisioning"
    return 1
  fi

  : > "$RELEASE_LOG_DIR/${label}.macho-inventory.txt"
  if ! release_python regular-files0 "$app" \
      > "$RELEASE_LOG_DIR/${label}.regular-files.list"; then
    release_error "$label regular-file inventory could not be completed"
    return 1
  fi
  index=0
  while IFS= read -r -d '' relative; do
    path="$app/$relative"
    if ! description="$(/usr/bin/file -b "$path")"; then
      release_error "$label contains an uninspectable regular file: $relative"
      return 1
    fi
    if [[ "$description" != *"Mach-O"* ]]; then
      continue
    fi
    index=$((index + 1))
    macho_count=$((macho_count + 1))
    if ! architectures="$(/usr/bin/lipo -archs "$path")"; then
      release_error "$label contains an uninspectable Mach-O: $relative"
      return 1
    fi
    if [[ "$architectures" != "arm64" ]]; then
      release_error "$label Mach-O is not arm64-only: $relative"
      return 1
    fi
    if [[ "$relative" == "Contents/MacOS/$expected_executable" ]]; then
      kind=main
      main_found=1
    else
      kind=nested
    fi
    printf '%s|%s\n' "$relative" "$architectures" \
      >> "$RELEASE_LOG_DIR/${label}.macho-inventory.txt"
    if ! /usr/bin/codesign --verify --strict --verbose=4 "$path" \
        > "$RELEASE_LOG_DIR/${label}.macho.${index}.codesign.stdout" \
        2> "$RELEASE_LOG_DIR/${label}.macho.${index}.codesign.stderr"; then
      release_error "$label Mach-O signature failed: $relative"
      return 1
    fi
    if ! /usr/bin/codesign -d --entitlements :- --xml "$path" \
        > "$RELEASE_LOG_DIR/${label}.macho.${index}.entitlements.plist" \
        2> "$RELEASE_LOG_DIR/${label}.macho.${index}.entitlements.stderr"; then
      release_error "$label Mach-O entitlements are uninspectable: $relative"
      return 1
    fi
    if ! release_python entitlements-check \
        "$RELEASE_LOG_DIR/${label}.macho.${index}.entitlements.plist" "$kind"; then
      release_error "$label Mach-O entitlement contract failed: $relative"
      return 1
    fi
    if ! /usr/bin/xcrun vtool -show-build "$path" \
        > "$RELEASE_LOG_DIR/${label}.macho.${index}.vtool.txt" \
        2> "$RELEASE_LOG_DIR/${label}.macho.${index}.vtool.stderr"; then
      release_error "$label Mach-O deployment metadata is uninspectable: $relative"
      return 1
    fi
    if ! release_python vtool-check \
        "$RELEASE_LOG_DIR/${label}.macho.${index}.vtool.txt" "$kind"; then
      release_error "$label Mach-O deployment contract failed: $relative"
      return 1
    fi
  done < "$RELEASE_LOG_DIR/${label}.regular-files.list"
  if [[ "$macho_count" -lt 1 || "$main_found" -ne 1 ]]; then
    release_error "$label main executable was not classified as exactly one Mach-O"
    return 1
  fi
  if ! release_python scan-controls "$app" "$RELEASE_LOG_DIR/${label}.test-controls.json"; then
    release_error "$label contains a Debug-only UI-test control identifier"
    return 1
  fi
}

release_cleanup_resources() {
  local cleanup_status=0
  local observed_identity
  if [[ "${RELEASE_CLEANUP_ATTEMPTED:-0}" -eq 1 ]]; then
    return "${RELEASE_CLEANUP_RESULT:-1}"
  fi
  RELEASE_CLEANUP_ATTEMPTED=1
  if [[ "${RELEASE_ATTACH_SUCCEEDED:-0}" -eq 1 ]]; then
    release_error "active image context is retained without automatic detach: ${RELEASE_ATTACHED_DEVICE:-unknown-device}"
    release_error "active mountpoint retained for manual inspection: ${RELEASE_MOUNTPOINT:-unknown-mountpoint}"
    RELEASE_CLEANUP_RESULT=1
    return 1
  fi
  if [[ -n "${RELEASE_WORK_ROOT:-}" ]]; then
    if [[ ! -d "$RELEASE_WORK_ROOT" || -L "$RELEASE_WORK_ROOT" ]]; then
      release_error 'owned work root is missing or changed type; cleanup refused'
      RELEASE_CLEANUP_RESULT=1
      return 1
    fi
    observed_identity="$(/usr/bin/stat -f '%d:%i' "$RELEASE_WORK_ROOT")" || return 1
    if [[ "$observed_identity" != "${RELEASE_WORK_IDENTITY:-}" ]]; then
      release_error 'owned work-root identity changed; cleanup refused'
      return 1
    fi
  fi
  if ! release_cancel_pending_publication; then
    cleanup_status=1
  fi
  if ! release_release_lock_owner; then
    cleanup_status=1
  fi
  RELEASE_CLEANUP_RESULT="$cleanup_status"
  return "$cleanup_status"
}

release_exit_trap() {
  local original_status="$1"
  local final_status="$original_status"
  trap - EXIT INT TERM HUP
  if ! release_cleanup_resources; then
    if [[ "$original_status" -eq 0 ]]; then
      final_status=1
    fi
  fi
  release_report_retained_work
  exit "$final_status"
}

main() {
  set -euo pipefail
  umask 022
  export PATH=/usr/bin:/bin:/usr/sbin:/sbin
  export LC_ALL=C
  export LANG=C

  local output_argument="" help_requested=0
  local show_status build_status create_status convert_status verify_status imageinfo_status attach_status
  local source_commit script_directory git_root parsed_output canonical_after_create
  local show_settings_stdout show_settings_json
  local setting_archs setting_active setting_deployment setting_sandbox setting_runtime setting_injection
  local setting_identity setting_style setting_entitlements setting_team setting_profile
  local setting_product setting_wrapper setting_build_dir setting_executable setting_bundle
  local built_app expected_app_count info_plist bundle_identifier bundle_short_version bundle_version bundle_executable
  local source_payload source_payload_identity source_payload_snapshot manifest_path
  local writable_image writable_image_initial_hash writable_image_hash writable_image_size
  local writable_mount readonly_mount temp_dmg dmg_basename checksum_basename manifest_basename
  local final_dmg final_checksum final_manifest temp_checksum temp_manifest dmg_hash
  local attach_plist diskinfo_plist final_count finder_status
  local customization_evidence customization_result
  local live_ds_store_stability post_close_ds_store_stability
  local ds_store_hash ds_store_hash_after_sync
  local finder_readback readback_status readback_view readback_icon_size readback_arrangement
  local readback_toolbar readback_statusbar readback_pathbar readback_item_information
  local readback_icon_preview readback_width readback_height mounted_ds_store_hash

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --help)
        help_requested=1
        shift
        ;;
      --output-dir)
        if [[ "$#" -lt 2 || -z "$2" ]]; then
          release_error '--output-dir requires a directory'
          return 2
        fi
        if [[ -n "$output_argument" ]]; then
          release_error '--output-dir may be supplied only once'
          return 2
        fi
        output_argument="$2"
        shift 2
        ;;
      *)
        release_error "unknown option: $1"
        return 2
        ;;
    esac
  done
  if [[ "$help_requested" -eq 1 ]]; then
    release_usage
    return 0
  fi
  if [[ -z "$output_argument" ]]; then
    release_error 'missing required --output-dir'
    return 2
  fi

  script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  REPOSITORY_ROOT="$(release_canonical_path "$script_directory/..")"
  release_reject_unsafe_environment
  git_root="$(/usr/bin/git -C "$REPOSITORY_ROOT" rev-parse --show-toplevel)" || {
    release_error 'release script is not inside a Git repository'
    return 1
  }
  git_root="$(release_canonical_path "$git_root")"
  if [[ "$git_root" != "$REPOSITORY_ROOT" ]]; then
    release_error 'derived repository root does not match Git root'
    return 1
  fi
  parsed_output="$(validate_output_directory "$REPOSITORY_ROOT" "$output_argument")" || return 1

  release_capture_and_validate_repository_status /dev/null
  /usr/bin/git -C "$REPOSITORY_ROOT" diff --exit-code >/dev/null || return 1
  /usr/bin/git -C "$REPOSITORY_ROOT" diff --cached --exit-code >/dev/null || return 1
  source_commit="$(/usr/bin/git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
  if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
    release_error 'source commit is not a full hexadecimal Git OID'
    return 1
  fi
  RELEASE_SOURCE_COMMIT="$source_commit"

  if [[ ! -d "$parsed_output" ]]; then
    /bin/mkdir "$parsed_output"
  fi
  canonical_after_create="$(validate_output_directory "$REPOSITORY_ROOT" "$parsed_output")" || return 1
  if [[ "$canonical_after_create" != "$parsed_output" ]]; then
    release_error 'output directory changed identity during creation'
    return 1
  fi
  RELEASE_OUTPUT_DIR="$parsed_output"
  RELEASE_LOCK_DIR="$RELEASE_OUTPUT_DIR/.hhvacancysber-release.lock"
  RELEASE_LOCK_ACQUIRED=0
  RELEASE_LOCK_IDENTITY=""
  RELEASE_LOCK_OWNER_PARENT=""
  RELEASE_LOCK_OWNER_NAME=""
  RELEASE_LOCK_OWNER_IDENTITY=""
  RELEASE_LOCK_OWNER_LINK_COUNT=""
  RELEASE_LOCK_OWNER_NONCE=""
  RELEASE_LOCK_OWNER_SHA256=""
  RELEASE_ALLOW_LOCK_RELEASE=0
  RELEASE_WORK_ROOT=""
  RELEASE_WORK_IDENTITY=""
  RELEASE_RETENTION_REPORTED=0
  RELEASE_CLEANUP_ATTEMPTED=0
  RELEASE_CLEANUP_RESULT=1
  RELEASE_LOG_DIR=""
  RELEASE_MOUNTPOINT=""
  RELEASE_MOUNTPOINT_IDENTITY=""
  RELEASE_MOUNTED_ROOT_IDENTITY=""
  RELEASE_ATTACH_SUCCEEDED=0
  RELEASE_ATTACHED_DEVICE=""
  RELEASE_DETACH_ATTEMPTED=0
  RELEASE_ATTACHMENT_KIND=""
  RELEASE_PUBLICATION_PENDING=0
  RELEASE_TEMP_DMG=""
  RELEASE_FINAL_DMG=""
  RELEASE_TEMP_CHECKSUM=""
  RELEASE_FINAL_CHECKSUM=""
  RELEASE_TEMP_MANIFEST=""
  RELEASE_FINAL_MANIFEST=""
  REPOSITORY_BASELINE_SNAPSHOT=""
  BUILD_SOURCE_ROOT=""
  if ! release_acquire_lock "$RELEASE_LOCK_DIR"; then return 1; fi
  trap 'release_exit_trap "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  release_create_lock_owner "$source_commit"
  release_create_work_root "$REPOSITORY_ROOT" "$RELEASE_OUTPUT_DIR" >/dev/null
  RELEASE_LOG_DIR="$RELEASE_WORK_ROOT/logs"
  /bin/mkdir -p \
    "$RELEASE_LOG_DIR" \
    "$RELEASE_WORK_ROOT/DerivedData" \
    "$RELEASE_WORK_ROOT/source-payload"
  {
    printf 'LOCK_DIRECTORY=%s\n' "$RELEASE_LOCK_DIR"
    printf 'LOCK_DIRECTORY_IDENTITY=%s\n' "$RELEASE_LOCK_IDENTITY"
    printf 'OWNER_PARENT=%s\n' "$RELEASE_LOCK_OWNER_PARENT"
    printf 'OWNER_NAME=%s\n' "$RELEASE_LOCK_OWNER_NAME"
    printf 'OWNER_TYPE=regular-file\n'
    printf 'OWNER_IDENTITY=%s\n' "$RELEASE_LOCK_OWNER_IDENTITY"
    printf 'OWNER_LINK_COUNT=%s\n' "$RELEASE_LOCK_OWNER_LINK_COUNT"
    printf 'OWNER_NONCE=%s\n' "$RELEASE_LOCK_OWNER_NONCE"
    printf 'OWNER_SHA256=%s\n' "$RELEASE_LOCK_OWNER_SHA256"
  } > "$RELEASE_LOG_DIR/lock-owner-creation.txt"
  REPOSITORY_BASELINE_SNAPSHOT="$RELEASE_LOG_DIR/repository-baseline.snapshot.json"
  release_python repository-snapshot "$REPOSITORY_ROOT" > "$REPOSITORY_BASELINE_SNAPSHOT"

  release_record_repository_status before-environment-inspection
  release_attest_environment
  release_record_repository_status before-showBuildSettings
  release_materialize_build_source

  show_settings_stdout="$RELEASE_LOG_DIR/showBuildSettings.stdout"
  {
    printf 'WORKING_DIRECTORY=%s\n' "$BUILD_SOURCE_ROOT"
    printf '%s\n' "/usr/bin/xcodebuild -project HHVacancySber/HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Release -destination platform=macOS,arch=arm64 -derivedDataPath $RELEASE_WORK_ROOT/DerivedData -disableAutomaticPackageResolution -showBuildSettings"
  } > "$RELEASE_LOG_DIR/showBuildSettings.command"
  if release_run_show_build_settings \
      > "$show_settings_stdout" 2> "$RELEASE_LOG_DIR/showBuildSettings.stderr"; then
    show_status=0
  else
    show_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$show_status" > "$RELEASE_LOG_DIR/showBuildSettings.status"
  if [[ "$show_status" -ne 0 ]]; then
    release_error 'xcodebuild -showBuildSettings failed'
    return "$show_status"
  fi
  show_settings_json="$RELEASE_LOG_DIR/release-settings.json"
  parse_target_build_settings \
    "$show_settings_stdout" \
    HHVacancySber \
    "$RELEASE_LOG_DIR/release-settings-parser-evidence.json" \
    > "$show_settings_json"
  release_python settings-validate "$show_settings_json"
  setting_archs="$(release_python json-get "$show_settings_json" ARCHS)"
  setting_active="$(release_python json-get "$show_settings_json" ONLY_ACTIVE_ARCH)"
  setting_deployment="$(release_python json-get "$show_settings_json" MACOSX_DEPLOYMENT_TARGET)"
  setting_sandbox="$(release_python json-get "$show_settings_json" ENABLE_APP_SANDBOX)"
  setting_runtime="$(release_python json-get "$show_settings_json" ENABLE_HARDENED_RUNTIME)"
  setting_injection="$(release_python json-get "$show_settings_json" CODE_SIGN_INJECT_BASE_ENTITLEMENTS)"
  setting_identity="$(release_python json-get "$show_settings_json" CODE_SIGN_IDENTITY)"
  setting_style="$(release_python json-get "$show_settings_json" CODE_SIGN_STYLE)"
  setting_entitlements="$(release_python json-get "$show_settings_json" CODE_SIGN_ENTITLEMENTS)"
  setting_team="$(release_python json-get "$show_settings_json" DEVELOPMENT_TEAM)"
  setting_profile="$(release_python json-get "$show_settings_json" PROVISIONING_PROFILE_SPECIFIER)"
  setting_product="$(release_python json-get "$show_settings_json" PRODUCT_NAME)"
  setting_wrapper="$(release_python json-get "$show_settings_json" WRAPPER_NAME)"
  setting_build_dir="$(release_python json-get "$show_settings_json" TARGET_BUILD_DIR)"
  setting_executable="$(release_python json-get "$show_settings_json" EXECUTABLE_NAME)"
  setting_bundle="$(release_python json-get "$show_settings_json" PRODUCT_BUNDLE_IDENTIFIER)"
  if ! validate_executable_name "$setting_executable"; then
    release_error 'effective executable name is unsafe'
    return 1
  fi
  {
    printf 'ARCHS=%s\n' "$setting_archs"
    printf 'ONLY_ACTIVE_ARCH=%s\n' "$setting_active"
    printf 'MACOSX_DEPLOYMENT_TARGET=%s\n' "$setting_deployment"
    printf 'ENABLE_APP_SANDBOX=%s\n' "$setting_sandbox"
    printf 'ENABLE_HARDENED_RUNTIME=%s\n' "$setting_runtime"
    printf 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=%s\n' "$setting_injection"
    printf 'CODE_SIGN_IDENTITY=%s\n' "$setting_identity"
    printf 'CODE_SIGN_STYLE=%s\n' "$setting_style"
    printf 'CODE_SIGN_ENTITLEMENTS=%s\n' "$setting_entitlements"
    printf 'DEVELOPMENT_TEAM=%s\n' "$setting_team"
    printf 'PROVISIONING_PROFILE_SPECIFIER=%s\n' "$setting_profile"
  } > "$RELEASE_LOG_DIR/effective-release-contract.txt"
  release_record_repository_status after-showBuildSettings

  {
    printf 'WORKING_DIRECTORY=%s\n' "$BUILD_SOURCE_ROOT"
    printf '%s\n' "/usr/bin/xcodebuild -quiet -project HHVacancySber/HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Release -destination platform=macOS,arch=arm64 -derivedDataPath $RELEASE_WORK_ROOT/DerivedData -disableAutomaticPackageResolution SWIFT_STRICT_CONCURRENCY=complete SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build"
  } > "$RELEASE_LOG_DIR/release-build.command"
  if release_run_strict_release_build \
      > "$RELEASE_LOG_DIR/release-build.stdout" 2> "$RELEASE_LOG_DIR/release-build.stderr"; then
    build_status=0
  else
    build_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$build_status" > "$RELEASE_LOG_DIR/release-build.status"
  if [[ "$build_status" -ne 0 ]]; then
    release_error 'strict Release build failed'
    return "$build_status"
  fi
  release_record_repository_status after-release-build

  setting_build_dir="$(release_canonical_path "$setting_build_dir")"
  if [[ "$setting_build_dir" != "$RELEASE_WORK_ROOT/DerivedData/"* ]]; then
    release_error 'effective TARGET_BUILD_DIR escapes the dedicated DerivedData root'
    return 1
  fi
  built_app="$setting_build_dir/$setting_wrapper"
  expected_app_count="$(/usr/bin/find "$setting_build_dir" -maxdepth 1 -type d -name "$setting_wrapper" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  if [[ "$expected_app_count" != "1" || ! -d "$built_app" ]]; then
    release_error 'exactly one expected application bundle was not produced'
    return 1
  fi
  info_plist="$built_app/Contents/Info.plist"
  bundle_identifier="$(release_plist_value "$info_plist" CFBundleIdentifier)"
  bundle_short_version="$(release_plist_value "$info_plist" CFBundleShortVersionString)"
  bundle_version="$(release_plist_value "$info_plist" CFBundleVersion)"
  bundle_executable="$(release_plist_value "$info_plist" CFBundleExecutable)"
  if [[ -z "$bundle_identifier" || -z "$bundle_short_version" || -z "$bundle_version" || -z "$bundle_executable" ]]; then
    release_error 'built application has incomplete bundle identity'
    return 1
  fi
  if [[ "$bundle_identifier" != "$setting_bundle" || "$bundle_executable" != "$setting_executable" ]]; then
    release_error 'built application identity differs from target build settings'
    return 1
  fi
  if ! validate_version_component "$bundle_short_version" || ! validate_version_component "$bundle_version"; then
    release_error 'bundle version is unsafe for deterministic output naming'
    return 1
  fi
  release_validate_app "$built_app" built "$bundle_identifier" "$bundle_executable" "$bundle_short_version" "$bundle_version"
  release_python snapshot "$built_app" > "$RELEASE_LOG_DIR/built.snapshot.json"
  release_record_repository_status after-built-app-verifier

  source_payload="$RELEASE_WORK_ROOT/source-payload"
  /usr/bin/ditto "$built_app" "$source_payload/СберВакансии.app"
  /bin/ln -s /Applications "$source_payload/Applications"
  /bin/chmod -h 0777 "$source_payload/Applications"
  write_release_readme "$source_payload/README.txt"
  release_validate_app "$source_payload/СберВакансии.app" staged "$bundle_identifier" "$bundle_executable" "$bundle_short_version" "$bundle_version"
  release_python snapshot "$source_payload/СберВакансии.app" > "$RELEASE_LOG_DIR/staged.snapshot.json"
  if ! /usr/bin/cmp -s "$RELEASE_LOG_DIR/built.snapshot.json" "$RELEASE_LOG_DIR/staged.snapshot.json"; then
    release_error 'staged application payload differs from the verified built application'
    return 1
  fi
  manifest_path="$source_payload/RELEASE-MANIFEST.json"
  generate_release_manifest "$source_payload" "$manifest_path" "$source_commit" "$bundle_identifier" "$bundle_short_version" "$bundle_version"
  release_python exact-entries \
    "$source_payload" \
    СберВакансии.app Applications README.txt RELEASE-MANIFEST.json \
    > "$RELEASE_LOG_DIR/source-payload-inventory.txt"
  verify_release_manifest "$source_payload" "$manifest_path" "$source_commit" \
    "$bundle_identifier" "$bundle_short_version" "$bundle_version"
  source_payload_identity="$(/usr/bin/stat -f '%d:%i' "$source_payload")"
  source_payload_snapshot="$RELEASE_LOG_DIR/source-payload-before.snapshot.json"
  release_python repository-snapshot "$source_payload" > "$source_payload_snapshot"
  {
    printf 'SOURCE_PAYLOAD=%s\n' "$source_payload"
    printf 'SOURCE_PAYLOAD_IDENTITY=%s\n' "$source_payload_identity"
    printf 'SOURCE_PAYLOAD_PHYSICAL_ENTRY_COUNT=4\n'
    printf 'SOURCE_PAYLOAD_HIDDEN_ENTRY_COUNT=0\n'
    printf 'SOURCE_PAYLOAD_DS_STORE=absent\n'
    printf 'SOURCE_PAYLOAD_FINDER_CUSTOMIZATION=prohibited\n'
  } > "$RELEASE_LOG_DIR/source-payload-identity.txt"

  writable_image="$RELEASE_WORK_ROOT/HHVacancySber-writable.dmg"
  release_authenticate_owned_image_path \
    "$writable_image" "$RELEASE_WORK_ROOT" HHVacancySber-writable.dmg absent
  {
    printf 'SOURCE_PAYLOAD_CANONICAL=%s\n' "$source_payload"
    printf 'SOURCE_PAYLOAD_IDENTITY=%s\n' "$source_payload_identity"
    printf '%s\n' "/usr/bin/hdiutil create -volname СберВакансии -fs HFS+ -format UDRW -srcfolder $source_payload $writable_image"
  } > "$RELEASE_LOG_DIR/writable-image-create.command"
  if /usr/bin/hdiutil create \
      -volname СберВакансии \
      -fs HFS+ \
      -format UDRW \
      -srcfolder "$source_payload" \
      "$writable_image" \
      > "$RELEASE_LOG_DIR/writable-image-create.stdout" \
      2> "$RELEASE_LOG_DIR/writable-image-create.stderr"; then
    create_status=0
  else
    create_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$create_status" \
    > "$RELEASE_LOG_DIR/writable-image-create.status"
  if [[ "$create_status" -ne 0 ]]; then
    release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — WRITABLE-IMAGE DESIGN FAILURE'
    return "$create_status"
  fi
  release_authenticate_owned_image_path \
    "$writable_image" "$RELEASE_WORK_ROOT" HHVacancySber-writable.dmg file
  writable_image_initial_hash="$(/usr/bin/shasum -a 256 "$writable_image" | /usr/bin/awk '{print $1}')"
  writable_image_size="$(/usr/bin/stat -f '%z' "$writable_image")"
  if ! /usr/bin/hdiutil imageinfo -plist "$writable_image" \
      > "$RELEASE_LOG_DIR/writable-image-imageinfo.plist" \
      2> "$RELEASE_LOG_DIR/writable-image-imageinfo.stderr" ||
     ! release_python imageinfo-check \
      "$RELEASE_LOG_DIR/writable-image-imageinfo.plist" UDRW; then
    release_error 'created writable image is not verified UDRW'
    return 1
  fi
  {
    printf 'WRITABLE_IMAGE=%s\n' "$writable_image"
    printf 'WRITABLE_IMAGE_FORMAT=UDRW\n'
    printf 'WRITABLE_IMAGE_FILESYSTEM=HFS+\n'
    printf 'WRITABLE_IMAGE_INITIAL_SHA256=%s\n' "$writable_image_initial_hash"
    printf 'WRITABLE_IMAGE_INITIAL_SIZE=%s\n' "$writable_image_size"
    printf 'WRITABLE_IMAGE_RETAINED=yes\n'
  } > "$RELEASE_LOG_DIR/writable-image-created.txt"
  release_python exact-entries \
    "$source_payload" \
    СберВакансии.app Applications README.txt RELEASE-MANIFEST.json \
    > "$RELEASE_LOG_DIR/source-payload-after-image-create.inventory.txt"
  release_python repository-snapshot "$source_payload" \
    > "$RELEASE_LOG_DIR/source-payload-after-image-create.snapshot.json"
  if ! /usr/bin/cmp -s "$source_payload_snapshot" \
      "$RELEASE_LOG_DIR/source-payload-after-image-create.snapshot.json"; then
    release_error 'source payload changed during writable-image creation'
    return 1
  fi
  release_record_repository_status after-writable-image-creation

  writable_mount="$RELEASE_WORK_ROOT/writable-mount"
  release_prepare_mountpoint \
    "$writable_mount" "$RELEASE_WORK_ROOT" writable-mount \
    > "$RELEASE_LOG_DIR/writable-mountpoint.txt"
  RELEASE_ATTACHMENT_KIND=writable
  RELEASE_DETACH_ATTEMPTED=0
  attach_plist="$RELEASE_LOG_DIR/writable-image-attach.plist"
  {
    printf '%s\n' "/usr/bin/hdiutil attach -readwrite -nobrowse -mountpoint $writable_mount -plist $writable_image"
  } > "$RELEASE_LOG_DIR/writable-image-attach.command"
  if /usr/bin/hdiutil attach \
      -readwrite \
      -nobrowse \
      -mountpoint "$writable_mount" \
      -plist \
      "$writable_image" \
      > "$attach_plist" \
      2> "$RELEASE_LOG_DIR/writable-image-attach.stderr"; then
    attach_status=0
    RELEASE_ATTACH_SUCCEEDED=1
  else
    attach_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$attach_status" \
    > "$RELEASE_LOG_DIR/writable-image-attach.status"
  if [[ "$attach_status" -ne 0 ]]; then
    release_error 'writable-image read-write attachment failed'
    return "$attach_status"
  fi
  RELEASE_ATTACHED_DEVICE="$(release_python attach-device "$attach_plist" "$writable_mount")" || {
    release_error 'writable-image device could not be identified; manual recovery required'
    return 1
  }
  RELEASE_MOUNTED_ROOT_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$writable_mount")"
  diskinfo_plist="$RELEASE_LOG_DIR/writable-diskutil-info.plist"
  if ! /usr/sbin/diskutil info -plist "$RELEASE_ATTACHED_DEVICE" \
      > "$diskinfo_plist" \
      2> "$RELEASE_LOG_DIR/writable-diskutil-info.stderr"; then
    release_error 'writable mounted-image device metadata inspection failed'
    return 1
  fi
  release_python writable-diskinfo-check \
    "$diskinfo_plist" "$RELEASE_ATTACHED_DEVICE" "$writable_mount" \
    > "$RELEASE_LOG_DIR/writable-diskutil-validation.txt"
  release_python exact-entries \
    "$writable_mount" \
    СберВакансии.app Applications README.txt RELEASE-MANIFEST.json \
    > "$RELEASE_LOG_DIR/writable-mounted-root-initial-inventory.txt" || {
      release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — WRITABLE MOUNT ROOT CONTAMINATED'
      return 1
    }

  printf 'FINDER_CUSTOMIZATION_INVOCATIONS=1\n' \
    > "$RELEASE_LOG_DIR/finder-customization-evidence.txt"
  if release_customize_finder_layout \
      "$writable_mount" "$RELEASE_WORK_ROOT" writable-mount \
      "$RELEASE_MOUNTED_ROOT_IDENTITY" \
      > "$RELEASE_LOG_DIR/finder-customization.stdout" \
      2> "$RELEASE_LOG_DIR/finder-customization.stderr"; then
    finder_status=0
  else
    finder_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$finder_status" > "$RELEASE_LOG_DIR/finder-customization.status"
  if ! customization_evidence="$(release_classify_finder_customization_result \
      "$finder_status" "$RELEASE_LOG_DIR/finder-customization.stderr")"; then
    printf '%s\n' "$customization_evidence" \
      >> "$RELEASE_LOG_DIR/finder-customization-evidence.txt"
    release_error 'writable-mounted-volume Finder customization failed closed'
    return "$finder_status"
  fi
  printf '%s\n' "$customization_evidence" \
    >> "$RELEASE_LOG_DIR/finder-customization-evidence.txt"
  customization_result="$(printf '%s\n' "$customization_evidence" |
    /usr/bin/awk -F= '$1 == "FINDER_CUSTOMIZATION_STATUS" {print $2}')"

  if ! release_persist_live_finder_layout \
      "$writable_mount" "$RELEASE_WORK_ROOT" writable-mount \
      "$RELEASE_MOUNTED_ROOT_IDENTITY" \
      > "$RELEASE_LOG_DIR/finder-live-persistence.stdout" \
      2> "$RELEASE_LOG_DIR/finder-live-persistence.stderr"; then
    release_error 'live Finder presentation persistence failed'
    return 1
  fi
  printf 'LIVE_FINDER_PRESENTATION_PERSISTENCE=pass\n' \
    > "$RELEASE_LOG_DIR/finder-live-persistence-evidence.txt"

  if ! live_ds_store_stability="$(release_wait_for_stable_ds_store \
      "$writable_mount" "$RELEASE_WORK_ROOT" 120 1 writable-mount \
      "$RELEASE_MOUNTED_ROOT_IDENTITY" 4 \
      2> "$RELEASE_LOG_DIR/finder-live-ds-store-stabilization.stderr")"; then
    release_error 'live Finder presentation metadata did not stabilize'
    return 1
  fi
  {
    printf 'LIVE_FINDER_DS_STORE_STABILITY=pass\n'
    printf '%s\n' "$live_ds_store_stability"
  } > "$RELEASE_LOG_DIR/finder-live-ds-store-stabilization.txt"

  if finder_readback="$(release_read_finder_layout \
      "$writable_mount" "$RELEASE_WORK_ROOT" writable-mount existing \
      "$RELEASE_MOUNTED_ROOT_IDENTITY" \
      2> "$RELEASE_LOG_DIR/finder-writable-readback.stderr")"; then
    finder_status=0
  else
    finder_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$finder_status" > "$RELEASE_LOG_DIR/finder-writable-readback.status"
  if [[ "$finder_status" -ne 0 ]]; then
    release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — WRITABLE-MOUNT FINDER READBACK FAILURE'
    return "$finder_status"
  fi
  readback_status="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "READBACK_STATUS" {print $2}')"
  readback_view="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "CURRENT_VIEW" {print $2}')"
  readback_icon_size="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "ICON_SIZE" {print $2}')"
  readback_arrangement="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "ARRANGEMENT" {print $2}')"
  readback_toolbar="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "TOOLBAR_VISIBLE" {print $2}')"
  readback_statusbar="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "STATUS_BAR_VISIBLE" {print $2}')"
  readback_pathbar="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "PATH_BAR_VISIBLE" {print $2}')"
  readback_item_information="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "ITEM_INFORMATION_VISIBLE" {print $2}')"
  readback_icon_preview="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "ICON_PREVIEW_ENABLED" {print $2}')"
  readback_width="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "WINDOW_WIDTH" {print $2}')"
  readback_height="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "WINDOW_HEIGHT" {print $2}')"
  if ! release_validate_finder_readback \
      "$readback_status" \
      "$readback_view" \
      "$readback_icon_size" \
      "$readback_arrangement" \
      "$readback_toolbar" \
      "$readback_statusbar" \
      "$readback_pathbar" \
      "$readback_item_information" \
      "$readback_icon_preview" \
      "$readback_width" \
      "$readback_height" \
      > "$RELEASE_LOG_DIR/finder-writable-readback-validation.txt"; then
    release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — WRITABLE-MOUNT FINDER READBACK FAILURE'
    return 1
  fi
  {
    printf '%s\n' "$finder_readback"
    printf 'WRITABLE_FINDER_READBACK=pass\n'
  } > "$RELEASE_LOG_DIR/finder-writable-readback.txt"

  if release_close_finder_window \
      "$writable_mount" "$RELEASE_WORK_ROOT" writable-mount \
      "$RELEASE_MOUNTED_ROOT_IDENTITY" \
      > "$RELEASE_LOG_DIR/finder-writable-close.stdout" \
      2> "$RELEASE_LOG_DIR/finder-writable-close.stderr"; then
    finder_status=0
  else
    finder_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$finder_status" > "$RELEASE_LOG_DIR/finder-writable-close.status"
  if [[ "$finder_status" -ne 0 ]]; then
    release_error 'writable mounted-volume exact-window close failed'
    return "$finder_status"
  fi
  printf 'FINDER_WINDOW_CLOSE_REQUEST_COUNT=1\n' \
    > "$RELEASE_LOG_DIR/finder-writable-close-evidence.txt"

  /bin/sync
  printf 'POST_CLOSE_FILESYSTEM_SYNC=pass\n' \
    > "$RELEASE_LOG_DIR/post-close-filesystem-sync.txt"

  if ! post_close_ds_store_stability="$(release_wait_for_stable_ds_store \
      "$writable_mount" "$RELEASE_WORK_ROOT" 120 1 writable-mount \
      "$RELEASE_MOUNTED_ROOT_IDENTITY" 8 \
      2> "$RELEASE_LOG_DIR/post-close-ds-store-stabilization.stderr")"; then
    release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — POST-CLOSE DS_STORE STABILITY FAILURE'
    return 1
  fi
  {
    printf 'POST_CLOSE_DS_STORE_STABILITY=pass\n'
    printf '%s\n' "$post_close_ds_store_stability"
  } > "$RELEASE_LOG_DIR/post-close-ds-store-stabilization.txt"
  ds_store_hash="$(printf '%s\n' "$post_close_ds_store_stability" |
    /usr/bin/awk -F= '$1 == "DS_STORE_SHA256" {print $2}')"
  verify_exact_payload_root "$writable_mount"
  /usr/bin/cmp -s "$source_payload/README.txt" "$writable_mount/README.txt" || {
    release_error 'writable mounted README bytes differ from source payload'
    return 1
  }
  /usr/bin/cmp -s "$manifest_path" "$writable_mount/RELEASE-MANIFEST.json" || {
    release_error 'writable mounted manifest bytes differ from source payload'
    return 1
  }
  verify_release_manifest "$writable_mount" \
    "$writable_mount/RELEASE-MANIFEST.json" "$source_commit" \
    "$bundle_identifier" "$bundle_short_version" "$bundle_version"
  release_validate_app "$writable_mount/СберВакансии.app" writable-mounted \
    "$bundle_identifier" "$bundle_executable" "$bundle_short_version" "$bundle_version"
  /bin/sync
  ds_store_hash_after_sync="$(/usr/bin/shasum -a 256 \
    "$writable_mount/.DS_Store" | /usr/bin/awk '{print $1}')"
  if [[ "$ds_store_hash_after_sync" != "$ds_store_hash" ]]; then
    release_error '.DS_Store changed during final pre-detach filesystem sync'
    return 1
  fi
  printf 'PRE_DETACH_DS_STORE_SHA256=%s\nPRE_DETACH_DS_STORE_STABLE=yes\n' \
    "$ds_store_hash_after_sync" \
    > "$RELEASE_LOG_DIR/pre-detach-ds-store-integrity.txt"
  if ! release_detach_attached_image writable-image writable-image-detach; then
    release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — WRITABLE IMAGE DETACH FAILURE'
    return 1
  fi
  release_authenticate_owned_image_path \
    "$writable_image" "$RELEASE_WORK_ROOT" HHVacancySber-writable.dmg file
  writable_image_hash="$(/usr/bin/shasum -a 256 "$writable_image" | /usr/bin/awk '{print $1}')"
  writable_image_size="$(/usr/bin/stat -f '%z' "$writable_image")"
  {
    printf 'WRITABLE_IMAGE=%s\n' "$writable_image"
    printf 'WRITABLE_IMAGE_POST_DETACH_SHA256=%s\n' "$writable_image_hash"
    printf 'WRITABLE_IMAGE_POST_DETACH_SIZE=%s\n' "$writable_image_size"
    printf 'WRITABLE_IMAGE_DETACH=pass\n'
    printf 'WRITABLE_IMAGE_RETAINED=yes\n'
  } > "$RELEASE_LOG_DIR/writable-image-detached.txt"

  dmg_basename="HHVacancySber_${bundle_short_version}_${bundle_version}_macos13_arm64.dmg"
  checksum_basename="$dmg_basename.sha256"
  manifest_basename="$dmg_basename.manifest.json"
  final_dmg="$RELEASE_OUTPUT_DIR/$dmg_basename"
  final_checksum="$RELEASE_OUTPUT_DIR/$checksum_basename"
  final_manifest="$RELEASE_OUTPUT_DIR/$manifest_basename"
  if [[ -e "$final_dmg" || -L "$final_dmg" || -e "$final_checksum" || -L "$final_checksum" || -e "$final_manifest" || -L "$final_manifest" ]]; then
    release_error 'publication collision detected before DMG creation'
    return 1
  fi
  temp_dmg="$RELEASE_WORK_ROOT/$dmg_basename"
  release_authenticate_owned_image_path \
    "$temp_dmg" "$RELEASE_WORK_ROOT" "$dmg_basename" absent
  {
    printf 'SOURCE_UDRW=%s\n' "$writable_image"
    printf 'SOURCE_UDRW_SHA256=%s\n' "$writable_image_hash"
    printf '%s\n' "/usr/bin/hdiutil convert $writable_image -format UDZO -imagekey zlib-level=9 -o $temp_dmg"
  } > "$RELEASE_LOG_DIR/hdiutil-convert.command"
  if /usr/bin/hdiutil convert "$writable_image" \
      -format UDZO \
      -imagekey zlib-level=9 \
      -o "$temp_dmg" \
      > "$RELEASE_LOG_DIR/hdiutil-convert.stdout" \
      2> "$RELEASE_LOG_DIR/hdiutil-convert.stderr"; then
    convert_status=0
  else
    convert_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$convert_status" > "$RELEASE_LOG_DIR/hdiutil-convert.status"
  if [[ "$convert_status" -ne 0 ]]; then
    release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — UDZO CONVERSION FAILURE'
    return "$convert_status"
  fi
  release_authenticate_owned_image_path \
    "$temp_dmg" "$RELEASE_WORK_ROOT" "$dmg_basename" file
  if [[ "$(/usr/bin/shasum -a 256 "$writable_image" | /usr/bin/awk '{print $1}')" != "$writable_image_hash" ]]; then
    release_error 'retained writable image changed during UDZO conversion'
    return 1
  fi
  printf 'UDZO_CONVERSION=pass\nWRITABLE_IMAGE_RETAINED=yes\n' \
    > "$RELEASE_LOG_DIR/hdiutil-convert-evidence.txt"

  if /usr/bin/hdiutil verify "$temp_dmg" > "$RELEASE_LOG_DIR/hdiutil-verify.stdout" 2> "$RELEASE_LOG_DIR/hdiutil-verify.stderr"; then
    verify_status=0
  else
    verify_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$verify_status" > "$RELEASE_LOG_DIR/hdiutil-verify.status"
  if [[ "$verify_status" -ne 0 ]]; then
    release_error 'temporary DMG structural verification failed'
    return "$verify_status"
  fi
  if /usr/bin/hdiutil imageinfo -plist "$temp_dmg" \
      > "$RELEASE_LOG_DIR/hdiutil-imageinfo.plist" 2> "$RELEASE_LOG_DIR/hdiutil-imageinfo.stderr"; then
    imageinfo_status=0
  else
    imageinfo_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$imageinfo_status" > "$RELEASE_LOG_DIR/hdiutil-imageinfo.status"
  if [[ "$imageinfo_status" -ne 0 ]] ||
     ! release_python imageinfo-check "$RELEASE_LOG_DIR/hdiutil-imageinfo.plist" UDZO; then
    release_error 'DMG image metadata is not verified UDZO'
    return 1
  fi
  release_record_repository_status after-dmg-conversion

  readonly_mount="$RELEASE_WORK_ROOT/readonly-mount"
  release_prepare_mountpoint \
    "$readonly_mount" "$RELEASE_WORK_ROOT" readonly-mount \
    > "$RELEASE_LOG_DIR/readonly-mountpoint.txt"
  RELEASE_ATTACHMENT_KIND=readonly
  RELEASE_DETACH_ATTEMPTED=0

  attach_plist="$RELEASE_LOG_DIR/readonly-image-attach.plist"
  printf '%s\n' \
    "/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint $readonly_mount -plist $temp_dmg" \
    > "$RELEASE_LOG_DIR/readonly-image-attach.command"
  if /usr/bin/hdiutil attach \
      -readonly \
      -nobrowse \
      -mountpoint "$readonly_mount" \
      -plist \
      "$temp_dmg" \
      > "$attach_plist" \
      2> "$RELEASE_LOG_DIR/readonly-image-attach.stderr"; then
    attach_status=0
    RELEASE_ATTACH_SUCCEEDED=1
  else
    attach_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$attach_status" > "$RELEASE_LOG_DIR/readonly-image-attach.status"
  if [[ "$attach_status" -ne 0 ]]; then
    release_error 'read-only DMG attach failed'
    return "$attach_status"
  fi
  RELEASE_ATTACHED_DEVICE="$(release_python attach-device "$attach_plist" "$readonly_mount")" || {
    release_error 'attached DMG device could not be identified; manual recovery required'
    return 1
  }
  RELEASE_MOUNTED_ROOT_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$readonly_mount")"
  diskinfo_plist="$RELEASE_LOG_DIR/readonly-diskutil-info.plist"
  if ! /usr/sbin/diskutil info -plist "$RELEASE_ATTACHED_DEVICE" \
      > "$diskinfo_plist" \
      2> "$RELEASE_LOG_DIR/readonly-diskutil-info.stderr"; then
    release_error 'mounted DMG device metadata inspection failed'
    return 1
  fi
  release_python diskinfo-check \
    "$diskinfo_plist" "$RELEASE_ATTACHED_DEVICE" "$readonly_mount" \
    > "$RELEASE_LOG_DIR/readonly-diskutil-validation.txt"
  verify_exact_payload_root "$readonly_mount"
  mounted_ds_store_hash="$(/usr/bin/shasum -a 256 \
    "$readonly_mount/.DS_Store" | /usr/bin/awk '{print $1}')"
  if [[ ! "$mounted_ds_store_hash" =~ ^[0-9a-f]{64}$ ]]; then
    release_error 'final mounted .DS_Store SHA-256 is invalid'
    return 1
  fi
  {
    printf 'PRE_UNMOUNT_DS_STORE_SHA256=%s\n' "$ds_store_hash"
    printf 'FINAL_MOUNTED_DS_STORE_SHA256=%s\n' "$mounted_ds_store_hash"
    printf 'CROSS_UNMOUNT_BYTE_IDENTITY_REQUIRED=no\n'
    printf 'FINAL_PRESENTATION_VERIFICATION=finder-semantic-readback\n'
  } > "$RELEASE_LOG_DIR/readonly-ds-store-comparison.txt"

  if finder_readback="$(release_read_finder_layout \
      "$readonly_mount" "$RELEASE_WORK_ROOT" readonly-mount open \
      "$RELEASE_MOUNTED_ROOT_IDENTITY" \
      2> "$RELEASE_LOG_DIR/finder-readonly-readback.stderr")"; then
    finder_status=0
  else
    finder_status=$?
  fi
  printf 'EXIT_STATUS=%s\n' "$finder_status" > "$RELEASE_LOG_DIR/finder-readonly-readback.status"
  if [[ "$finder_status" -ne 0 ]]; then
    release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — FINAL FINDER PRESENTATION READBACK FAILURE'
    return "$finder_status"
  fi
  readback_status="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "READBACK_STATUS" {print $2}')"
  readback_view="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "CURRENT_VIEW" {print $2}')"
  readback_icon_size="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "ICON_SIZE" {print $2}')"
  readback_arrangement="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "ARRANGEMENT" {print $2}')"
  readback_toolbar="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "TOOLBAR_VISIBLE" {print $2}')"
  readback_statusbar="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "STATUS_BAR_VISIBLE" {print $2}')"
  readback_pathbar="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "PATH_BAR_VISIBLE" {print $2}')"
  readback_item_information="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "ITEM_INFORMATION_VISIBLE" {print $2}')"
  readback_icon_preview="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "ICON_PREVIEW_ENABLED" {print $2}')"
  readback_width="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "WINDOW_WIDTH" {print $2}')"
  readback_height="$(printf '%s\n' "$finder_readback" | /usr/bin/awk -F= '$1 == "WINDOW_HEIGHT" {print $2}')"
  if ! release_validate_finder_readback \
      "$readback_status" \
      "$readback_view" \
      "$readback_icon_size" \
      "$readback_arrangement" \
      "$readback_toolbar" \
      "$readback_statusbar" \
      "$readback_pathbar" \
      "$readback_item_information" \
      "$readback_icon_preview" \
      "$readback_width" \
      "$readback_height" \
      > "$RELEASE_LOG_DIR/finder-readonly-readback-validation.txt"; then
    release_error 'B13-DIST-001-R5-R6-R4 BLOCKED — FINAL FINDER PRESENTATION READBACK FAILURE'
    return 1
  fi
  {
    printf '%s\n' "$finder_readback"
    printf 'FINAL_READONLY_FINDER_READBACK=pass\n'
    printf 'DS_STORE_SHA256=%s\n' "$mounted_ds_store_hash"
    printf 'DS_STORE_SEMANTICS_PRESERVED=yes\n'
  } > "$RELEASE_LOG_DIR/finder-readonly-readback.txt"
  if ! release_close_finder_window \
      "$readonly_mount" "$RELEASE_WORK_ROOT" readonly-mount \
      "$RELEASE_MOUNTED_ROOT_IDENTITY" \
      > "$RELEASE_LOG_DIR/finder-readonly-close.stdout" \
      2> "$RELEASE_LOG_DIR/finder-readonly-close.stderr"; then
    release_error 'read-only mounted Finder window close request failed'
    return 1
  fi
  printf 'FINAL_READONLY_WINDOW_CLOSE_REQUEST_COUNT=1\n' \
    > "$RELEASE_LOG_DIR/finder-readonly-close-evidence.txt"
  if [[ ! -L "$readonly_mount/Applications" ||
        "$(/usr/bin/readlink "$readonly_mount/Applications")" != "/Applications" ]]; then
    release_error 'mounted Applications symlink contract failed'
    return 1
  fi
  /usr/bin/cmp -s "$source_payload/README.txt" "$readonly_mount/README.txt" || {
    release_error 'mounted README bytes differ from source payload'
    return 1
  }
  /usr/bin/cmp -s "$manifest_path" "$readonly_mount/RELEASE-MANIFEST.json" || {
    release_error 'mounted manifest bytes differ from source payload'
    return 1
  }
  verify_release_manifest "$readonly_mount" \
    "$readonly_mount/RELEASE-MANIFEST.json" "$source_commit" \
    "$bundle_identifier" "$bundle_short_version" "$bundle_version"
  release_validate_app "$readonly_mount/СберВакансии.app" mounted \
    "$bundle_identifier" "$bundle_executable" "$bundle_short_version" "$bundle_version"
  release_record_repository_status after-dmg-mount-verification

  if ! release_detach_attached_image readonly-image readonly-image-detach; then
    release_error 'final read-only image normal detach failed'
    return 1
  fi
  release_validate_finder_lifecycle \
    "$customization_result" pass 1 pass pass pass pass pass \
    > "$RELEASE_LOG_DIR/finder-lifecycle-acceptance.txt"

  release_python exact-entries \
    "$source_payload" \
    СберВакансии.app Applications README.txt RELEASE-MANIFEST.json \
    > "$RELEASE_LOG_DIR/source-payload-final-inventory.txt"
  release_python repository-snapshot "$source_payload" \
    > "$RELEASE_LOG_DIR/source-payload-after-packaging.snapshot.json"
  if [[ "$(/usr/bin/stat -f '%d:%i' "$source_payload")" != "$source_payload_identity" ]] ||
     ! /usr/bin/cmp -s "$source_payload_snapshot" \
      "$RELEASE_LOG_DIR/source-payload-after-packaging.snapshot.json"; then
    release_error 'immutable source payload changed during Finder presentation packaging'
    return 1
  fi
  printf 'SOURCE_PAYLOAD_IMMUTABLE=yes\nSOURCE_PAYLOAD_DS_STORE=absent\n' \
    > "$RELEASE_LOG_DIR/source-payload-final-integrity.txt"

  dmg_hash="$(/usr/bin/shasum -a 256 "$temp_dmg" | /usr/bin/awk '{print $1}')"
  if [[ ! "$dmg_hash" =~ ^[0-9a-f]{64}$ ]]; then
    release_error 'final DMG SHA-256 is invalid'
    return 1
  fi
  temp_checksum="$RELEASE_WORK_ROOT/$checksum_basename"
  temp_manifest="$RELEASE_WORK_ROOT/$manifest_basename"
  printf '%s  %s\n' "$dmg_hash" "$dmg_basename" > "$temp_checksum"
  /bin/ln "$manifest_path" "$temp_manifest"
  release_python checksum-check "$temp_checksum" "$dmg_hash" "$dmg_basename"
  /usr/bin/cmp -s "$temp_manifest" "$manifest_path" || return 1

  RELEASE_TEMP_DMG="$temp_dmg"
  RELEASE_FINAL_DMG="$final_dmg"
  RELEASE_TEMP_CHECKSUM="$temp_checksum"
  RELEASE_FINAL_CHECKSUM="$final_checksum"
  RELEASE_TEMP_MANIFEST="$temp_manifest"
  RELEASE_FINAL_MANIFEST="$final_manifest"
  RELEASE_PUBLICATION_PENDING=1
  if ! publish_no_clobber \
      "$temp_dmg" "$final_dmg" \
      "$temp_checksum" "$final_checksum" \
      "$temp_manifest" "$final_manifest"; then
    return 1
  fi
  if [[ ! -f "$final_dmg" || -L "$final_dmg" ||
        ! -f "$final_checksum" || -L "$final_checksum" ||
        ! -f "$final_manifest" || -L "$final_manifest" ]]; then
    if ! release_cancel_pending_publication; then :; fi
    release_error 'published objects are not three regular files'
    return 1
  fi
  if ! release_same_file "$temp_dmg" "$final_dmg" ||
     ! release_same_file "$temp_checksum" "$final_checksum" ||
     ! release_same_file "$temp_manifest" "$final_manifest"; then
    if ! release_cancel_pending_publication; then :; fi
    release_error 'published objects do not retain verified hard-link identity'
    return 1
  fi
  if [[ "$(/usr/bin/shasum -a 256 "$final_dmg" | /usr/bin/awk '{print $1}')" != "$dmg_hash" ]]; then
    if ! release_cancel_pending_publication; then :; fi
    release_error 'published DMG checksum differs from verified temporary image'
    return 1
  fi
  if ! release_python checksum-check "$final_checksum" "$dmg_hash" "$dmg_basename"; then
    if ! release_cancel_pending_publication; then :; fi
    release_error 'published checksum sidecar verification failed'
    return 1
  fi
  if ! /usr/bin/cmp -s "$final_manifest" "$manifest_path"; then
    if ! release_cancel_pending_publication; then :; fi
    release_error 'published manifest differs from internal manifest bytes'
    return 1
  fi
  printf 'CONVERTED_IMAGE_HDIUTIL_VERIFY=pass\nPUBLICATION_HARDLINK_IDENTITY=verified\n' \
    > "$RELEASE_LOG_DIR/published-image-verification.txt"
  if /usr/bin/find "$RELEASE_OUTPUT_DIR" -maxdepth 1 -type f -name '*.partial' | /usr/bin/grep -q .; then
    if ! release_cancel_pending_publication; then :; fi
    release_error 'partial publication file remains'
    return 1
  fi
  if ! release_record_repository_status after-publication ||
     ! release_record_repository_status before-script-exit; then
    if ! release_cancel_pending_publication; then :; fi
    return 1
  fi
  RELEASE_PUBLICATION_PENDING=0
  RELEASE_ALLOW_LOCK_RELEASE=1
  if ! release_cleanup_resources; then
    release_error 'release resources were not cleaned completely'
    return 1
  fi
  release_report_retained_work
  trap - EXIT INT TERM HUP
  final_count=0
  [[ -f "$final_dmg" && ! -L "$final_dmg" ]] && final_count=$((final_count + 1))
  [[ -f "$final_checksum" && ! -L "$final_checksum" ]] && final_count=$((final_count + 1))
  [[ -f "$final_manifest" && ! -L "$final_manifest" ]] && final_count=$((final_count + 1))
  if [[ "$final_count" != "3" ]]; then
    release_error 'final publication does not contain its three verified objects'
    return 1
  fi

  printf 'RELEASE_STATUS=success\n'
  printf 'SOURCE_COMMIT=%s\n' "$source_commit"
  printf 'APP_PATH=%s\n' "$built_app"
  printf 'DMG_PATH=%s\n' "$final_dmg"
  printf 'DMG_SHA256=%s\n' "$dmg_hash"
  printf 'CHECKSUM_PATH=%s\n' "$final_checksum"
  printf 'MANIFEST_PATH=%s\n' "$final_manifest"
  printf 'BUNDLE_IDENTIFIER=%s\n' "$bundle_identifier"
  printf 'BUNDLE_SHORT_VERSION=%s\n' "$bundle_short_version"
  printf 'BUNDLE_VERSION=%s\n' "$bundle_version"
  printf 'ARCHITECTURE=arm64\n'
  printf 'MINIMUM_MACOS=13.0\n'
  printf 'SIGNING=ad-hoc\n'
  printf 'SOURCE_PAYLOAD_PATH=%s\n' "$source_payload"
  printf 'SOURCE_PAYLOAD_OPENED_IN_FINDER=no\n'
  printf 'WRITABLE_IMAGE_PATH=%s\n' "$writable_image"
  printf 'WRITABLE_IMAGE_SHA256=%s\n' "$writable_image_hash"
  printf 'WRITABLE_IMAGE_RETAINED=yes\n'
  printf 'FINDER_CUSTOMIZATION_INVOCATIONS=1\n'
  printf 'FINDER_CUSTOMIZATION_RETRY_COUNT=0\n'
  printf 'FINDER_CUSTOMIZATION_STATUS=%s\n' "$customization_result"
  printf 'WRITABLE_FINDER_READBACK=pass\n'
  printf 'FINDER_WINDOW_CLOSE_REQUEST_COUNT=1\n'
  printf 'POST_CLOSE_DS_STORE_STABILITY=pass\n'
  printf 'STABLE_DS_STORE_SHA256=%s\n' "$ds_store_hash"
  printf 'WRITABLE_IMAGE_DETACH=pass\n'
  printf 'UDZO_CONVERSION=pass\n'
  printf 'FINAL_READONLY_FINDER_READBACK=pass\n'
  printf 'FINAL_MOUNTED_DS_STORE_SHA256=%s\n' "$mounted_ds_store_hash"
  printf 'DS_STORE_SEMANTICS_PRESERVED=yes\n'
  printf 'GET_TASK_ALLOW=absent\n'
  printf 'APP_SANDBOX=present\n'
  printf 'HARDENED_RUNTIME=present\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
