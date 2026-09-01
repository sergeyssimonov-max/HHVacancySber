import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest import mock


import scripts.verify_release_entitlements as verifier


class ReleaseEntitlementVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.app = Path(self.temporary.name) / "СберВакансии.app"
        self.main = self.app / "Contents" / "MacOS" / "СберВакансии"
        self.main.parent.mkdir(parents=True)
        self.main.write_bytes(b"main")
        self.expected = {
            verifier.APP_SANDBOX: True,
            "com.apple.security.files.user-selected.read-write": True,
            "com.apple.security.network.client": True,
        }

    def tearDown(self):
        self.temporary.cleanup()

    def completed(self, returncode=0, stdout=b"", stderr=b""):
        return subprocess.CompletedProcess([], returncode, stdout, stderr)

    def command_results(self, main_entitlements=None, nested_entitlements=None, signature_valid=True):
        main_entitlements = self.expected if main_entitlements is None else main_entitlements
        nested_entitlements = {} if nested_entitlements is None else nested_entitlements

        def result(arguments, **_kwargs):
            if "--verify" in arguments:
                return self.completed(0 if signature_valid else 1)
            path = Path(arguments[-1])
            entitlements = (
                main_entitlements
                if verifier.same_file_identity(path, self.main)
                else nested_entitlements
            )
            return self.completed(stdout=plistlib.dumps(entitlements, fmt=plistlib.FMT_XML, sort_keys=True))

        return result

    def add_nested_macho(self):
        nested = self.app / "Contents" / "Frameworks" / "NestedTool"
        nested.parent.mkdir(parents=True)
        nested.write_bytes(b"\xcf\xfa\xed\xfe" + b"nested")
        return nested

    def invoke_main(self):
        output = io.StringIO()
        with mock.patch("sys.stdout", output):
            status = verifier.main(["--app", str(self.app)])
        return status, output.getvalue(), json.loads(output.getvalue())

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_accepts_expected_release_entitlements(self, process):
        process.side_effect = self.command_results()
        canonical_app = verifier.canonical_path(self.app)
        self.assertTrue(str(canonical_app).startswith("/private/var/"))
        alias_app = Path(str(canonical_app).replace("/private/var/", "/var/", 1))
        alias_main = alias_app / "Contents" / "MacOS" / "HHVacancySber"
        with mock.patch.object(Path, "rglob", return_value=[alias_main]):
            report = verifier.inspect_application(alias_app)
        self.assertTrue(report["success"])
        self.assertEqual(str(canonical_app), report["app"])
        self.assertEqual([], report["nested_code"])

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_rejects_get_task_allow_true(self, process):
        entitlements = dict(self.expected, **{verifier.GET_TASK_ALLOW: True})
        process.side_effect = self.command_results(entitlements)
        self.assertFalse(verifier.inspect_application(self.app)["success"])

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_rejects_get_task_allow_false_because_key_must_be_absent(self, process):
        entitlements = dict(self.expected, **{verifier.GET_TASK_ALLOW: False})
        process.side_effect = self.command_results(entitlements)
        report = verifier.inspect_application(self.app)
        self.assertEqual(verifier.GET_TASK_ALLOW, report["forbidden_entitlements_found"][0]["entitlement"])

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_requires_app_sandbox(self, process):
        entitlements = dict(self.expected)
        entitlements.pop(verifier.APP_SANDBOX)
        process.side_effect = self.command_results(entitlements)
        report = verifier.inspect_application(self.app)
        self.assertIn(verifier.APP_SANDBOX, report["required_entitlements_missing"])

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_requires_user_selected_read_write(self, process):
        entitlements = dict(self.expected)
        entitlements.pop("com.apple.security.files.user-selected.read-write")
        process.side_effect = self.command_results(entitlements)
        report = verifier.inspect_application(self.app)
        self.assertIn("com.apple.security.files.user-selected.read-write", report["required_entitlements_missing"])

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_requires_network_client(self, process):
        entitlements = dict(self.expected)
        entitlements.pop("com.apple.security.network.client")
        process.side_effect = self.command_results(entitlements)
        report = verifier.inspect_application(self.app)
        self.assertIn("com.apple.security.network.client", report["required_entitlements_missing"])

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_rejects_get_task_allow_in_nested_code(self, process):
        nested = self.add_nested_macho()
        nested_alias = nested.with_name("NestedToolHardLink")
        os.link(nested, nested_alias)
        self.assertTrue(os.path.samefile(nested, nested_alias))
        process.side_effect = self.command_results(
            nested_entitlements={verifier.GET_TASK_ALLOW: True}
        )
        with mock.patch.object(
            Path,
            "rglob",
            return_value=[nested_alias, self.main, nested],
        ):
            report = verifier.inspect_application(self.app)

        expected_path = min(
            str(verifier.canonical_path(path))
            for path in (nested, nested_alias)
        )
        nested_extractions = [
            call
            for call in process.call_args_list
            if "--entitlements" in call.args[0]
            and verifier.same_file_identity(Path(call.args[0][-1]), nested)
        ]

        self.assertEqual(1, len(nested_extractions))
        self.assertEqual(
            [{"path": expected_path, "entitlements": {verifier.GET_TASK_ALLOW: True}}],
            report["nested_code"],
        )
        self.assertEqual(
            [{"code": expected_path, "entitlement": verifier.GET_TASK_ALLOW}],
            report["forbidden_entitlements_found"],
        )
        self.assertEqual(expected_path, str(verifier.canonical_path(expected_path)))
        self.assertTrue(
            all(
                not verifier.same_file_identity(Path(item["path"]), self.main)
                for item in report["nested_code"]
            )
        )

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_reports_invalid_signature(self, process):
        process.side_effect = self.command_results(signature_valid=False)
        report = verifier.inspect_application(self.app)
        self.assertFalse(report["signature_valid"])
        self.assertIn("signature_invalid", report["errors"])

    def test_reports_missing_application(self):
        report = verifier.inspect_application(Path(self.temporary.name) / "Missing.app")
        self.assertIn("application_missing", report["errors"])

    def test_reports_missing_main_executable(self):
        self.main.unlink()
        report = verifier.inspect_application(self.app)
        self.assertIn("main_executable_missing", report["errors"])

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_json_output_is_deterministic(self, process):
        process.side_effect = self.command_results()
        first = self.invoke_main()
        process.side_effect = self.command_results()
        second = self.invoke_main()
        self.assertEqual(first[0], second[0])
        self.assertEqual(first[1], second[1])

    @mock.patch("scripts.verify_release_entitlements.subprocess.run")
    def test_does_not_emit_environment_or_token_values(self, process):
        process.side_effect = self.command_results()
        secret = "B12_SECRET_VALUE_MUST_NOT_APPEAR"
        with mock.patch.dict(os.environ, {"HH_ACCESS_TOKEN": secret}):
            _status, output, _report = self.invoke_main()
        self.assertNotIn(secret, output)
        self.assertNotIn("HH_ACCESS_TOKEN", output)


if __name__ == "__main__":
    unittest.main()
