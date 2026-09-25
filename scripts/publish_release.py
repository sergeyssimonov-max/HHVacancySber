#!/usr/bin/env python3
"""Publish a verified DMG and checksum without replacing existing entries."""

import hashlib
import os
from pathlib import Path
import shutil
import sys
import tempfile


def publish(source, directory):
    source, directory = Path(source), Path(directory)
    name = source.name
    published = []
    # Stage on the destination filesystem: hard links then publish complete files
    # exclusively, including when the build's temporary directory is on another disk.
    with tempfile.TemporaryDirectory(prefix=".release-", dir=directory) as temporary:
        staged = Path(temporary) / name
        shutil.copyfile(source, staged)
        digest = hashlib.sha256()
        with staged.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        checksum = Path(temporary) / (name + ".sha256")
        checksum.write_text(f"{digest.hexdigest()}  {name}\n", encoding="utf-8")
        try:
            for item in (staged, checksum):
                target = directory / item.name
                os.link(item, target)
                published.append((item, target))
        except BaseException:
            for item, target in reversed(published):
                try:
                    owned, current = item.stat(), target.lstat()
                    if (owned.st_dev, owned.st_ino) == (current.st_dev, current.st_ino):
                        target.unlink()
                except FileNotFoundError:
                    pass
            raise
    return directory / name


if __name__ == "__main__":
    print(publish(sys.argv[1], sys.argv[2]))
