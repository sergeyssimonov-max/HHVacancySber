import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RELEASE_SCRIPT = REPOSITORY_ROOT / "scripts" / "release.sh"
CI_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml"
STRICT_FLAGS = (
    "SWIFT_STRICT_CONCURRENCY=complete",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
    "GCC_TREAT_WARNINGS_AS_ERRORS=YES",
)


def run(script, *arguments, cwd=None, env=None):
    environment = dict(os.environ)
    environment.pop("DEVELOPER_ID", None)
    environment.pop("NOTARY_PROFILE", None)
    environment.update(env or {})
    return subprocess.run(
        ["/bin/bash", str(script), *arguments],
        cwd=cwd, env=environment, capture_output=True, text=True, check=False,
    )


class ReleaseScriptTests(unittest.TestCase):
    def test_syntax(self):
        completed = subprocess.run(["/bin/bash", "-n", str(RELEASE_SCRIPT)], capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_help_and_argument_errors(self):
        self.assertEqual(run(RELEASE_SCRIPT, "--help").returncode, 0)
        self.assertIn("--output-dir", run(RELEASE_SCRIPT, "--help").stdout)
        for arguments in ((), ("--output-dir",), ("--output-dir", ""), ("--unknown",)):
            completed = run(RELEASE_SCRIPT, *arguments)
            self.assertEqual(completed.returncode, 2, arguments)
            self.assertIn("Usage:", completed.stderr)

    def test_notarization_requires_developer_id(self):
        completed = run(RELEASE_SCRIPT, "--output-dir", "out", env={"NOTARY_PROFILE": "profile"})
        self.assertEqual(completed.returncode, 1)
        self.assertIn("NOTARY_PROFILE requires DEVELOPER_ID", completed.stderr)

    def test_dirty_tree_stops_before_building_or_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            (repository / "scripts").mkdir(parents=True)
            shutil.copy(RELEASE_SCRIPT, repository / "scripts" / "release.sh")
            git = ["git", "-C", str(repository), "-c", "user.name=Test", "-c", "user.email=test@example.invalid"]
            subprocess.run(git[:3] + ["init", "-q"], check=True)
            subprocess.run(git + ["add", "."], check=True)
            subprocess.run(git + ["commit", "-q", "-m", "initial"], check=True)
            (repository / "uncommitted.txt").write_text("change\n")
            output = Path(temporary) / "output"

            completed = run(repository / "scripts" / "release.sh", "--output-dir", str(output))

            self.assertEqual(completed.returncode, 1)
            self.assertIn("working tree is not clean", completed.stderr)
            self.assertFalse(output.exists())

    def test_release_build_uses_the_same_strict_flags_as_ci(self):
        script = RELEASE_SCRIPT.read_text(encoding="utf-8")
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")
        for flag in STRICT_FLAGS:
            self.assertIn(flag, script)
            self.assertIn(flag, workflow)

    def test_no_finder_scripting_or_leftover_work_directories(self):
        script = RELEASE_SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("osascript", script)
        self.assertIn("trap 'rm -rf \"$work\"' EXIT", script)

    def test_packaging_builds_frozen_commit_and_publishes_matching_pair(self):
        # Exercise the actual shell flow; stub only macOS packaging/build tools.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / "repository"
            scripts = repository / "scripts"
            scripts.mkdir(parents=True)
            shutil.copy(RELEASE_SCRIPT, scripts / "release.sh")
            shutil.copy(REPOSITORY_ROOT / "scripts/publish_release.py", scripts / "publish_release.py")
            (scripts / "verify_release_entitlements.py").write_text("print('{}')\n")
            (repository / "source.txt").write_text("committed")
            git = ["git", "-C", str(repository), "-c", "user.name=Test", "-c", "user.email=test@example.invalid"]
            subprocess.run(git[:3] + ["init", "-q"], check=True)
            subprocess.run(git + ["add", "."], check=True)
            subprocess.run(git + ["commit", "-q", "-m", "fixture"], check=True)
            binaries = root / "bin"
            binaries.mkdir()
            commands = {
                "xcodebuild": '''#!/usr/bin/env python3
import os, pathlib, plistlib, sys
pathlib.Path(os.environ['ORIGINAL_CHECKOUT'], 'source.txt').write_text('edited during build')
assert pathlib.Path('source.txt').read_text() == 'committed'
derived = pathlib.Path(sys.argv[sys.argv.index('-derivedDataPath') + 1])
app = derived / 'Build/Products/Release/СберВакансии.app/Contents'
app.mkdir(parents=True)
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'1.1','CFBundleVersion':'9'}))
''',
                "codesign": '#!/bin/sh\necho "flags=0x10000(runtime)"\n',
                "ditto": '#!/bin/sh\ncp -R "$1" "$2"\n',
                "hdiutil": '''#!/bin/bash
if [[ "$1" == create ]]; then
  printf 'verified fixture image' > "${@: -1}"
fi
''',
            }
            for name, content in commands.items():
                executable = binaries / name
                executable.write_text(content)
                executable.chmod(0o755)
            output = root / "output"
            completed = run(scripts / "release.sh", "--output-dir", str(output), env={
                "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                "ORIGINAL_CHECKOUT": str(repository),
                "TMPDIR": str(root),
            })
            self.assertEqual(completed.returncode, 0, completed.stderr)
            image = output / "HHVacancySber_1.1_9_macos13_arm64.dmg"
            self.assertEqual(image.read_bytes(), b"verified fixture image")
            verification = subprocess.run(["shasum", "-a", "256", "-c", image.name + ".sha256"],
                                          cwd=output, capture_output=True)
            self.assertEqual(verification.returncode, 0, verification.stderr)
            self.assertEqual(list(root.glob("hhvacancysber-release.*")), [])


if __name__ == "__main__":
    unittest.main()
