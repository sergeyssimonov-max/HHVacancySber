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


if __name__ == "__main__":
    unittest.main()
