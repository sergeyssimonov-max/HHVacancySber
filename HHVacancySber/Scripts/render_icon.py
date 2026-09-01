#!/usr/bin/env python3
"""Render the canonical SVG into every macOS AppIcon slot.

Backends are tried in this order: CairoSVG, rsvg-convert, Pillow. The script
fails explicitly when none is available and never keeps unrelated legacy art.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Design" / "AppIcon.svg"
OUTPUT = ROOT / "HHVacancySber" / "Assets.xcassets" / "AppIcon.appiconset"
SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
         (256, 1), (256, 2), (512, 1), (512, 2)]


def render(source: Path, target: Path, pixels: int) -> None:
    try:
        import cairosvg  # type: ignore
        cairosvg.svg2png(url=str(source), write_to=str(target),
                         output_width=pixels, output_height=pixels)
        return
    except ImportError:
        pass

    converter = shutil.which("rsvg-convert")
    if converter:
        subprocess.run(
            [converter, "-w", str(pixels), "-h", str(pixels),
             "-o", str(target), str(source)], check=True)
        return

    try:
        from PIL import Image  # type: ignore
    except ImportError as error:
        raise RuntimeError(
            "No supported SVG renderer. Install CairoSVG, rsvg-convert, or Pillow."
        ) from error

    try:
        image = Image.open(source)
        image.resize((pixels, pixels), Image.Resampling.LANCZOS).save(target)
    except Exception as error:
        raise RuntimeError(
            "Installed Pillow cannot decode SVG; install CairoSVG or rsvg-convert."
        ) from error


def main() -> int:
    if not SOURCE.is_file():
        print(f"Missing canonical icon: {SOURCE}", file=sys.stderr)
        return 1
    OUTPUT.mkdir(parents=True, exist_ok=True)
    images = []
    try:
        for points, scale in SLOTS:
            pixels = points * scale
            filename = f"appicon_{points}x{points}@{scale}x.png"
            render(SOURCE, OUTPUT / filename, pixels)
            images.append({
                "filename": filename,
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{points}x{points}",
            })
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (OUTPUT / "Contents.json").write_text(
        json.dumps(contents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
