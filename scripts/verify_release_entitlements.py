#!/usr/bin/env python3
"""Verify the signed entitlement contract of a distributable macOS app."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys


CODESIGN = "/usr/bin/codesign"
GET_TASK_ALLOW = "com.apple.security.get-task-allow"
APP_SANDBOX = "com.apple.security.app-sandbox"
REQUIRED_ENTITLEMENTS = (
    APP_SANDBOX,
    "com.apple.security.files.user-selected.read-write",
    "com.apple.security.network.client",
)
MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


def canonical_path(path):
    return Path(os.path.realpath(os.path.abspath(os.fspath(path))))


def same_file_identity(first, second):
    try:
        return os.path.samefile(first, second)
    except OSError:
        return canonical_path(first) == canonical_path(second)


def _command(arguments):
    return subprocess.run(
        arguments,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def _extract_entitlements(path):
    completed = _command([
        CODESIGN, "-d", "--entitlements", ":-", "--xml", str(path),
    ])
    if completed.returncode != 0:
        return None
    payload = completed.stdout.strip()
    if not payload:
        return {}
    try:
        value = plistlib.loads(payload)
    except (plistlib.InvalidFileException, ValueError, TypeError):
        return None
    return value if isinstance(value, dict) else None


def _is_macho(path):
    try:
        with path.open("rb") as stream:
            return stream.read(4) in MACHO_MAGICS
    except OSError:
        return False


def _main_executable(app):
    info = app / "Contents" / "Info.plist"
    executable_name = app.stem
    if info.is_file():
        try:
            with info.open("rb") as stream:
                plist = plistlib.load(stream)
            candidate = plist.get("CFBundleExecutable")
            if isinstance(candidate, str) and candidate:
                executable_name = candidate
        except (OSError, plistlib.InvalidFileException, ValueError, TypeError):
            pass
    return app / "Contents" / "MacOS" / executable_name


def _record_entitlement_findings(path, entitlements, forbidden, missing, require_main):
    display = str(path)
    for key in (GET_TASK_ALLOW,):
        if key in entitlements:
            forbidden.append({"code": display, "entitlement": key})
    if require_main:
        for key in REQUIRED_ENTITLEMENTS:
            if entitlements.get(key) is not True:
                missing.append(key)


def inspect_application(app_path):
    app = canonical_path(Path(app_path))
    main = canonical_path(_main_executable(app))
    report = {
        "app": str(app),
        "main_executable": str(main),
        "signature_valid": False,
        "main_entitlements": {},
        "nested_code": [],
        "forbidden_entitlements_found": [],
        "required_entitlements_missing": [],
        "success": False,
    }
    errors = []
    if not app.is_dir():
        errors.append("application_missing")
    elif not main.is_file():
        errors.append("main_executable_missing")
    else:
        main_entitlements = _extract_entitlements(main)
        if main_entitlements is None:
            errors.append("main_entitlements_unavailable")
        else:
            report["main_entitlements"] = main_entitlements
            _record_entitlement_findings(
                main, main_entitlements,
                report["forbidden_entitlements_found"],
                report["required_entitlements_missing"], True,
            )

        nested_identities = []
        for discovered in sorted(app.rglob("*"), key=lambda path: str(canonical_path(path))):
            candidate = canonical_path(discovered)
            if same_file_identity(candidate, main) or not candidate.is_file() or not _is_macho(candidate):
                continue
            if any(same_file_identity(candidate, existing) for existing in nested_identities):
                continue
            entitlements = _extract_entitlements(candidate)
            if entitlements is None:
                continue
            nested_identities.append(candidate)
            entry = {"path": str(candidate), "entitlements": entitlements}
            report["nested_code"].append(entry)
            _record_entitlement_findings(
                candidate, entitlements,
                report["forbidden_entitlements_found"],
                report["required_entitlements_missing"], False,
            )

        verification = _command([
            CODESIGN, "--verify", "--strict", "--deep", str(app),
        ])
        report["signature_valid"] = verification.returncode == 0
        if not report["signature_valid"]:
            errors.append("signature_invalid")

    report["forbidden_entitlements_found"] = sorted(
        report["forbidden_entitlements_found"],
        key=lambda item: (item["code"], item["entitlement"]),
    )
    report["required_entitlements_missing"] = sorted(set(report["required_entitlements_missing"]))
    report["nested_code"] = sorted(report["nested_code"], key=lambda item: item["path"])
    report["success"] = not (
        errors or report["forbidden_entitlements_found"] or
        report["required_entitlements_missing"] or not report["signature_valid"]
    )
    if errors:
        report["errors"] = sorted(errors)
    return report


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True)
    return parser


def main(argv=None):
    arguments = build_parser().parse_args(argv)
    report = inspect_application(arguments.app)
    print(json.dumps(report, sort_keys=True, indent=2, ensure_ascii=False))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
