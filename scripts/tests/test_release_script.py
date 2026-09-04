import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RELEASE_SCRIPT = REPOSITORY_ROOT / "scripts" / "release.sh"


class ReleaseScriptTests(unittest.TestCase):
    def invoke_helper(self, helper, *arguments, input_text=None):
        return subprocess.run(
            [
                "/bin/bash",
                "-c",
                'source "$1"; shift; "$@"',
                "release-helper-test",
                str(RELEASE_SCRIPT),
                helper,
                *[str(argument) for argument in arguments],
            ],
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def invoke_owned_helper(
        self, owned_root, helper, *arguments, input_text=None
    ):
        return subprocess.run(
            [
                "/bin/bash",
                "-c",
                (
                    'source "$1"; '
                    'RELEASE_WORK_ROOT="$2"; '
                    'RELEASE_WORK_IDENTITY="$(/usr/bin/stat -f \'%d:%i\' "$2")"; '
                    'shift 2; "$@"'
                ),
                "release-owned-helper-test",
                str(RELEASE_SCRIPT),
                str(owned_root),
                helper,
                *[str(argument) for argument in arguments],
            ],
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def run_script(self, *arguments, cwd=None):
        return subprocess.run(
            [str(RELEASE_SCRIPT), *[str(argument) for argument in arguments]],
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def git_status(self):
        return subprocess.run(
            [
                "/usr/bin/git",
                "-C",
                str(REPOSITORY_ROOT),
                "status",
                "--porcelain=v1",
                "--untracked-files=all",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout

    def settings_fixture(self, replacements=None):
        settings = {
            "ARCHS": "arm64",
            "CODE_SIGN_ENTITLEMENTS": "HHVacancySber/HHVacancySber.entitlements",
            "CODE_SIGN_IDENTITY": "-",
            "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "NO",
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_APP_SANDBOX": "YES",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "EXECUTABLE_NAME": "СберВакансии",
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "ONLY_ACTIVE_ARCH": "NO",
            "PRODUCT_BUNDLE_IDENTIFIER": "local.sergey.HHVacancySber",
            "PRODUCT_NAME": "СберВакансии",
            "TARGET_BUILD_DIR": "/private/tmp/release/Build/Products/Release",
            "WRAPPER_NAME": "СберВакансии.app",
        }
        if replacements:
            settings.update(replacements)
        body = "\n".join(
            "    %s = %s" % (key, value)
            for key, value in sorted(settings.items())
        )
        return textwrap.dedent(
            """\
            unrelated xcodebuild warning
            Build settings for action build and target HHVacancySberTests:
                ARCHS = x86_64
                ENABLE_APP_SANDBOX = YES

            Build settings for action build and target HHVacancySber:
            """
        ) + body + "\n"

    def write_settings(self, directory, replacements=None):
        path = Path(directory) / "showBuildSettings.txt"
        path.write_text(self.settings_fixture(replacements), encoding="utf-8")
        return path

    def create_staging_payload(self, root):
        root = Path(root)
        executable = root / "СберВакансии.app" / "Contents" / "MacOS" / "СберВакансии"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b"deterministic-app-bytes\n")
        executable.chmod(0o755)
        current = executable.parent.parent / "Current"
        applications = root / "Applications"
        os.symlink("MacOS", current)
        os.symlink("/Applications", applications)
        subprocess.run(
            ["/bin/chmod", "-h", "0777", str(current), str(applications)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        readme = self.invoke_helper("write_release_readme", root / "README.txt")
        self.assertEqual(0, readme.returncode, readme.stderr)
        return executable

    def create_isolation_fixture(self, temporary):
        root = Path(temporary)
        repository = root / "authoritative"
        repository.mkdir()
        subprocess.run(
            ["/usr/bin/git", "-C", str(repository), "init", "-b", "main"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            [
                "/usr/bin/git", "-C", str(repository), "config",
                "user.name", "Release Isolation Test",
            ],
            check=True,
        )
        subprocess.run(
            [
                "/usr/bin/git", "-C", str(repository), "config",
                "user.email", "release-isolation@example.invalid",
            ],
            check=True,
        )
        project = repository / "HHVacancySber" / "HHVacancySber.xcodeproj"
        project.mkdir(parents=True)
        (project / "project.pbxproj").write_text(
            "minimal project fixture\n", encoding="utf-8"
        )
        verifier = repository / "scripts" / "verify_release_entitlements.py"
        verifier.parent.mkdir()
        verifier.write_text("# committed verifier fixture\n", encoding="utf-8")
        executable = repository / "tools" / "committed-tool"
        executable.parent.mkdir()
        executable.write_bytes(b"#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        os.symlink("tools/committed-tool", repository / "tracked-link")
        (repository / ".gitignore").write_text(
            "ignored/\n", encoding="utf-8"
        )
        subprocess.run(
            ["/usr/bin/git", "-C", str(repository), "add", "-A"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            [
                "/usr/bin/git", "-C", str(repository), "commit", "-m",
                "isolation fixture",
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        (repository / "untracked.txt").write_bytes(b"untracked\n")
        ignored = repository / "ignored" / "private.txt"
        ignored.parent.mkdir()
        ignored.write_bytes(b"ignored\n")

        work_root = root / "release-output" / ".hhvacancysber-release.test"
        (work_root / "logs").mkdir(parents=True)
        work_root.chmod(0o700)
        commit = subprocess.run(
            ["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout.strip()
        return repository.resolve(), work_root.resolve(), commit

    def materialize_isolation_fixture(self, repository, work_root, commit):
        command = textwrap.dedent(
            """\
            set -e
            source "$1"
            REPOSITORY_ROOT="$2"
            RELEASE_WORK_ROOT="$3"
            RELEASE_SOURCE_COMMIT="$4"
            RELEASE_WORK_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$3")"
            RELEASE_LOG_DIR="$3/logs"
            BUILD_SOURCE_ROOT=""
            release_materialize_build_source
            printf 'BUILD_SOURCE_ROOT=%s\n' "$BUILD_SOURCE_ROOT"
            """
        )
        completed = subprocess.run(
            [
                "/bin/bash", "-c", command, "release-isolation-test",
                str(RELEASE_SCRIPT), str(repository), str(work_root), commit,
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        return completed, work_root / "source"

    def invoke_disk_info(self, temporary, evidence=None, raw=None):
        mountpoint = Path(temporary) / "mount"
        mountpoint.mkdir(exist_ok=True)
        path = Path(temporary) / "disk-info.plist"
        if raw is None:
            data = {
                "DeviceNode": "/dev/disk9s1",
                "FilesystemType": "hfs",
                "MountPoint": str(mountpoint),
                "VolumeName": "СберВакансии",
            }
            data.update(evidence or {})
            with path.open("wb") as stream:
                plistlib.dump(data, stream)
        else:
            path.write_bytes(raw)
        return self.invoke_helper(
            "release_python", "diskinfo-check", path,
            "/dev/disk9s1", mountpoint,
        )

    def test_release_script_has_valid_bash_syntax(self):
        completed = subprocess.run(
            ["/bin/bash", "-n", str(RELEASE_SCRIPT)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)

    def test_release_script_is_executable(self):
        mode = stat.S_IMODE(RELEASE_SCRIPT.stat().st_mode)
        self.assertEqual(0o755, mode)
        self.assertTrue(os.access(RELEASE_SCRIPT, os.X_OK))

    def test_help_succeeds_without_repository_changes(self):
        before = self.git_status()
        with tempfile.TemporaryDirectory() as temporary:
            completed = self.run_script("--help", cwd=temporary)
            created = list(Path(temporary).iterdir())
        after = self.git_status()
        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertIn("--output-dir", completed.stdout)
        self.assertEqual("", completed.stderr)
        self.assertEqual(before, after)
        self.assertEqual([], created)

    def test_unknown_option_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            completed = self.run_script("--unknown", cwd=temporary)
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("unknown option", completed.stderr)

    def test_missing_output_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            completed = self.run_script(cwd=temporary)
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("--output-dir", completed.stderr)

    def test_output_directory_inside_repository_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            repository.mkdir()
            candidate = repository / "release-output"
            completed = self.invoke_helper(
                "validate_output_directory", repository, candidate
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("inside the source repository", completed.stderr)
            self.assertFalse(candidate.exists())

    def test_unsafe_cleanup_root_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / "repository"
            output = root / "output"
            repository.mkdir()
            output.mkdir()
            sentinel = output / "sentinel"
            sentinel.write_text("preserve", encoding="utf-8")
            completed = self.invoke_helper(
                "release_create_work_root", repository, output
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual("preserve", sentinel.read_text(encoding="utf-8"))
            work_root = Path(completed.stdout.strip())
            self.assertNotEqual(output.resolve(), work_root.resolve())
            self.assertEqual(output.resolve().parent, work_root.resolve().parent)
            work_sentinel = work_root / "manual-cleanup-required"
            work_sentinel.write_text("preserve-work", encoding="utf-8")
            self.assertEqual("preserve-work", work_sentinel.read_text(encoding="utf-8"))

    def test_repository_status_allows_only_untracked_release_pipeline_bootstrap(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            script = repository / "scripts" / "release.sh"
            tests = repository / "scripts" / "tests" / "test_release_script.py"
            tests.parent.mkdir(parents=True)
            script.write_text("#!/bin/bash\n", encoding="utf-8")
            tests.write_text("# tests\n", encoding="utf-8")
            status = Path(temporary) / "status.txt"
            status.write_text(
                "?? scripts/release.sh\n"
                "?? scripts/tests/test_release_script.py\n",
                encoding="utf-8",
            )
            completed = self.invoke_helper(
                "release_validate_repository_status_file", repository, status
            )
            self.assertEqual(0, completed.returncode, completed.stderr)

            status.write_text(
                "?? scripts/release.sh\n?? unrelated.txt\n", encoding="utf-8"
            )
            completed = self.invoke_helper(
                "release_validate_repository_status_file", repository, status
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("not clean", completed.stderr)

            script.unlink()
            status.write_text("?? scripts/release.sh\n", encoding="utf-8")
            completed = self.invoke_helper(
                "release_validate_repository_status_file", repository, status
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("unsafe type", completed.stderr)

    def test_release_setting_parser_selects_application_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            settings = self.write_settings(temporary)
            completed = self.invoke_helper(
                "parse_target_build_settings", settings, "HHVacancySber"
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            parsed = json.loads(completed.stdout)
            self.assertEqual("arm64", parsed["ARCHS"])
            self.assertEqual("YES", parsed["ENABLE_APP_SANDBOX"])
            self.assertNotIn("HHVacancySberTests", completed.stdout)

    def test_release_settings_parser_ignores_trailing_coresimulator_request_records(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = self.settings_fixture().rstrip("\n") + textwrap.dedent(
                """\

                    BUNDLE_CONTENTS_FOLDER_PATH_deep = Contents/
                structural termination before CoreSimulator diagnostics
                [-[SimServiceContext sendRequest:]:1] ERROR : diagnostic ({
                    request = "set_developer_dir";
                })
                [-[SimServiceContext sendRequest:reply:error:]:2] ERROR : diagnostic ({
                    request = "notification_subscription";
                })
                [-[SimServiceContext sendRequest:reply:error:]:3] ERROR : diagnostic ({
                    request = "notification_subscription";
                })
                [-[SimServiceContext sendRequest:reply:error:]:4] ERROR : diagnostic ({
                    request = "get_runtime_sdk_map";
                })
                    ARCHS = must-not-reenter
                """
            )
            self.assertEqual(4, fixture.count("    request = "))
            path = Path(temporary) / "showBuildSettings.txt"
            path.write_text(fixture, encoding="utf-8")
            completed = self.invoke_helper(
                "parse_target_build_settings", path, "HHVacancySber"
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            parsed = json.loads(completed.stdout)
            self.assertEqual("arm64", parsed["ARCHS"])
            self.assertEqual("13.0", parsed["MACOSX_DEPLOYMENT_TARGET"])
            self.assertNotIn("BUNDLE_CONTENTS_FOLDER_PATH_deep", parsed)
            self.assertNotIn("request", parsed)
            self.assertNotIn("must-not-reenter", completed.stdout)
            self.assertNotIn("duplicate build setting", completed.stderr)

    def test_release_settings_parser_rejects_duplicate_authenticated_uppercase_key(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = textwrap.dedent(
                """\
                Build settings for action build and target HHVacancySber:
                    BUNDLE_CONTENTS_FOLDER_PATH_deep = first
                    BUNDLE_CONTENTS_FOLDER_PATH_deep = second
                    request = "notification_subscription"
                    request = "notification_subscription"
                    ARCHS = first-secret-value
                    ARCHS = second-secret-value

                diagnostic dictionary ({
                    request = "notification_subscription";
                })
                """
            )
            path = Path(temporary) / "showBuildSettings.txt"
            path.write_text(fixture, encoding="utf-8")
            completed = self.invoke_helper(
                "parse_target_build_settings", path, "HHVacancySber"
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertIn(
                "duplicate build setting in application target: ARCHS",
                completed.stderr,
            )
            self.assertNotIn("first-secret-value", completed.stderr)
            self.assertNotIn("second-secret-value", completed.stderr)
            self.assertNotIn("request", completed.stderr)
            self.assertEqual("", completed.stdout)

    def test_release_settings_parser_uses_single_exact_contiguous_application_target_section(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture_lines = self.settings_fixture().splitlines()
            fixture_lines.insert(
                fixture_lines.index(
                    "Build settings for action build and target HHVacancySber:"
                ),
                "diagnostic mentions HHVacancySber but is not a header",
            )
            fixture_lines.insert(
                fixture_lines.index("    ONLY_ACTIVE_ARCH = NO"),
                "    UNKNOWN_UPPERCASE = ignored",
            )
            fixture_lines.insert(
                fixture_lines.index("    ONLY_ACTIVE_ARCH = NO"),
                "    BUNDLE_CONTENTS_FOLDER_PATH_deep = Contents/",
            )
            fixture = "\n".join(fixture_lines) + "\n" + textwrap.dedent(
                """\
                first noncanonical line terminates settings
                    PRODUCT_NAME = must-be-ignored
                Build settings for action build and target AnotherTarget:
                    ARCHS = unrelated
                """
            )
            path = Path(temporary) / "showBuildSettings.txt"
            path.write_text(fixture, encoding="utf-8")
            completed = self.invoke_helper(
                "parse_target_build_settings", path, "HHVacancySber"
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            parsed = json.loads(completed.stdout)
            self.assertEqual("arm64", parsed["ARCHS"])
            self.assertEqual("NO", parsed["ONLY_ACTIVE_ARCH"])
            self.assertEqual("СберВакансии.app", parsed["WRAPPER_NAME"])
            self.assertNotIn("UNKNOWN_UPPERCASE", parsed)
            self.assertNotIn("BUNDLE_CONTENTS_FOLDER_PATH_deep", parsed)
            self.assertNotIn("must-be-ignored", completed.stdout)

            cases = {
                "missing": "Build settings for action build and target Other:\n"
                           "    ARCHS = arm64\n",
                "duplicate-section": fixture + textwrap.dedent(
                    """\
                    Build settings for action analyze and target HHVacancySber:
                        ARCHS = arm64
                    """
                ),
            }
            for name, content in cases.items():
                with self.subTest(case=name):
                    path.write_text(content, encoding="utf-8")
                    completed = self.invoke_helper(
                        "parse_target_build_settings", path, "HHVacancySber"
                    )
                    self.assertNotEqual(0, completed.returncode)
                    self.assertIn(
                        "expected exactly one build-settings section",
                        completed.stderr,
                    )

    def test_release_settings_parser_ignores_unknown_mixed_case_setting_and_continues_to_required_keys(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture_lines = self.settings_fixture().splitlines()
            fixture_lines.insert(
                fixture_lines.index("    ONLY_ACTIVE_ARCH = NO"),
                "    BUNDLE_CONTENTS_FOLDER_PATH_deep = Contents/",
            )
            path = Path(temporary) / "showBuildSettings.txt"
            path.write_text("\n".join(fixture_lines) + "\n", encoding="utf-8")
            completed = self.invoke_helper(
                "parse_target_build_settings", path, "HHVacancySber"
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            parsed = json.loads(completed.stdout)
            self.assertNotIn("BUNDLE_CONTENTS_FOLDER_PATH_deep", parsed)
            self.assertEqual("NO", parsed["ONLY_ACTIVE_ARCH"])
            self.assertEqual("СберВакансии.app", parsed["WRAPPER_NAME"])

    def test_release_settings_parser_extracts_only_consumer_required_keys(self):
        consumer_required_keys = {
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
        with tempfile.TemporaryDirectory() as temporary:
            fixture_lines = self.settings_fixture().splitlines()
            target_start = fixture_lines.index(
                "Build settings for action build and target HHVacancySber:"
            )
            fixture_lines[target_start + 1:target_start + 1] = [
                "    DEVELOPMENT_TEAM = ",
                "    PROVISIONING_PROFILE_SPECIFIER = ",
                "    UNKNOWN_UPPERCASE = first",
                "    UNKNOWN_UPPERCASE = second",
                "    Unknown_Mixed_Case = first",
                "    Unknown_Mixed_Case = second",
                "    unknown_lowercase = first",
                "    unknown_lowercase = second",
            ]
            path = Path(temporary) / "showBuildSettings.txt"
            path.write_text("\n".join(fixture_lines) + "\n", encoding="utf-8")
            completed = self.invoke_helper(
                "parse_target_build_settings", path, "HHVacancySber"
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            parsed = json.loads(completed.stdout)
            self.assertEqual(consumer_required_keys, set(parsed))
            self.assertEqual(0, len(set(parsed) - consumer_required_keys))

            duplicate_required = "\n".join(
                fixture_lines + ["    ARCHS = second-secret-value"]
            ) + "\n"
            path.write_text(duplicate_required, encoding="utf-8")
            completed = self.invoke_helper(
                "parse_target_build_settings", path, "HHVacancySber"
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertIn(
                "duplicate build setting in application target: ARCHS",
                completed.stderr,
            )
            self.assertNotIn("second-secret-value", completed.stderr)

    def test_release_contract_rejects_wrong_architecture(self):
        with tempfile.TemporaryDirectory() as temporary:
            for index, architecture in enumerate(("x86_64", "arm64 x86_64")):
                with self.subTest(architecture=architecture):
                    settings = self.write_settings(
                        temporary, {"ARCHS": architecture}
                    )
                    completed = self.invoke_helper(
                        "validate_release_settings", settings
                    )
                    self.assertNotEqual(0, completed.returncode)
                    self.assertIn("ARCHS", completed.stderr)
                    if index == 0:
                        settings.unlink()

    def test_release_contract_rejects_get_task_allow_injection(self):
        with tempfile.TemporaryDirectory() as temporary:
            settings = self.write_settings(
                temporary, {"CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "YES"}
            )
            completed = self.invoke_helper("validate_release_settings", settings)
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("CODE_SIGN_INJECT_BASE_ENTITLEMENTS", completed.stderr)
        isolated_environment = {
            "PATH": "/usr/bin:/bin",
            "GIT_INDEX_FILE": "/private/tmp/alternate-index-must-be-rejected",
            "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "YES",
        }
        completed = subprocess.run(
            [
                "/bin/bash",
                "-c",
                'source "$1"; release_reject_unsafe_environment',
                "release-environment-test",
                str(RELEASE_SCRIPT),
            ],
            env=isolated_environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("unsafe Git or Xcode override", completed.stderr)

    def test_release_contract_requires_sandbox_and_hardened_runtime(self):
        cases = (
            ("ENABLE_APP_SANDBOX", "NO"),
            ("ENABLE_HARDENED_RUNTIME", "NO"),
        )
        with tempfile.TemporaryDirectory() as temporary:
            for index, (key, value) in enumerate(cases):
                with self.subTest(setting=key):
                    settings = self.write_settings(temporary, {key: value})
                    completed = self.invoke_helper(
                        "validate_release_settings", settings
                    )
                    self.assertNotEqual(0, completed.returncode)
                    self.assertIn(key, completed.stderr)
                    if index == 0:
                        settings.unlink()

    def test_version_component_validation_rejects_unsafe_values(self):
        unsafe = ("", ".1", "-1", "1/2", "../1", "1 2", "1\n2")
        for value in unsafe:
            with self.subTest(value=value):
                completed = self.invoke_helper(
                    "validate_version_component", value
                )
                self.assertNotEqual(0, completed.returncode)
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "marker"
            completed = self.invoke_helper(
                "validate_version_component", "1;touch " + str(marker)
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertFalse(marker.exists())
        for value in ("1", "1.0", "build_1-rc.2"):
            completed = self.invoke_helper("validate_version_component", value)
            self.assertEqual(0, completed.returncode)

    def test_executable_name_validation_accepts_only_release_product_name(self):
        completed = self.invoke_helper(
            "validate_executable_name", "СберВакансии"
        )
        self.assertEqual(0, completed.returncode, completed.stderr)

        for value in (
            "",
            "HHVacancySber",
            "СберВакансии.app",
            "../СберВакансии",
            "СберВакансии/подмена",
            "СберВакансии\nподмена",
        ):
            with self.subTest(value=value):
                completed = self.invoke_helper("validate_executable_name", value)
                self.assertNotEqual(0, completed.returncode)

    def test_readme_has_fixed_neutral_first_launch_instruction(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "README.txt"
            completed = self.invoke_helper("write_release_readme", destination)
            self.assertEqual(0, completed.returncode, completed.stderr)
            content = destination.read_text(encoding="utf-8")
            self.assertIn("3. Запустите «СберВакансии».", content)
            self.assertIn("стандартное предупреждение безопасности", content)
            self.assertIn("полученную из доверенного источника", content)

    def test_readme_contains_no_gatekeeper_bypass_command(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "README.txt"
            completed = self.invoke_helper("write_release_readme", destination)
            self.assertEqual(0, completed.returncode, completed.stderr)
            content = destination.read_text(encoding="utf-8")
            for forbidden in (
                "spctl --master-disable",
                "xattr -dr",
                "sudo",
                "Terminal",
            ):
                self.assertNotIn(forbidden, content)

    def test_manifest_is_sorted_relative_and_deterministic(self):
        commit = "a" * 40
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first"
            second = Path(temporary) / "second"
            first.mkdir()
            second.mkdir()
            first_executable = self.create_staging_payload(first)
            self.create_staging_payload(second)
            first_manifest = first / "RELEASE-MANIFEST.json"
            second_manifest = second / "RELEASE-MANIFEST.json"
            for root, manifest in (
                (first, first_manifest),
                (second, second_manifest),
            ):
                completed = self.invoke_helper(
                    "generate_release_manifest",
                    root,
                    manifest,
                    commit,
                    "local.sergey.HHVacancySber",
                    "1.0",
                    "1",
                )
                self.assertEqual(0, completed.returncode, completed.stderr)
            first_bytes = first_manifest.read_bytes()
            self.assertEqual(first_bytes, second_manifest.read_bytes())
            parsed = json.loads(first_bytes.decode("utf-8"))
            canonical = (
                json.dumps(parsed, ensure_ascii=False, indent=2, sort_keys=True)
                + "\n"
            ).encode("utf-8")
            self.assertEqual(canonical, first_bytes)
            paths = [record["path"] for record in parsed["payload"]]
            self.assertEqual(sorted(paths), paths)
            self.assertEqual(len(paths), len(set(paths)))
            self.assertEqual(
                [
                    "Applications",
                    "README.txt",
                    "СберВакансии.app/Contents/Current",
                    "СберВакансии.app/Contents/MacOS/СберВакансии",
                ],
                paths,
            )
            self.assertNotIn("RELEASE-MANIFEST.json", paths)
            self.assertTrue(all(not path.startswith("/") for path in paths))
            self.assertTrue(all(".." not in Path(path).parts for path in paths))
            executable_record = next(
                record
                for record in parsed["payload"]
                if record["path"]
                == "СберВакансии.app/Contents/MacOS/СберВакансии"
            )
            self.assertEqual(
                hashlib.sha256(first_executable.read_bytes()).hexdigest(),
                executable_record["sha256"],
            )
            self.assertEqual("0755", executable_record["mode"])
            symlinks = {
                record["path"]: record
                for record in parsed["payload"]
                if record["type"] == "symlink"
            }
            self.assertEqual("/Applications", symlinks["Applications"]["target"])
            self.assertEqual("MacOS", symlinks[
                "СберВакансии.app/Contents/Current"
            ]["target"])
            self.assertTrue(all(
                record["mode"] == "0777" for record in symlinks.values()
            ))
            serialized = first_bytes.decode("utf-8").lower()
            for unstable in (
                '"timestamp"', '"mtime"', '"ctime"', '"inode"',
                '"device"', '"hostname"', '"username"',
            ):
                self.assertNotIn(unstable, serialized)

    def test_payload_contract_has_exact_required_top_level_entries(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "staging"
            root.mkdir()
            self.create_staging_payload(root)
            manifest = root / "RELEASE-MANIFEST.json"
            manifest.write_text("{}\n", encoding="utf-8")
            ds_store = root / ".DS_Store"
            ds_store.write_bytes(b"finder-presentation")
            completed = self.invoke_helper("verify_exact_payload_root", root)
            self.assertEqual(0, completed.returncode, completed.stderr)
            unexpected = root / ".unexpected"
            unexpected.write_bytes(b"unexpected")
            completed = self.invoke_helper("verify_exact_payload_root", root)
            self.assertNotEqual(0, completed.returncode)
            unexpected.unlink()
            (root / "README.txt").unlink()
            completed = self.invoke_helper("verify_exact_payload_root", root)
            self.assertNotEqual(0, completed.returncode)

    def test_macos_fsevents_metadata_is_removed_without_weakening_payload_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "mounted"
            root.mkdir()
            self.create_staging_payload(root)
            (root / "RELEASE-MANIFEST.json").write_text("{}\n", encoding="utf-8")
            metadata = root / ".fseventsd"
            metadata.mkdir()
            (metadata / "fseventsd-uuid").write_text("fixture\n", encoding="utf-8")

            contaminated = self.invoke_helper(
                "release_python",
                "exact-entries",
                root,
                "СберВакансии.app",
                "Applications",
                "README.txt",
                "RELEASE-MANIFEST.json",
            )
            self.assertNotEqual(0, contaminated.returncode)

            removed = self.invoke_helper(
                "release_python", "remove-fseventsd", root
            )
            self.assertEqual(0, removed.returncode, removed.stderr)
            self.assertFalse(metadata.exists())
            exact = self.invoke_helper(
                "release_python",
                "exact-entries",
                root,
                "СберВакансии.app",
                "Applications",
                "README.txt",
                "RELEASE-MANIFEST.json",
            )
            self.assertEqual(0, exact.returncode, exact.stderr)

            metadata.mkdir()
            nested = metadata / "unexpected"
            nested.mkdir()
            refused = self.invoke_helper(
                "release_python", "remove-fseventsd", root
            )
            self.assertNotEqual(0, refused.returncode)
            self.assertTrue(nested.is_dir())

    def test_dmg_readme_is_deterministic_utf8_plain_text_with_required_sections(self):
        expected = (
            "СберВакансии\n"
            "=============\n\n"
            "СберВакансии — настольное приложение для macOS, предназначенное для поиска,\n"
            "просмотра и сохранения вакансий HeadHunter.\n\n"
            "Приложение не является официальным продуктом HeadHunter.\n\n"
            "ВОЗМОЖНОСТИ\n"
            "-----------\n\n"
            "• поиск вакансий и просмотр результатов в единой вертикальной ленте;\n"
            "• загрузка подробного описания вакансии по запросу;\n"
            "• сохранение избранных вакансий на этом Mac;\n"
            "• экспорт отдельной вакансии в PDF;\n"
            "• пакетный экспорт выбранных вакансий в PDF;\n"
            "• автоматическое разбиение больших PDF-подборок на несколько файлов.\n\n"
            "УСТАНОВКА\n"
            "---------\n\n"
            "1. Перетащите приложение «СберВакансии» на значок «Программы».\n"
            "2. Откройте папку «Программы».\n"
            "3. Запустите «СберВакансии».\n\n"
            "СИСТЕМНЫЕ ТРЕБОВАНИЯ\n"
            "--------------------\n\n"
            "• macOS 13 или новее;\n"
            "• Mac с Apple silicon (arm64);\n"
            "• подключение к интернету для поиска и загрузки вакансий.\n\n"
            "ЛОКАЛЬНЫЕ ДАННЫЕ\n"
            "----------------\n\n"
            "Избранные вакансии и пользовательские настройки сохраняются локально на этом\n"
            "Mac.\n\n"
            "ПОДПИСЬ СБОРКИ\n"
            "--------------\n\n"
            "Эта сборка подписана ad hoc и не нотарифицирована Apple. При первом запуске\n"
            "macOS может показать стандартное предупреждение безопасности. Используйте\n"
            "только сборку, полученную из доверенного источника.\n"
        ).encode("utf-8")
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first.txt"
            second = Path(temporary) / "second.txt"
            for destination in (first, second):
                completed = self.invoke_helper("write_release_readme", destination)
                self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual(expected, first.read_bytes())
            self.assertEqual(expected, second.read_bytes())
            content = first.read_bytes()
            self.assertEqual(expected.decode("utf-8"), content.decode("utf-8"))
            self.assertFalse(content.startswith(b"\xef\xbb\xbf"))
            self.assertNotIn(b"\r", content)
            self.assertNotIn(b"\t", content)
            self.assertTrue(content.endswith(b"\n"))
            self.assertTrue(all(
                line == line.rstrip(b" ") for line in content.splitlines()
            ))
            self.assertNotIn(b"{\\rtf", content.lower())
            self.assertNotIn(b"<html", content.lower())

    def test_dmg_readme_describes_core_features_and_installation_without_security_bypass(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "README.txt"
            completed = self.invoke_helper("write_release_readme", destination)
            self.assertEqual(0, completed.returncode, completed.stderr)
            content = destination.read_text(encoding="utf-8")
            for required in (
                "HeadHunter",
                "поиск вакансий",
                "единой вертикальной ленте",
                "подробного описания вакансии",
                "избранных вакансий",
                "экспорт отдельной вакансии в PDF",
                "пакетный экспорт выбранных вакансий в PDF",
                "macOS 13",
                "arm64",
                "подключение к интернету",
                "сохраняются локально",
                "ad hoc",
                "не нотарифицирована",
                "Перетащите приложение «СберВакансии»",
            ):
                self.assertIn(required, content)
            for forbidden in (
                "xattr",
                "spctl",
                "quarantine",
                "Gatekeeper",
                "настройки безопасности",
                "Terminal",
                "Терминал",
            ):
                self.assertNotIn(forbidden, content)

    def test_dmg_finder_layout_sets_persistable_macos13_icon_view(self):
        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        customization = source.split(
            "release_customize_finder_layout() {", 1
        )[1].split("release_persist_live_finder_layout() {", 1)[0]
        for required in (
            "set current view of presentationWindow to icon view",
            "set icon size of presentationOptions to 48",
            "set arrangement of presentationOptions to arranged by name",
            "set toolbar visible of presentationWindow to false",
            "set statusbar visible of presentationWindow to false",
            "set pathbar visible of presentationWindow to false",
            "set shows item info of presentationOptions to true",
            "set shows icon preview of presentationOptions to true",
            "set bounds of presentationWindow to {100, 100, 1500, 1000}",
            "with timeout of 300 seconds",
            "release_run_with_timeout 310 /usr/bin/osascript",
        ):
            self.assertIn(required, customization)
        for forbidden in (" to 512", " to 256", " to 128"):
            self.assertNotIn(forbidden, customization)
        self.assertNotIn("defaults ", source)
        self.assertNotIn("killall Finder", source)
        self.assertNotIn("pkill Finder", source)
        self.assertNotIn('tell application "Finder" to quit', source)
        self.assertNotIn("update presentationFolder", customization)
        persistence = source.split(
            "release_persist_live_finder_layout() {", 1
        )[1].split("release_classify_finder_customization_result() {", 1)[0]
        self.assertIn("ignoring application responses", persistence)
        self.assertIn(
            "update presentationFolder without registering applications",
            persistence,
        )
        self.assertIn("end tell\n    delay 2\n  end timeout", persistence)
        self.assertIn(
            '"$RELEASE_MOUNTED_ROOT_IDENTITY" 8',
            RELEASE_SCRIPT.read_text(encoding="utf-8"),
        )
        production = RELEASE_SCRIPT.read_text(encoding="utf-8").split("main() {", 1)[1]
        close_position = production.index("release_close_finder_window")
        first_sync_position = production.index("/bin/sync", close_position)
        stability_position = production.index(
            "release_wait_for_stable_ds_store", close_position
        )
        self.assertLess(close_position, first_sync_position)
        self.assertLess(first_sync_position, stability_position)
        self.assertIn("PRE_DETACH_DS_STORE_STABLE=yes", production)

    def test_dmg_finder_layout_is_scoped_to_owned_windows_and_preserves_global_finder_state(self):
        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        customization = source.split(
            "release_customize_finder_layout() {", 1
        )[1].split("release_classify_finder_customization_result() {", 1)[0]
        readback = source.split(
            "release_read_finder_layout() {", 1
        )[1].split("generate_release_manifest() {", 1)[0]
        self.assertIn('/usr/bin/osascript - "$target"', customization)
        self.assertIn("on run argv", customization)
        self.assertIn("item 1 of argv", customization)
        self.assertIn("release_authenticate_presentation_root", customization)
        self.assertIn('"$target" "$owned_root" "$expected_leaf"', customization)
        self.assertIn(
            'if matchingWindowCount is not 0 then error "presentation window is already open"',
            customization,
        )
        self.assertNotIn("repeat with candidateWindow in every Finder window", source)
        self.assertEqual(
            4,
            source.count("repeat with windowIndex from 1 to count of Finder windows"),
        )
        self.assertEqual(4, source.count("set candidateWindow to Finder window windowIndex"))
        self.assertNotIn("close presentationWindow", customization)
        self.assertIn('/usr/bin/osascript - "$target"', readback)
        self.assertGreaterEqual(
            source.count("release_run_with_timeout 310 /usr/bin/osascript"), 3
        )
        self.assertIn("release_authenticate_presentation_root", readback)
        self.assertNotIn("close reviewWindow", readback)
        self.assertIn("release_close_finder_window() {", readback)
        self.assertIn("close exactWindow", readback)
        self.assertNotIn("close every Finder window", source)
        self.assertNotIn("quit application \"Finder\"", source)
        production = source.split("main() {", 1)[1]
        self.assertEqual(1, production.count("release_customize_finder_layout"))
        self.assertEqual(1, production.count("release_persist_live_finder_layout"))
        self.assertLess(
            production.index("release_persist_live_finder_layout"),
            production.index("release_read_finder_layout"),
        )
        live_persistence_position = production.index(
            "release_persist_live_finder_layout"
        )
        live_stability_position = production.index(
            "release_wait_for_stable_ds_store", live_persistence_position
        )
        live_readback_position = production.index(
            "release_read_finder_layout", live_persistence_position
        )
        self.assertLess(live_persistence_position, live_stability_position)
        self.assertLess(live_stability_position, live_readback_position)
        self.assertIn("LIVE_FINDER_DS_STORE_STABILITY=pass", production)
        self.assertIn('"$writable_mount" "$RELEASE_WORK_ROOT" writable-mount', production)
        self.assertNotIn(
            'release_customize_finder_layout "$source_payload"', production
        )

    def test_external_timeout_runner_bounds_unresponsive_process(self):
        import time

        started = time.monotonic()
        completed = self.invoke_helper(
            "release_run_with_timeout", "0.05", "/bin/sleep", "5"
        )
        elapsed = time.monotonic() - started
        self.assertEqual(124, completed.returncode)
        self.assertLess(elapsed, 2.0)
        self.assertIn("EXTERNAL_PROCESS_TIMEOUT_SECONDS=0.05", completed.stderr)

        completed = self.invoke_helper(
            "release_run_with_timeout", "1", "/usr/bin/true"
        )
        self.assertEqual(0, completed.returncode, completed.stderr)

    def test_dmg_finder_layout_requires_stable_nonempty_ds_store_and_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            owned = Path(temporary).resolve() / "owned"
            mounted = owned / "writable-mount"
            mounted.mkdir(parents=True)
            ds_store = mounted / ".DS_Store"
            ds_store.write_bytes(b"stable-finder-layout")
            completed = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted, owned, "2", "0", "writable-mount",
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertIn("DS_STORE_FIRST_OBSERVED_UTC=", completed.stdout)
            self.assertIn("DS_STORE_STABLE_OBSERVATIONS=2", completed.stdout)
            self.assertIn("DS_STORE_DEVICE=", completed.stdout)
            self.assertIn("DS_STORE_INODE=", completed.stdout)
            self.assertIn("DS_STORE_MODE=", completed.stdout)
            self.assertIn("DS_STORE_SIZE=", completed.stdout)
            self.assertIn("DS_STORE_SHA256=", completed.stdout)

            ds_store.unlink()
            missing = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted, owned, "2", "0", "writable-mount",
            )
            self.assertNotEqual(0, missing.returncode)

            ds_store.write_bytes(b"")
            empty = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted, owned, "2", "0", "writable-mount",
            )
            self.assertNotEqual(0, empty.returncode)

            ds_store.unlink()
            outside_file = owned / "outside-ds-store"
            outside_file.write_bytes(b"outside")
            os.symlink(outside_file, ds_store)
            linked = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted, owned, "2", "0", "writable-mount",
            )
            self.assertNotEqual(0, linked.returncode)

            ds_store.unlink()
            other = owned / "other"
            other.mkdir()
            (other / ".DS_Store").write_bytes(b"outside-staging")
            outside = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                other, owned, "2", "0", "writable-mount",
            )
            self.assertNotEqual(0, outside.returncode)

            ds_store.write_bytes(b"changing")
            changing = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted, owned, "1", "0", "writable-mount",
            )
            self.assertNotEqual(0, changing.returncode)
            invalid_window = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted, owned, "2", "0", "writable-mount", "", "3",
            )
            self.assertNotEqual(0, invalid_window.returncode)
            source = RELEASE_SCRIPT.read_text(encoding="utf-8")
            production = source.split("main() {", 1)[1]
            self.assertNotIn(
                'release_wait_for_stable_ds_store \\\n'
                '      "$source_payload"',
                production,
            )

    def test_finder_customization_timeout_is_provisional_only_after_verified_readback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            timeout_stderr = root / "timeout.stderr"
            timeout_stderr.write_text(
                "225:264: execution error: Finder AppleEvent timed out. (-1712)\n",
                encoding="utf-8",
            )
            classification = self.invoke_helper(
                "release_classify_finder_customization_result",
                "1",
                timeout_stderr,
            )
            self.assertEqual(0, classification.returncode, classification.stderr)
            self.assertIn(
                "FINDER_CUSTOMIZATION_STATUS=indeterminate_timeout",
                classification.stdout,
            )
            self.assertIn(
                "FINDER_CUSTOMIZATION_RETRY_COUNT=0",
                classification.stdout,
            )

            owned = root / "owned"
            mounted = owned / "writable-mount"
            mounted.mkdir(parents=True)
            ds_store = mounted / ".DS_Store"
            self.assertFalse(ds_store.exists())
            readback_accepted = self.invoke_helper(
                "release_validate_finder_readback",
                "pass",
                "icon view",
                "48",
                "arranged by name",
                "false",
                "false",
                "false",
                "true",
                "true",
                "1400",
                "900",
            )
            self.assertEqual(
                0, readback_accepted.returncode, readback_accepted.stderr
            )
            ds_store.write_bytes(b"stable-timeout-presentation")
            post_close_stability = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted,
                owned,
                "2",
                "0",
                "writable-mount",
            )
            self.assertEqual(
                0,
                post_close_stability.returncode,
                post_close_stability.stderr,
            )
            accepted = self.invoke_helper(
                "release_validate_finder_lifecycle",
                "indeterminate_timeout",
                "pass",
                "1",
                "pass",
                "pass",
                "pass",
                "pass",
                "pass",
            )
            self.assertEqual(0, accepted.returncode, accepted.stderr)
            self.assertIn("FINDER_LIFECYCLE_ACCEPTED=yes", accepted.stdout)
            source = RELEASE_SCRIPT.read_text(encoding="utf-8")
            production = source.split("main() {", 1)[1]
            self.assertEqual(1, production.count("release_customize_finder_layout"))
            self.assertIn("FINDER_CUSTOMIZATION_RETRY_COUNT=0", source)
            customization = production.index("release_customize_finder_layout")
            readback = production.index(
                "release_read_finder_layout", customization
            )
            close = production.index("release_close_finder_window", readback)
            stability = production.index(
                "release_wait_for_stable_ds_store", close
            )
            self.assertLess(customization, readback)
            self.assertLess(readback, close)
            self.assertLess(close, stability)

            ds_store.unlink()
            missing = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted,
                owned,
                "2",
                "0",
                "writable-mount",
            )
            self.assertNotEqual(0, missing.returncode)
            ds_store.write_bytes(b"not-yet-stable")
            unstable = self.invoke_owned_helper(
                owned,
                "release_wait_for_stable_ds_store",
                mounted,
                owned,
                "1",
                "0",
                "writable-mount",
            )
            self.assertNotEqual(0, unstable.returncode)

            rejected_cases = (
                ("fatal_error", "pass", "1", "pass", "pass", "pass", "pass", "pass"),
                ("indeterminate_timeout", "fail", "1", "pass", "pass", "pass", "pass", "pass"),
                ("indeterminate_timeout", "pass", "0", "pass", "pass", "pass", "pass", "pass"),
                ("indeterminate_timeout", "pass", "1", "fail", "pass", "pass", "pass", "pass"),
                ("indeterminate_timeout", "pass", "1", "pass", "fail", "pass", "pass", "pass"),
                ("indeterminate_timeout", "pass", "1", "pass", "pass", "fail", "pass", "pass"),
                ("indeterminate_timeout", "pass", "1", "pass", "pass", "pass", "fail", "pass"),
                ("indeterminate_timeout", "pass", "1", "pass", "pass", "pass", "pass", "fail"),
            )
            for lifecycle in rejected_cases:
                with self.subTest(lifecycle=lifecycle):
                    rejected = self.invoke_helper(
                        "release_validate_finder_lifecycle",
                        *lifecycle,
                    )
                    self.assertNotEqual(0, rejected.returncode)

    def test_finder_customization_non_timeout_error_fails_closed_without_retry(self):
        cases = (
            "1:2: execution error: Automation permission denied. (-1743)\n",
            "1:2: syntax error: Expected expression. (-2741)\n",
            "1:2: execution error: Invalid staging path. (-43)\n",
            "unexpected nonzero result\n",
            "1:2: execution error: timed out then denied. (-1712) (-1743)\n",
            "1:2: execution error: invalid path (-43); AppleEvent timed out. (-1712)\n",
        )
        with tempfile.TemporaryDirectory() as temporary:
            for index, diagnostic in enumerate(cases):
                with self.subTest(diagnostic=diagnostic):
                    stderr_path = Path(temporary) / ("error-%d.stderr" % index)
                    stderr_path.write_text(diagnostic, encoding="utf-8")
                    classified = self.invoke_helper(
                        "release_classify_finder_customization_result",
                        "1",
                        stderr_path,
                    )
                    self.assertNotEqual(0, classified.returncode)
                    self.assertIn(
                        "FINDER_CUSTOMIZATION_STATUS=fatal_error",
                        classified.stdout,
                    )
                    self.assertIn(
                        "FINDER_CUSTOMIZATION_RETRY_COUNT=0",
                        classified.stdout,
                    )
                    self.assertNotIn(
                        "FINDER_CUSTOMIZATION_STATUS=indeterminate_timeout",
                        classified.stdout,
                    )

        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        production = source.split(
            'manifest_path="$source_payload/RELEASE-MANIFEST.json"', 1
        )[1].split('dmg_basename="', 1)[0]
        classification_position = production.index(
            "release_classify_finder_customization_result"
        )
        persistence_position = production.index(
            "release_persist_live_finder_layout", classification_position
        )
        self.assertLess(classification_position, persistence_position)
        fatal_branch = production[
            classification_position:persistence_position
        ]
        self.assertIn("return \"$finder_status\"", fatal_branch)
        self.assertNotIn("release_read_finder_layout", fatal_branch)
        self.assertNotIn("release_close_finder_window", fatal_branch)
        self.assertNotIn("release_wait_for_stable_ds_store", fatal_branch)
        self.assertNotIn("release_detach_attached_image", fatal_branch)
        self.assertNotIn("hdiutil convert", fatal_branch)
        self.assertIn("release_report_retained_work", source)
        self.assertIn("release lock retained for manual inspection", source)
        self.assertGreater(
            source.index("RELEASE_ALLOW_LOCK_RELEASE=1"),
            source.index("hdiutil-convert.command"),
        )

    def test_finder_window_closes_only_after_readback_and_requires_post_close_ds_store_stability(self):
        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        production = source.split(
            'source_payload="$RELEASE_WORK_ROOT/source-payload"', 1
        )[1].split('dmg_hash="', 1)[0]
        customize = production.index("release_customize_finder_layout \\")
        persistence = production.index("release_persist_live_finder_layout \\", customize)
        live_stability = production.index("release_wait_for_stable_ds_store \\", persistence)
        readback = production.index("release_read_finder_layout \\", live_stability)
        close = production.index("release_close_finder_window \\", readback)
        post_close_stability = production.index("release_wait_for_stable_ds_store \\", close)
        positions = [
            production.index("/usr/bin/hdiutil create \\"),
            production.index("/usr/bin/hdiutil attach \\"),
            customize,
            persistence,
            live_stability,
            readback,
            production.index("release_validate_finder_readback \\", readback),
            close,
            post_close_stability,
            production.index("release_detach_attached_image writable-image"),
            production.index('/usr/bin/hdiutil convert "$writable_image"'),
            production.index('/usr/bin/hdiutil verify "$temp_dmg"'),
        ]
        self.assertEqual(sorted(positions), positions)
        self.assertLess(live_stability, close)
        self.assertLess(close, post_close_stability)
        self.assertEqual(
            1,
            production.count(
                'release_close_finder_window \\\n'
                '      "$writable_mount"'
            ),
        )
        customization = source.split(
            "release_customize_finder_layout() {", 1
        )[1].split(
            "release_classify_finder_customization_result() {", 1
        )[0]
        readback = source.split(
            "release_read_finder_layout() {", 1
        )[1].split("release_close_finder_window() {", 1)[0]
        self.assertNotIn("close ", customization)
        self.assertNotIn("close ", readback)
        self.assertNotIn("close every Finder window", source)
        self.assertNotIn("killall Finder", source)
        self.assertNotIn("pkill Finder", source)
        self.assertNotIn('tell application "Finder" to quit', source)
        self.assertNotIn('quit application "Finder"', source)
        self.assertNotIn("defaults write", source)
        self.assertNotIn("defaults delete", source)

    def test_finder_presentation_uses_writable_hfs_image_not_plain_source_folder(self):
        with tempfile.TemporaryDirectory() as temporary:
            payload = Path(temporary) / "source-payload"
            payload.mkdir()
            (payload / "СберВакансии.app").mkdir()
            os.symlink("/Applications", payload / "Applications")
            (payload / "README.txt").write_text("readme\n", encoding="utf-8")
            (payload / "RELEASE-MANIFEST.json").write_text(
                "{}\n", encoding="utf-8"
            )
            exact = self.invoke_helper(
                "release_python",
                "exact-entries",
                payload,
                "СберВакансии.app",
                "Applications",
                "README.txt",
                "RELEASE-MANIFEST.json",
            )
            self.assertEqual(0, exact.returncode, exact.stderr)
            self.assertIn("ROOT_PHYSICAL_ENTRY_COUNT=4", exact.stdout)
            self.assertIn("ROOT_HIDDEN_ENTRY_COUNT=0", exact.stdout)

            (payload / ".DS_Store").write_bytes(b"source-contamination")
            contaminated = self.invoke_helper(
                "release_python",
                "exact-entries",
                payload,
                "СберВакансии.app",
                "Applications",
                "README.txt",
                "RELEASE-MANIFEST.json",
            )
            self.assertNotEqual(0, contaminated.returncode)

            mountpoint = Path(temporary) / "writable-mount"
            mountpoint.mkdir()
            diskinfo = Path(temporary) / "writable-diskinfo.plist"
            with diskinfo.open("wb") as stream:
                plistlib.dump(
                    {
                        "DeviceNode": "/dev/disk9s1",
                        "FilesystemType": "hfs",
                        "MountPoint": str(mountpoint),
                        "VolumeName": "СберВакансии",
                        "Writable": True,
                        "WritableVolume": True,
                        "WritableMedia": True,
                    },
                    stream,
                )
            writable = self.invoke_helper(
                "release_python",
                "writable-diskinfo-check",
                diskinfo,
                "/dev/disk9s1",
                mountpoint,
            )
            self.assertEqual(0, writable.returncode, writable.stderr)
            self.assertEqual(
                "DMG_WRITABLE_SCHEMA=macos13-writable-flags\n",
                writable.stdout,
            )

        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        production = source.split("main() {", 1)[1]
        self.assertIn(
            'writable_image="$RELEASE_WORK_ROOT/HHVacancySber-writable.dmg"',
            production,
        )
        self.assertIn("-format UDRW", production)
        self.assertIn("-fs HFS+", production)
        self.assertIn('-srcfolder "$source_payload"', production)
        create_call = production.split(
            "if /usr/bin/hdiutil create \\", 1
        )[1].split("; then", 1)[0]
        self.assertIn("-format UDRW", create_call)
        self.assertIn("-fs HFS+", create_call)
        self.assertIn('-srcfolder "$source_payload"', create_call)
        attach_call = production.split(
            "if /usr/bin/hdiutil attach \\", 1
        )[1].split("; then", 1)[0]
        self.assertIn("-readwrite", attach_call)
        self.assertIn("-nobrowse", attach_call)
        self.assertIn('-mountpoint "$writable_mount"', attach_call)
        self.assertIn('"$writable_image"', attach_call)
        self.assertEqual(1, production.count("release_customize_finder_layout"))
        customization_call = production.split(
            "if release_customize_finder_layout \\", 1
        )[1].split("; then", 1)[0]
        self.assertIn(
            '"$writable_mount" "$RELEASE_WORK_ROOT" writable-mount',
            customization_call,
        )
        self.assertNotIn("$source_payload", customization_call)
        finder_calls = [
            block.split("; then", 1)[0]
            for block in production.split("release_read_finder_layout")[1:]
        ]
        self.assertGreaterEqual(len(finder_calls), 2)
        self.assertTrue(all("$source_payload" not in call for call in finder_calls))
        self.assertIn("SOURCE_PAYLOAD_DS_STORE=absent", production)

    def test_finder_readback_precedes_close_and_ds_store_stability_follows_close(self):
        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        production = source.split(
            'source_payload="$RELEASE_WORK_ROOT/source-payload"', 1
        )[1].split('dmg_hash="', 1)[0]
        customize = production.index("release_customize_finder_layout \\")
        persistence = production.index("release_persist_live_finder_layout \\", customize)
        live_stability = production.index("release_wait_for_stable_ds_store \\", persistence)
        readback = production.index("release_read_finder_layout \\", live_stability)
        close = production.index("release_close_finder_window \\", readback)
        stability = production.index("release_wait_for_stable_ds_store \\", close)
        positions = [
            production.index("/usr/bin/hdiutil create \\"),
            production.index("/usr/bin/hdiutil attach \\"),
            customize,
            persistence,
            live_stability,
            readback,
            production.index("release_validate_finder_readback \\", readback),
            close,
            stability,
            production.index("release_detach_attached_image writable-image"),
            production.index('/usr/bin/hdiutil convert "$writable_image"'),
            production.index('/usr/bin/hdiutil verify "$temp_dmg"'),
        ]
        self.assertEqual(sorted(positions), positions)
        self.assertLess(live_stability, close)
        self.assertLess(close, stability)
        self.assertEqual(1, production.count("release_customize_finder_layout"))
        self.assertEqual(
            1,
            production.count(
                'release_close_finder_window \\\n'
                '      "$writable_mount"'
            ),
        )
        self.assertEqual(
            2,
            production.count(
                'release_wait_for_stable_ds_store \\\n'
                '      "$writable_mount"'
            ),
        )
        detach = production.index(
            "release_detach_attached_image writable-image"
        )
        convert = production.index('/usr/bin/hdiutil convert "$writable_image"')
        detach_end = production.index("\n  fi\n", detach) + len("\n  fi")
        detach_failure = production[
            detach:detach_end
        ]
        self.assertIn("return 1", detach_failure)
        self.assertLess(detach_end, convert)
        self.assertNotIn("-format UDZO", production[:detach])

    def test_finder_probe_keeps_evidence_outside_exact_four_entry_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / "payload"
            evidence = root / "evidence"
            images = root / "images"
            mounts = root / "mounts"
            for directory in (payload, evidence, images, mounts):
                directory.mkdir()
            (payload / "Probe.app").mkdir()
            os.symlink("/Applications", payload / "Applications")
            (payload / "README.txt").write_text("probe\n", encoding="utf-8")
            (payload / "manifest.json").write_text("{}\n", encoding="utf-8")
            (evidence / "customization.status").write_text(
                "EXIT_STATUS=0\n", encoding="utf-8"
            )

            exact_payload = self.invoke_helper(
                "release_python",
                "exact-entries",
                payload,
                "Probe.app",
                "Applications",
                "README.txt",
                "manifest.json",
            )
            self.assertEqual(
                0, exact_payload.returncode, exact_payload.stderr
            )
            self.assertEqual(
                ["Applications", "Probe.app", "README.txt", "manifest.json"],
                sorted(path.name for path in payload.iterdir()),
            )

            payload_status = payload / "probe.status"
            payload_status.write_text("invalid\n", encoding="utf-8")
            contaminated = self.invoke_helper(
                "release_python",
                "exact-entries",
                payload,
                "Probe.app",
                "Applications",
                "README.txt",
                "manifest.json",
            )
            self.assertNotEqual(0, contaminated.returncode)
            payload_status.unlink()

            for mount_name in ("writable", "readonly"):
                mounted = mounts / mount_name
                mounted.mkdir()
                (mounted / "Probe.app").mkdir()
                os.symlink("/Applications", mounted / "Applications")
                (mounted / "README.txt").write_text(
                    "probe\n", encoding="utf-8"
                )
                (mounted / "manifest.json").write_text(
                    "{}\n", encoding="utf-8"
                )
                if mount_name == "writable":
                    exact_initial_writable = self.invoke_helper(
                        "release_python",
                        "exact-entries",
                        mounted,
                        "Probe.app",
                        "Applications",
                        "README.txt",
                        "manifest.json",
                    )
                    self.assertEqual(
                        0,
                        exact_initial_writable.returncode,
                        exact_initial_writable.stderr,
                    )
                (mounted / ".DS_Store").write_bytes(b"presentation")
                exact_mounted = self.invoke_helper(
                    "release_python",
                    "exact-entries",
                    mounted,
                    ".DS_Store",
                    "Probe.app",
                    "Applications",
                    "README.txt",
                    "manifest.json",
                )
                self.assertEqual(
                    0, exact_mounted.returncode, exact_mounted.stderr
                )
                (mounted / "readback.log").write_text(
                    "invalid\n", encoding="utf-8"
                )
                extra = self.invoke_helper(
                    "release_python",
                    "exact-entries",
                    mounted,
                    ".DS_Store",
                    "Probe.app",
                    "Applications",
                    "README.txt",
                    "manifest.json",
                )
                self.assertNotEqual(0, extra.returncode)
                (mounted / "readback.log").unlink()
            (images / "probe-writable.dmg").write_bytes(b"udrw")
            (images / "probe-final.dmg").write_bytes(b"udzo")
            self.assertTrue((evidence / "customization.status").is_file())
            self.assertFalse(any(path.suffix in (".log", ".status")
                                 for path in payload.iterdir()))
            self.assertEqual(
                ["probe-final.dmg", "probe-writable.dmg"],
                sorted(path.name for path in images.iterdir()),
            )
            self.assertNotEqual(payload, evidence)
            self.assertNotEqual(payload, images)
            self.assertNotEqual(payload, mounts)

        production = RELEASE_SCRIPT.read_text(encoding="utf-8").split(
            "main() {", 1
        )[1]
        for payload_root in (
            "$source_payload/",
            "$writable_mount/",
            "$readonly_mount/",
        ):
            self.assertNotIn('> "' + payload_root, production)
        self.assertIn('RELEASE_LOG_DIR="$RELEASE_WORK_ROOT/logs"', production)

    def test_writable_image_detaches_before_udzo_conversion_and_is_retained(self):
        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        production = source.split(
            'source_payload="$RELEASE_WORK_ROOT/source-payload"', 1
        )[1].split('dmg_hash="', 1)[0]
        detach = production.index(
            "release_detach_attached_image writable-image"
        )
        convert = production.index('/usr/bin/hdiutil convert "$writable_image"')
        self.assertLess(detach, convert)
        self.assertEqual(
            1, production.count("release_detach_attached_image writable-image")
        )
        detach_end = production.index("\n  fi\n", detach) + len("\n  fi")
        detach_failure = production[
            detach:detach_end
        ]
        self.assertIn("return 1", detach_failure)
        self.assertLess(detach_end, convert)
        self.assertIn(
            'writable_image="$RELEASE_WORK_ROOT/HHVacancySber-writable.dmg"',
            production,
        )
        self.assertIn("WRITABLE_IMAGE_RETAINED=yes", production)
        self.assertIn(
            'release_authenticate_owned_image_path \\\n'
            '    "$writable_image" "$RELEASE_WORK_ROOT"',
            production,
        )
        publication = source.split("if ! publish_no_clobber \\", 1)[1].split(
            "; then", 1
        )[0]
        self.assertNotIn("writable_image", publication)
        self.assertIn('"$temp_dmg" "$final_dmg"', publication)
        self.assertIn('"$temp_checksum" "$final_checksum"', publication)
        self.assertIn('"$temp_manifest" "$final_manifest"', publication)
        cleanup = source.split("release_cleanup_resources() {", 1)[1].split(
            "release_exit_trap() {", 1
        )[0]
        self.assertNotIn("hdiutil detach", cleanup)
        self.assertNotIn("-force", source)
        self.assertNotIn("rm -rf", source)
        self.assertNotRegex(
            source,
            r"(?s)/(?:bin|usr/bin)/(?:rm|unlink).{0,160}\$writable_image",
        )
        self.assertNotIn("safe_remove_owned_tree", source)

    def test_final_readonly_mount_preserves_ds_store_and_icon_view(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ds_store = root / ".DS_Store"
            content = b"stable-writable-presentation"
            ds_store.write_bytes(content)
            digest = hashlib.sha256(content).hexdigest()
            matched = self.invoke_helper(
                "release_python", "ds-store-check", ds_store, digest
            )
            self.assertEqual(0, matched.returncode, matched.stderr)
            self.assertIn("DS_STORE_SHA256=" + digest, matched.stdout)

            mismatch = self.invoke_helper(
                "release_python", "ds-store-check", ds_store, "0" * 64
            )
            self.assertNotEqual(0, mismatch.returncode)
            ds_store.unlink()
            target = root / "target"
            target.write_bytes(content)
            os.symlink(target, ds_store)
            linked = self.invoke_helper(
                "release_python", "ds-store-check", ds_store, digest
            )
            self.assertNotEqual(0, linked.returncode)

        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        production = source.split(
            'source_payload="$RELEASE_WORK_ROOT/source-payload"', 1
        )[1].split('dmg_hash="', 1)[0]
        readonly = production.split(
            'readonly_mount="$RELEASE_WORK_ROOT/readonly-mount"', 1
        )[1]
        readonly_attach = readonly.split(
            "if /usr/bin/hdiutil attach \\", 1
        )[1].split("; then", 1)[0]
        self.assertIn("-readonly", readonly_attach)
        self.assertIn("-nobrowse", readonly_attach)
        self.assertIn('-mountpoint "$readonly_mount"', readonly_attach)
        self.assertIn('"$temp_dmg"', readonly_attach)
        markers = (
            "release_prepare_mountpoint",
            "/usr/bin/hdiutil attach \\",
            'verify_exact_payload_root "$readonly_mount"',
            'mounted_ds_store_hash="$(/usr/bin/shasum -a 256',
            "release_read_finder_layout \\",
            "release_validate_finder_readback \\",
            "release_close_finder_window \\",
            "release_detach_attached_image readonly-image",
        )
        positions = [readonly.index(marker) for marker in markers]
        self.assertEqual(sorted(positions), positions)
        self.assertEqual(
            1, readonly.count("release_detach_attached_image readonly-image")
        )
        self.assertNotIn(
            'release_python ds-store-check "$readonly_mount/.DS_Store"', readonly
        )
        self.assertIn("CROSS_UNMOUNT_BYTE_IDENTITY_REQUIRED=no", readonly)
        self.assertIn("FINAL_PRESENTATION_VERIFICATION=finder-semantic-readback", readonly)
        self.assertLess(
            production.index('/usr/bin/hdiutil verify "$temp_dmg"'),
            production.index(
                'readonly_mount="$RELEASE_WORK_ROOT/readonly-mount"'
            ),
        )
        for required in (
            '"$readback_view"',
            '"$readback_icon_size"',
            '"$readback_arrangement"',
            '"$readback_toolbar"',
            '"$readback_statusbar"',
            '"$readback_pathbar"',
            '"$readback_item_information"',
            '"$readback_icon_preview"',
            '"$readback_width"',
            '"$readback_height"',
        ):
            self.assertIn(required, readonly)
        self.assertIn("FINAL_READONLY_FINDER_READBACK=pass", readonly)
        self.assertIn("DS_STORE_SEMANTICS_PRESERVED=yes", readonly)
        self.assertNotIn("-force", readonly)

    def test_dmg_payload_has_four_visible_entries_plus_excluded_hidden_ds_store(self):
        commit = "b" * 40
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "staging"
            root.mkdir()
            self.create_staging_payload(root)
            readme_bytes = (root / "README.txt").read_bytes()
            ds_store = root / ".DS_Store"
            ds_store.write_bytes(b"nonempty-finder-presentation")
            manifest = root / "RELEASE-MANIFEST.json"
            generated = self.invoke_helper(
                "generate_release_manifest",
                root,
                manifest,
                commit,
                "local.sergey.HHVacancySber",
                "1.0",
                "1",
            )
            self.assertEqual(0, generated.returncode, generated.stderr)
            verified = self.invoke_helper(
                "verify_release_manifest",
                root,
                manifest,
                commit,
                "local.sergey.HHVacancySber",
                "1.0",
                "1",
            )
            self.assertEqual(0, verified.returncode, verified.stderr)
            entries = sorted(path.name for path in root.iterdir())
            self.assertEqual(5, len(entries))
            self.assertEqual(4, len([name for name in entries if not name.startswith(".")]))
            self.assertEqual([".DS_Store"], [
                name for name in entries if name.startswith(".")
            ])
            self.assertTrue(ds_store.is_file())
            self.assertFalse(ds_store.is_symlink())
            self.assertGreater(ds_store.stat().st_size, 0)
            self.assertEqual("/Applications", os.readlink(root / "Applications"))
            self.assertEqual(readme_bytes, (root / "README.txt").read_bytes())
            parsed = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(1, parsed["schema_version"])
            self.assertEqual(
                "excluded_from_logical_payload_hashes",
                parsed["excluded_presentation_metadata"][".DS_Store"],
            )
            self.assertNotIn(
                ".DS_Store",
                [record["path"] for record in parsed["payload"]],
            )
            self.assertEqual(
                set(entries),
                {
                    ".DS_Store",
                    "Applications",
                    "СберВакансии.app",
                    "README.txt",
                    "RELEASE-MANIFEST.json",
                },
            )

    def test_source_snapshot_ignores_mtime_only_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repository"
            directory = root / "nested directory"
            directory.mkdir(parents=True)
            source = directory / "source file"
            source.write_bytes(b"semantic bytes\n")
            os.symlink("source file", directory / "source link")

            baseline = self.invoke_helper(
                "release_python", "repository-snapshot", root
            )
            self.assertEqual(0, baseline.returncode, baseline.stderr)

            source_stat = source.stat()
            directory_stat = directory.stat()
            os.utime(source, ns=(
                source_stat.st_atime_ns,
                source_stat.st_mtime_ns + 1_000_000_000,
            ))
            os.utime(directory, ns=(
                directory_stat.st_atime_ns,
                directory_stat.st_mtime_ns + 1_000_000_000,
            ))

            current = self.invoke_helper(
                "release_python", "repository-snapshot", root
            )
            self.assertEqual(0, current.returncode, current.stderr)
            self.assertEqual(baseline.stdout, current.stdout)

            baseline_path = root / "baseline.json"
            current_path = root / "current.json"
            baseline_path.write_text(baseline.stdout, encoding="utf-8")
            current_path.write_text(current.stdout, encoding="utf-8")
            comparison = self.invoke_helper(
                "release_python",
                "repository-snapshot-check",
                baseline_path,
                current_path,
                "mtime-only",
            )
            self.assertEqual(0, comparison.returncode, comparison.stderr)
            self.assertEqual("", comparison.stderr)

    def test_source_snapshot_detects_same_size_content_change_with_restored_mtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            source = root / "same-size.txt"
            original = b"first-content\n"
            replacement = b"other-content\n"
            self.assertEqual(len(original), len(replacement))
            source.write_bytes(original)
            original_stat = source.stat()

            baseline = self.invoke_helper(
                "release_python", "repository-snapshot", root
            )
            self.assertEqual(0, baseline.returncode, baseline.stderr)
            source.write_bytes(replacement)
            os.utime(source, ns=(
                original_stat.st_atime_ns,
                original_stat.st_mtime_ns,
            ))
            self.assertEqual(len(original), source.stat().st_size)
            self.assertEqual(original_stat.st_mtime_ns, source.stat().st_mtime_ns)

            current = self.invoke_helper(
                "release_python", "repository-snapshot", root
            )
            self.assertEqual(0, current.returncode, current.stderr)
            self.assertNotEqual(baseline.stdout, current.stdout)

            baseline_path = root / "baseline.json"
            current_path = root / "current.json"
            baseline_path.write_text(baseline.stdout, encoding="utf-8")
            current_path.write_text(current.stdout, encoding="utf-8")
            comparison = self.invoke_helper(
                "release_python",
                "repository-snapshot-check",
                baseline_path,
                current_path,
                "same-size-content",
            )
            self.assertNotEqual(0, comparison.returncode)
            self.assertIn("path=same-size.txt", comparison.stderr)
            self.assertIn("fields=sha256", comparison.stderr)
            self.assertNotIn("mtime", comparison.stderr)

    def test_source_snapshot_detects_ignored_path_addition_and_symlink_target_change(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            git_directory = root / ".git"
            git_directory.mkdir()
            (git_directory / "private-state").write_bytes(b"excluded\n")
            (root / ".gitignore").write_text("ignored/\n", encoding="utf-8")
            ignored = root / "ignored"
            ignored.mkdir()
            removed = ignored / "removed.txt"
            removed.write_bytes(b"remove me\n")
            mode_file = root / "mode.txt"
            mode_file.write_bytes(b"mode bytes\n")
            mode_file.chmod(0o644)
            link = root / "current-link"
            os.symlink("first-target", link)

            baseline = self.invoke_helper(
                "release_python", "repository-snapshot", root
            )
            self.assertEqual(0, baseline.returncode, baseline.stderr)
            baseline_records = json.loads(baseline.stdout)
            baseline_paths = [record["path"] for record in baseline_records]
            self.assertFalse(any(
                path == ".git" or path.startswith(".git/")
                for path in baseline_paths
            ))

            removed.unlink()
            (ignored / "added.txt").write_bytes(b"ignored addition\n")
            mode_file.chmod(0o755)
            link.unlink()
            os.symlink("second-target", link)

            current = self.invoke_helper(
                "release_python", "repository-snapshot", root
            )
            self.assertEqual(0, current.returncode, current.stderr)
            baseline_path = root / "baseline.json"
            current_path = root / "current.json"
            baseline_path.write_text(baseline.stdout, encoding="utf-8")
            current_path.write_text(current.stdout, encoding="utf-8")
            comparison = self.invoke_helper(
                "release_python",
                "repository-snapshot-check",
                baseline_path,
                current_path,
                "ignored-and-symlink",
            )
            self.assertNotEqual(0, comparison.returncode)
            self.assertIn(
                "SOURCE_SNAPSHOT_CHANGE=added path=ignored/added.txt",
                comparison.stderr,
            )
            self.assertIn(
                "SOURCE_SNAPSHOT_CHANGE=removed path=ignored/removed.txt",
                comparison.stderr,
            )
            self.assertIn(
                "SOURCE_SNAPSHOT_CHANGE=modified path=current-link fields=target",
                comparison.stderr,
            )
            self.assertIn(
                "SOURCE_SNAPSHOT_CHANGE=modified path=mode.txt fields=mode",
                comparison.stderr,
            )
            self.assertNotIn(".git/private-state", comparison.stderr)

    def test_source_snapshot_diagnostic_reports_checkpoint_path_and_fields_before_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            source = root / "diagnostic.txt"
            original = b"original-secret\n"
            replacement = b"modified-secret\n"
            self.assertEqual(len(original), len(replacement))
            source.write_bytes(original)
            baseline = self.invoke_helper(
                "release_python", "repository-snapshot", root
            )
            self.assertEqual(0, baseline.returncode, baseline.stderr)
            source.write_bytes(replacement)
            current = self.invoke_helper(
                "release_python", "repository-snapshot", root
            )
            self.assertEqual(0, current.returncode, current.stderr)

            baseline_path = root / "baseline.json"
            current_path = root / "current.json"
            baseline_path.write_text(baseline.stdout, encoding="utf-8")
            current_path.write_text(current.stdout, encoding="utf-8")
            comparison = self.invoke_helper(
                "release_python",
                "repository-snapshot-check",
                baseline_path,
                current_path,
                "after-controlled-change",
            )
            captured = comparison.stderr
            self.assertNotEqual(0, comparison.returncode)
            self.assertEqual(
                "Release gate failed: source repository content changed during release packaging",
                captured.splitlines()[0],
            )
            self.assertIn(
                "SOURCE_SNAPSHOT_CHECKPOINT=after-controlled-change", captured
            )
            self.assertIn("path=diagnostic.txt", captured)
            self.assertIn("fields=sha256", captured)
            self.assertNotIn(str(root), captured)
            self.assertNotIn(original.decode("utf-8").strip(), captured)
            self.assertNotIn(replacement.decode("utf-8").strip(), captured)
            self.assertNotIn(
                hashlib.sha256(original).hexdigest(), captured
            )
            self.assertNotIn(
                hashlib.sha256(replacement).hexdigest(), captured
            )

            baseline_path.unlink()
            current_path.unlink()
            self.assertFalse(baseline_path.exists())
            self.assertFalse(current_path.exists())
            self.assertIn("path=diagnostic.txt", captured)

    def test_build_source_is_materialized_from_committed_head_outside_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository, work_root, commit = self.create_isolation_fixture(
                temporary
            )
            status_before = subprocess.run(
                [
                    "/usr/bin/git", "-C", str(repository), "status",
                    "--porcelain=v1", "--untracked-files=all",
                ],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            ).stdout
            snapshot_before = self.invoke_helper(
                "release_python", "repository-snapshot", repository
            )
            self.assertEqual(0, snapshot_before.returncode, snapshot_before.stderr)

            completed, build_source = self.materialize_isolation_fixture(
                repository, work_root, commit
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual(build_source.resolve(), Path(
                completed.stdout.strip().split("=", 1)[1]
            ).resolve())
            self.assertNotEqual(repository.resolve(), build_source.resolve())
            self.assertTrue(build_source.is_relative_to(work_root))
            self.assertTrue(
                (build_source / "HHVacancySber" / "HHVacancySber.xcodeproj"
                 / "project.pbxproj").is_file()
            )
            self.assertTrue(
                (build_source / "scripts" / "verify_release_entitlements.py")
                .is_file()
            )
            executable = build_source / "tools" / "committed-tool"
            self.assertEqual(0o755, stat.S_IMODE(executable.stat().st_mode))
            self.assertEqual(
                "tools/committed-tool",
                os.readlink(build_source / "tracked-link"),
            )
            self.assertFalse((build_source / "untracked.txt").exists())
            self.assertFalse((build_source / "ignored").exists())
            self.assertEqual([], list(build_source.rglob(".git")))
            evidence = (work_root / "logs" / "build-source-materialization.txt")
            self.assertIn(
                "SOURCE_COMMIT=" + commit, evidence.read_text(encoding="utf-8")
            )

            status_after = subprocess.run(
                [
                    "/usr/bin/git", "-C", str(repository), "status",
                    "--porcelain=v1", "--untracked-files=all",
                ],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            ).stdout
            snapshot_after = self.invoke_helper(
                "release_python", "repository-snapshot", repository
            )
            self.assertEqual(status_before, status_after)
            self.assertEqual(snapshot_before.stdout, snapshot_after.stdout)

    def test_xcode_commands_use_isolated_build_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository, work_root, commit = self.create_isolation_fixture(
                temporary
            )
            completed, build_source = self.materialize_isolation_fixture(
                repository, work_root, commit
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            capture = Path(temporary) / "xcode-calls.txt"
            command = textwrap.dedent(
                """\
                source "$1"
                BUILD_SOURCE_ROOT="$2"
                RELEASE_WORK_ROOT="$3"
                RELEASE_XCODE_CAPTURE="$4"
                release_xcodebuild() {
                  {
                    printf 'CALL\n'
                    printf 'PWD=%s\n' "$PWD"
                    for argument in "$@"; do
                      printf 'ARG=%s\n' "$argument"
                    done
                  } >> "$RELEASE_XCODE_CAPTURE"
                }
                release_run_show_build_settings
                release_run_strict_release_build
                """
            )
            invocation = subprocess.run(
                [
                    "/bin/bash", "-c", command, "release-xcode-test",
                    str(RELEASE_SCRIPT), str(build_source), str(work_root),
                    str(capture),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(0, invocation.returncode, invocation.stderr)
            calls = [
                block.splitlines()
                for block in capture.read_text(encoding="utf-8").split("CALL\n")
                if block
            ]
            self.assertEqual(2, len(calls))
            for call in calls:
                working_directory = Path(call[0].split("=", 1)[1])
                arguments = [line.split("=", 1)[1] for line in call[1:]]
                self.assertEqual(build_source.resolve(), working_directory.resolve())
                project_index = arguments.index("-project") + 1
                project = (working_directory / arguments[project_index]).resolve()
                self.assertTrue(project.is_relative_to(build_source.resolve()))
                derived_index = arguments.index("-derivedDataPath") + 1
                derived = Path(arguments[derived_index]).resolve()
                self.assertTrue(derived.is_relative_to(work_root.resolve()))
                self.assertNotIn(str(repository), "\n".join(arguments))
                self.assertIn("-disableAutomaticPackageResolution", arguments)
                for forbidden in (
                    "ARCHS=", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM=",
                    "ENABLE_APP_SANDBOX=", "ENABLE_HARDENED_RUNTIME=",
                ):
                    self.assertFalse(any(
                        argument.startswith(forbidden) for argument in arguments
                    ))
            self.assertIn("-showBuildSettings", [
                line.split("=", 1)[1] for line in calls[0][1:]
            ])
            self.assertEqual("build", calls[1][-1].split("=", 1)[1])

    def test_xcode_swiftpm_side_effects_do_not_mutate_authoritative_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository, work_root, commit = self.create_isolation_fixture(
                temporary
            )
            baseline = self.invoke_helper(
                "release_python", "repository-snapshot", repository
            )
            self.assertEqual(0, baseline.returncode, baseline.stderr)
            completed, build_source = self.materialize_isolation_fixture(
                repository, work_root, commit
            )
            self.assertEqual(0, completed.returncode, completed.stderr)

            command = textwrap.dedent(
                """\
                source "$1"
                BUILD_SOURCE_ROOT="$2"
                RELEASE_WORK_ROOT="$3"
                release_xcodebuild() {
                  /bin/mkdir -p "$PWD/HHVacancySber/HHVacancySber.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration"
                }
                release_run_show_build_settings
                """
            )
            invocation = subprocess.run(
                [
                    "/bin/bash", "-c", command, "release-swiftpm-test",
                    str(RELEASE_SCRIPT), str(build_source), str(work_root),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(0, invocation.returncode, invocation.stderr)
            relative = Path(
                "HHVacancySber/HHVacancySber.xcodeproj/project.xcworkspace/"
                "xcshareddata/swiftpm/configuration"
            )
            self.assertTrue((build_source / relative).is_dir())
            self.assertFalse((repository / relative).exists())

            current = self.invoke_helper(
                "release_python", "repository-snapshot", repository
            )
            self.assertEqual(baseline.stdout, current.stdout)
            baseline_path = Path(temporary) / "baseline.json"
            current_path = Path(temporary) / "current.json"
            baseline_path.write_text(baseline.stdout, encoding="utf-8")
            current_path.write_text(current.stdout, encoding="utf-8")
            comparison = self.invoke_helper(
                "release_python", "repository-snapshot-check",
                baseline_path, current_path, "isolated-xcode",
            )
            self.assertEqual(0, comparison.returncode, comparison.stderr)

            (repository / relative).mkdir(parents=True)
            negative = self.invoke_helper(
                "release_python", "repository-snapshot", repository
            )
            negative_path = Path(temporary) / "negative.json"
            negative_path.write_text(negative.stdout, encoding="utf-8")
            negative_comparison = self.invoke_helper(
                "release_python", "repository-snapshot-check",
                baseline_path, negative_path, "authoritative-negative-control",
            )
            self.assertNotEqual(0, negative_comparison.returncode)
            self.assertIn(relative.as_posix(), negative_comparison.stderr)

    def test_read_only_disk_info_accepts_explicit_read_only_volume_schema(self):
        cases = (
            {"ReadOnlyVolume": True},
            {
                "ReadOnlyVolume": True,
                "Writable": False,
                "WritableVolume": False,
                "WritableMedia": False,
            },
            {"ReadOnlyVolume": True, "WritableVolume": False},
        )
        with tempfile.TemporaryDirectory() as temporary:
            for evidence in cases:
                with self.subTest(evidence=evidence):
                    completed = self.invoke_disk_info(temporary, evidence)
                    self.assertEqual(0, completed.returncode, completed.stderr)
                    self.assertEqual(
                        "DMG_READ_ONLY_SCHEMA=explicit-read-only\n",
                        completed.stdout,
                    )

    def test_read_only_disk_info_accepts_macos13_all_writable_flags_false(self):
        evidence = {
            "Writable": False,
            "WritableVolume": False,
            "WritableMedia": False,
        }
        with tempfile.TemporaryDirectory() as temporary:
            completed = self.invoke_disk_info(temporary, evidence)
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual(
                "DMG_READ_ONLY_SCHEMA=macos13-writable-flags\n",
                completed.stdout,
            )

    def test_read_only_disk_info_rejects_writable_or_contradictory_evidence(self):
        cases = (
            {"Writable": True},
            {"WritableVolume": True},
            {"WritableMedia": True},
            {"ReadOnlyVolume": False},
            {"ReadOnlyVolume": True, "Writable": True},
            {"ReadOnlyVolume": True, "WritableVolume": True},
            {"ReadOnlyVolume": True, "WritableMedia": True},
        )
        with tempfile.TemporaryDirectory() as temporary:
            for evidence in cases:
                with self.subTest(evidence=evidence):
                    completed = self.invoke_disk_info(temporary, evidence)
                    self.assertNotEqual(0, completed.returncode)
                    self.assertIn(
                        "Release gate failed: DMG is not mounted read-only",
                        completed.stderr,
                    )
                    for field in (
                        "DMG_READ_ONLY_SCHEMA", "DMG_READ_ONLY_VOLUME",
                        "DMG_WRITABLE", "DMG_WRITABLE_VOLUME",
                        "DMG_WRITABLE_MEDIA",
                    ):
                        self.assertIn(field + "=", completed.stderr)
                    self.assertNotIn("<plist", completed.stderr)
                    self.assertNotIn("Traceback", completed.stderr)

    def test_read_only_disk_info_rejects_partial_non_boolean_or_unparseable_evidence(self):
        cases = (
            {"Writable": False},
            {"WritableVolume": False},
            {"Writable": False, "WritableVolume": False},
            {},
            {"ReadOnlyVolume": "true"},
            {"Writable": 0},
            {"WritableVolume": "false"},
            {"WritableMedia": []},
        )
        with tempfile.TemporaryDirectory() as temporary:
            for evidence in cases:
                with self.subTest(evidence=evidence):
                    completed = self.invoke_disk_info(temporary, evidence)
                    self.assertNotEqual(0, completed.returncode)
                    self.assertIn(
                        "DMG_READ_ONLY_SCHEMA=invalid", completed.stderr
                    )
                    self.assertNotIn("<plist", completed.stderr)
                    self.assertNotIn("Traceback", completed.stderr)
            malformed = self.invoke_disk_info(
                temporary, raw=b"not a plist\nsecret fixture bytes"
            )
            self.assertNotEqual(0, malformed.returncode)
            self.assertIn("DMG_READ_ONLY_SCHEMA=invalid", malformed.stderr)
            self.assertNotIn("secret fixture bytes", malformed.stderr)
            self.assertNotIn("Traceback", malformed.stderr)

    def test_no_clobber_publication_rejects_existing_destination_and_rolls_back_owned_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sources = [root / ("temporary-%d" % index) for index in range(3)]
            destinations = [root / ("final-%d" % index) for index in range(3)]
            for index, source in enumerate(sources):
                source.write_text("source-%d" % index, encoding="utf-8")

            destinations[1].write_text("pre-existing", encoding="utf-8")
            preexisting_identity = (
                destinations[1].stat().st_dev,
                destinations[1].stat().st_ino,
            )
            completed = self.invoke_helper(
                "publish_no_clobber",
                sources[0], destinations[0],
                sources[1], destinations[1],
                sources[2], destinations[2],
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertFalse(destinations[0].exists())
            self.assertEqual(
                "pre-existing", destinations[1].read_text(encoding="utf-8")
            )
            self.assertEqual(
                preexisting_identity,
                (destinations[1].stat().st_dev, destinations[1].stat().st_ino),
            )
            self.assertTrue(all(source.exists() for source in sources))
            self.assertFalse(destinations[2].exists())
            destinations[1].unlink()

            directory_destination = root / "directory-destination"
            directory_destination.mkdir()
            completed = self.invoke_helper(
                "release_link_exclusive", sources[0], directory_destination
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertEqual([], list(directory_destination.iterdir()))

            command = textwrap.dedent(
                """\
                source "$1"
                release_link_calls=0
                release_link_exclusive() {
                  release_link_calls=$((release_link_calls + 1))
                  if [[ "$release_link_calls" -eq 2 ]]; then
                    printf 'raced-destination' > "$2"
                    return 1
                  fi
                  /bin/ln "$1" "$2"
                }
                publish_no_clobber "$2" "$3" "$4" "$5" "$6" "$7"
                """
            )
            completed = subprocess.run(
                [
                    "/bin/bash",
                    "-c",
                    command,
                    "release-race-test",
                    str(RELEASE_SCRIPT),
                    str(sources[0]), str(destinations[0]),
                    str(sources[1]), str(destinations[1]),
                    str(sources[2]), str(destinations[2]),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertFalse(destinations[0].exists())
            self.assertEqual(
                "raced-destination",
                destinations[1].read_text(encoding="utf-8"),
            )
            self.assertFalse(destinations[2].exists())
            self.assertTrue(all(source.exists() for source in sources))

    def test_release_script_contains_no_reachable_recursive_cleanup_primitive(self):
        source = RELEASE_SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("safe_remove_owned_tree", source)
        self.assertNotIn("shutil.rmtree", source)
        self.assertNotIn("FileManager", source)
        self.assertNotRegex(source, r"(?m)\bfind\b[^\n]*\s-delete(?:\s|$)")
        self.assertNotRegex(source, r"(?m)\bxargs\b[^\n]*\brm\b")
        for logical_line in source.replace("\\\n", " ").splitlines():
            stripped = logical_line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            try:
                import shlex
                tokens = shlex.split(stripped, comments=True, posix=True)
            except ValueError:
                continue
            for index, token in enumerate(tokens):
                if Path(token).name != "rm":
                    continue
                for argument in tokens[index + 1:]:
                    if argument == "--":
                        continue
                    self.assertNotEqual("--recursive", argument)
                    if argument.startswith("-") and not argument.startswith("--"):
                        self.assertNotIn("r", argument[1:].lower())
        recursive_flag_assignments = dict(
            (name, value) for name, value in
            __import__("re").findall(
                r"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)=(?:['\"])?(-[^'\"\s]*[rR][^'\"\s]*)(?:['\"])?\s*$",
                source,
            )
        )
        for variable in recursive_flag_assignments:
            self.assertNotRegex(source, r"\brm\b[^\n]*\$\{?" + variable + r"\}?")

    def test_work_root_is_same_filesystem_sibling_outside_output_and_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            repository = root / "repository"
            output = root / "publication"
            repository.mkdir()
            output.mkdir()
            completed = self.invoke_helper(
                "release_create_work_root", repository, output
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            work_root = Path(completed.stdout.strip()).resolve()
            self.assertTrue(work_root.is_dir())
            self.assertFalse(work_root.is_symlink())
            self.assertEqual(output.resolve().parent, work_root.parent)
            self.assertFalse(work_root.is_relative_to(output.resolve()))
            self.assertFalse(output.resolve().is_relative_to(work_root))
            self.assertFalse(work_root.is_relative_to(repository.resolve()))
            self.assertFalse(repository.resolve().is_relative_to(work_root))
            self.assertEqual(output.stat().st_dev, work_root.stat().st_dev)
            self.assertNotIn(work_root.name, [item.name for item in output.iterdir()])

    def test_success_retains_nonempty_work_tree_and_reports_manual_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            output = root / "output"
            work_root = root / ".hhvacancysber-release.success"
            output.mkdir()
            (work_root / "source").mkdir(parents=True)
            (work_root / "DerivedData").mkdir()
            (work_root / "source-payload").mkdir()
            (work_root / "logs").mkdir()
            sentinels = []
            for directory in ("source", "DerivedData", "source-payload", "logs"):
                sentinel = work_root / directory / "sentinel"
                sentinel.write_text(directory, encoding="utf-8")
                sentinels.append(sentinel)
            for name in ("release.dmg", "release.dmg.sha256", "release.dmg.manifest.json"):
                (output / name).write_text(name, encoding="utf-8")
            completed = subprocess.run(
                [
                    "/bin/bash", "-c",
                    'source "$1"; RELEASE_WORK_ROOT="$2"; '
                    'RELEASE_RETENTION_REPORTED=0; release_report_retained_work',
                    "retention-success", str(RELEASE_SCRIPT), str(work_root),
                ],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertTrue(all(path.is_file() for path in sentinels))
            self.assertIn(
                "SAFE AUTOMATIC CLEANUP NOT IMPLEMENTED — MACOS 13 PRIMITIVES INSUFFICIENT",
                completed.stdout,
            )
            self.assertIn("MANUAL_CLEANUP_REQUIRED=yes", completed.stdout)
            self.assertIn("RETAINED_WORK_ROOT=" + str(work_root), completed.stdout)
            self.assertIn(
                "RETAINED_WORK_ROOT_CONTAINS=source,DerivedData,source-payload,audit-logs",
                completed.stdout,
            )
            self.assertEqual(3, len(list(output.iterdir())))
            self.assertTrue(all(path.is_file() for path in output.iterdir()))

    def test_failure_retains_nonempty_work_tree_and_preserves_primary_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            work_root = root / ".hhvacancysber-release.failure"
            lock = root / "output" / ".hhvacancysber-release.lock"
            (work_root / "logs").mkdir(parents=True)
            lock.mkdir(parents=True)
            sentinel = work_root / "logs" / "primary-failure"
            sentinel.write_text("retain", encoding="utf-8")
            command = textwrap.dedent(
                """\\
                source "$1"
                RELEASE_WORK_ROOT="$2"
                RELEASE_WORK_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$2")"
                RELEASE_RETENTION_REPORTED=0
                RELEASE_CLEANUP_ATTEMPTED=0
                RELEASE_CLEANUP_RESULT=1
                RELEASE_ATTACH_SUCCEEDED=0
                RELEASE_PUBLICATION_PENDING=0
                RELEASE_LOCK_ACQUIRED=1
                RELEASE_LOCK_DIR="$3"
                RELEASE_ALLOW_LOCK_RELEASE=0
                release_exit_trap 23
                """
            )
            completed = subprocess.run(
                ["/bin/bash", "-c", command, "retention-failure",
                 str(RELEASE_SCRIPT), str(work_root), str(lock)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(23, completed.returncode)
            self.assertEqual("retain", sentinel.read_text(encoding="utf-8"))
            self.assertTrue(lock.is_dir())
            self.assertIn("MANUAL_CLEANUP_REQUIRED=yes", completed.stdout)
            self.assertIn("lock retained", completed.stderr)
            self.assertNotRegex(completed.stdout + completed.stderr, r"\brm\s+-[^\n]*[rR]")

    def test_exact_empty_mountpoint_cleanup_uses_rmdir_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            work = root / "work"
            work.mkdir()

            def invoke(path, identity):
                return self.invoke_owned_helper(
                    work,
                    "release_remove_empty_mountpoint", path, identity, work
                )

            empty = work / "empty"
            empty.mkdir()
            identity = "%d:%d" % (empty.stat().st_dev, empty.stat().st_ino)
            completed = invoke(empty, identity)
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertFalse(empty.exists())

            nonempty = work / "nonempty"
            nonempty.mkdir()
            sentinel = nonempty / "sentinel"
            sentinel.write_text("retain", encoding="utf-8")
            identity = "%d:%d" % (nonempty.stat().st_dev, nonempty.stat().st_ino)
            completed = invoke(nonempty, identity)
            self.assertNotEqual(0, completed.returncode)
            self.assertEqual("retain", sentinel.read_text(encoding="utf-8"))

            replaced = work / "replaced"
            replaced.mkdir()
            old_identity = "%d:%d" % (replaced.stat().st_dev, replaced.stat().st_ino)
            replacement = work / "replacement-source"
            replacement.mkdir()
            replaced.rmdir()
            replacement.rename(replaced)
            completed = invoke(replaced, old_identity)
            self.assertNotEqual(0, completed.returncode)
            self.assertTrue(replaced.is_dir())

            target = work / "target"
            target.mkdir()
            alias = work / "alias"
            os.symlink(target, alias)
            identity = "%d:%d" % (target.stat().st_dev, target.stat().st_ino)
            completed = invoke(alias, identity)
            self.assertNotEqual(0, completed.returncode)
            self.assertTrue(alias.is_symlink())

    def test_lock_owner_identity_is_recorded_at_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            lock = (Path(temporary) / "lock").resolve()
            command = textwrap.dedent(
                """\\
                source "$1"
                RELEASE_LOCK_DIR="$2"
                /bin/mkdir -m 700 "$RELEASE_LOCK_DIR"
                RELEASE_LOCK_ACQUIRED=1
                RELEASE_LOCK_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$RELEASE_LOCK_DIR")"
                release_create_lock_owner 0123456789012345678901234567890123456789
                printf 'PARENT=%s\\nNAME=%s\\nIDENTITY=%s\\nLINKS=%s\\nNONCE=%s\\nSHA=%s\\nLOCK=%s\\n' \
                  "$RELEASE_LOCK_OWNER_PARENT" "$RELEASE_LOCK_OWNER_NAME" \
                  "$RELEASE_LOCK_OWNER_IDENTITY" "$RELEASE_LOCK_OWNER_LINK_COUNT" \
                  "$RELEASE_LOCK_OWNER_NONCE" "$RELEASE_LOCK_OWNER_SHA256" \
                  "$RELEASE_LOCK_IDENTITY"
                """
            )
            completed = subprocess.run(
                ["/bin/bash", "-c", command, "lock-create", str(RELEASE_SCRIPT), str(lock)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            owner = lock / "owner"
            self.assertTrue(owner.is_file())
            self.assertFalse(owner.is_symlink())
            self.assertIn("PARENT=" + str(lock), completed.stdout)
            self.assertIn("NAME=owner", completed.stdout)
            self.assertRegex(completed.stdout, r"IDENTITY=\d+:\d+")
            self.assertIn("LINKS=1", completed.stdout)
            self.assertRegex(completed.stdout, r"NONCE=[0-9A-F-]+")
            self.assertRegex(completed.stdout, r"SHA=[0-9a-f]{64}")
            self.assertRegex(completed.stdout, r"LOCK=\d+:\d+")

    def test_lock_owner_unlink_requires_matching_regular_file_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()

            def run_case(name, mutation):
                lock = root / name
                command = textwrap.dedent(
                    """\\
                    source "$1"
                    RELEASE_LOCK_DIR="$2"
                    /bin/mkdir -m 700 "$RELEASE_LOCK_DIR"
                    RELEASE_LOCK_ACQUIRED=1
                    RELEASE_LOCK_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$RELEASE_LOCK_DIR")"
                    release_create_lock_owner 0123456789012345678901234567890123456789
                    RELEASE_ALLOW_LOCK_RELEASE=1
                    eval "$3"
                    release_release_lock_owner
                    """
                )
                return lock, subprocess.run(
                    ["/bin/bash", "-c", command, "lock-release",
                     str(RELEASE_SCRIPT), str(lock), mutation],
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    check=False,
                )

            lock, completed = run_case("exact", ":")
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertFalse(lock.exists())

            cases = {
                "wrong-identity": "RELEASE_LOCK_OWNER_IDENTITY=0:0",
                "wrong-type": "/bin/rm -f -- \"$RELEASE_LOCK_DIR/owner\"; /bin/mkdir \"$RELEASE_LOCK_DIR/owner\"",
                "symlink": "/bin/rm -f -- \"$RELEASE_LOCK_DIR/owner\"; /bin/ln -s target \"$RELEASE_LOCK_DIR/owner\"",
                "link-count": "/bin/ln \"$RELEASE_LOCK_DIR/owner\" \"$RELEASE_LOCK_DIR/second-link\"",
                "wrong-content": "printf changed > \"$RELEASE_LOCK_DIR/owner\"",
            }
            for name, mutation in cases.items():
                with self.subTest(case=name):
                    lock, completed = run_case(name, mutation)
                    self.assertNotEqual(0, completed.returncode)
                    self.assertTrue(lock.is_dir())
                    self.assertIn("retained", completed.stderr)

    def test_replaced_lock_owner_is_retained_and_reported(self):
        with tempfile.TemporaryDirectory() as temporary:
            lock = (Path(temporary) / "lock").resolve()
            command = textwrap.dedent(
                """\\
                source "$1"
                RELEASE_LOCK_DIR="$2"
                /bin/mkdir -m 700 "$RELEASE_LOCK_DIR"
                RELEASE_LOCK_ACQUIRED=1
                RELEASE_LOCK_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$RELEASE_LOCK_DIR")"
                release_create_lock_owner 0123456789012345678901234567890123456789
                /bin/rm -f -- "$RELEASE_LOCK_DIR/owner"
                printf replacement > "$RELEASE_LOCK_DIR/owner"
                RELEASE_ALLOW_LOCK_RELEASE=1
                release_release_lock_owner
                """
            )
            completed = subprocess.run(
                ["/bin/bash", "-c", command, "lock-replace", str(RELEASE_SCRIPT), str(lock)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(0, completed.returncode)
            self.assertEqual("replacement", (lock / "owner").read_text(encoding="utf-8"))
            self.assertTrue(lock.is_dir())
            self.assertIn("authentication failed", completed.stderr)
            self.assertIn("retained", completed.stderr)
            self.assertNotRegex(completed.stderr, r"\brm\s+-[^\n]*[rR]")

    def test_stale_lock_is_never_deleted_automatically(self):
        with tempfile.TemporaryDirectory() as temporary:
            lock = (Path(temporary) / "output" / ".hhvacancysber-release.lock").resolve()
            lock.mkdir(parents=True)
            owner = lock / "owner"
            original = b"stale-owner-evidence\n"
            owner.write_bytes(original)
            identity = (owner.stat().st_dev, owner.stat().st_ino)
            completed = self.invoke_helper("release_acquire_lock", lock)
            self.assertNotEqual(0, completed.returncode)
            self.assertEqual(original, owner.read_bytes())
            self.assertEqual(identity, (owner.stat().st_dev, owner.stat().st_ino))
            self.assertTrue(lock.is_dir())
            self.assertIn("manual inspection required", completed.stderr)
            self.assertIn(str(lock), completed.stderr)


if __name__ == "__main__":
    unittest.main()
