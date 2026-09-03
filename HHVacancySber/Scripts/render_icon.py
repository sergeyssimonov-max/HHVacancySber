#!/usr/bin/env python3
"""Render the canonical SVG into every macOS AppIcon slot.

Backends are tried in this order: CairoSVG, rsvg-convert, macOS AppKit,
Pillow. The script fails explicitly when none is available and never keeps
unrelated legacy art.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Design" / "AppIcon.svg"
OUTPUT = ROOT / "HHVacancySber" / "Assets.xcassets" / "AppIcon.appiconset"
SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
         (256, 1), (256, 2), (512, 1), (512, 2)]

APPKIT_RENDERER = r"""
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4, let pixels = Int(arguments[3]), pixels > 0 else { exit(2) }
let source = URL(fileURLWithPath: arguments[1])
let target = URL(fileURLWithPath: arguments[2])
guard let image = NSImage(contentsOf: source),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(3) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
image.draw(
    in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
    from: NSRect(origin: .zero, size: image.size),
    operation: .copy,
    fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

var foundGreenPixel = false
var minX = pixels
var minY = pixels
var maxX = -1
var maxY = -1
if let bytes = bitmap.bitmapData {
    for y in 0..<pixels {
        for x in 0..<pixels {
            let offset = y * bitmap.bytesPerRow + x * 4
            let red = Int(bytes[offset])
            let green = Int(bytes[offset + 1])
            let blue = Int(bytes[offset + 2])
            let alpha = Int(bytes[offset + 3])
            if alpha > 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
            if alpha > 0 && green > red + 20 && green > blue + 20 {
                foundGreenPixel = true
            }
        }
    }
}

guard foundGreenPixel,
      minX > 0,
      minY > 0,
      maxX < pixels - 1,
      maxY < pixels - 1,
      let data = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
try data.write(to: target, options: .atomic)
"""


def render(source: Path, target: Path, pixels: int) -> None:
    try:
        import cairosvg  # type: ignore
        cairosvg.svg2png(url=str(source), write_to=str(target),
                         output_width=pixels, output_height=pixels)
        return
    except (ImportError, OSError):
        pass

    converter = shutil.which("rsvg-convert")
    if converter:
        subprocess.run(
            [converter, "-w", str(pixels), "-h", str(pixels),
             "-o", str(target), str(source)], check=True)
        return

    xcrun = shutil.which("xcrun")
    if xcrun:
        with tempfile.TemporaryDirectory(prefix="hhvacancysber-icon-") as directory:
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(Path(directory) / "clang-cache")
            environment["SWIFT_MODULE_CACHE_PATH"] = str(Path(directory) / "swift-cache")
            try:
                subprocess.run(
                    [xcrun, "swift", "-e", APPKIT_RENDERER,
                     str(source), str(target), str(pixels)],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    text=True,
                    env=environment,
                )
                return
            except subprocess.CalledProcessError:
                pass

    try:
        from PIL import Image  # type: ignore
    except ImportError as error:
        raise RuntimeError(
            "No supported SVG renderer. Install CairoSVG, rsvg-convert, or Pillow, "
            "or run on macOS with Xcode and AppKit available."
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
