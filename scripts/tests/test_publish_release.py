import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("publish_release", Path(__file__).resolve().parents[1] / "publish_release.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.source = root / "test.dmg"
        self.source.write_bytes(b"verified image")
        self.output = root / "output"
        self.output.mkdir()

    def test_complete_pair_and_checksum(self):
        result = module.publish(self.source, self.output)
        self.assertEqual(result.read_bytes(), self.source.read_bytes())
        self.assertEqual((self.output / "test.dmg.sha256").read_text(),
                         hashlib.sha256(self.source.read_bytes()).hexdigest() + "  test.dmg\n")
        self.assertEqual(len(list(self.output.iterdir())), 2)

    def test_conflicting_checksum_rolls_back_image_and_preserves_existing(self):
        checksum = self.output / "test.dmg.sha256"
        checksum.write_text("existing checksum")
        with self.assertRaises(FileExistsError):
            module.publish(self.source, self.output)
        self.assertEqual(checksum.read_text(), "existing checksum")
        self.assertEqual(list(self.output.iterdir()), [checksum])

    def test_image_file_directory_and_dangling_symlink_are_never_replaced(self):
        target = self.output / "test.dmg"
        for kind in ("file", "directory", "symlink"):
            with self.subTest(kind=kind):
                if kind == "file": target.write_text("existing")
                elif kind == "directory": target.mkdir()
                else: target.symlink_to(self.output / "missing")
                with self.assertRaises(FileExistsError):
                    module.publish(self.source, self.output)
                self.assertEqual(list(self.output.iterdir()), [target])
                if kind == "file": self.assertEqual(target.read_text(), "existing")
                if kind == "directory": target.rmdir()
                else: target.unlink()

    def test_failed_second_publication_preserves_replacement(self):
        link = module.os.link
        def replace_then_fail(source, target):
            if str(target).endswith(".sha256"):
                image = self.output / "test.dmg"
                image.unlink()
                image.write_text("replacement")
                raise OSError("disk failure")
            link(source, target)
        with patch.object(module.os, "link", side_effect=replace_then_fail):
            with self.assertRaises(OSError):
                module.publish(self.source, self.output)
        self.assertEqual((self.output / "test.dmg").read_text(), "replacement")
        self.assertEqual(len(list(self.output.iterdir())), 1)
