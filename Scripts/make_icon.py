#!/usr/bin/env python3
"""Generates the AutoType app icon and the input-menu template icon.

The app icon is a rounded square with the Persian letter آ (alef with a
madda), which reads as the first letter of "AutoType" in Persian. The menu
icon is a monochrome template image, the shape macOS expects for an input
source that appears in the menu bar.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / ".build" / "icons"
FONT_PATH = "/System/Library/Fonts/SFArabic.ttf"

# The palette: a deep indigo that reads well next to the macOS window chrome.
BACKGROUND = (38, 42, 74, 255)
ACCENT = (126, 214, 223, 255)
FOREGROUND = (255, 255, 255, 255)


def rounded_rect(draw: ImageDraw.ImageDraw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def draw_glyph(size: int, color, glyph: str = "آ") -> Image.Image:
    """Draws a single Persian glyph centred on a transparent canvas."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(FONT_PATH, int(size * 0.62))
    left, top, right, bottom = draw.textbbox((0, 0), glyph, font=font)
    x = (size - (right - left)) / 2 - left
    y = (size - (bottom - top)) / 2 - top
    draw.text((x, y), glyph, font=font, fill=color)
    return canvas


def build_app_icon() -> Path:
    """Builds the .icns file used as the application icon."""
    if BUILD.exists():
        shutil.rmtree(BUILD)
    iconset = BUILD / "AutoType.iconset"
    iconset.mkdir(parents=True)

    master = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    draw = ImageDraw.Draw(master)
    rounded_rect(draw, (0, 0, 1023, 1023), radius=220, fill=BACKGROUND)

    # A soft accent band along the bottom edge, echoing a text cursor.
    rounded_rect(draw, (300, 800, 724, 830), radius=15, fill=ACCENT)

    glyph = draw_glyph(1024, FOREGROUND)
    master = Image.alpha_composite(master, glyph)

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in sizes.items():
        master.resize((size, size), Image.LANCZOS).save(iconset / name)

    icns = BUILD / "AutoType.icns"
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(icns)],
        check=True,
    )
    return icns


def build_menu_icons() -> list[Path]:
    """Builds the monochrome template icons shown in the input menu."""
    out = []
    for size, name in ((16, "AutoTypeMenuTemplate.png"), (32, "AutoTypeMenuTemplate@2x.png")):
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        glyph = draw_glyph(size, (0, 0, 0, 255))
        canvas = Image.alpha_composite(canvas, glyph)
        path = BUILD / name
        canvas.save(path)
        out.append(path)
    return out


def main() -> int:
    if not os.path.exists(FONT_PATH):
        print(f"error: font not found at {FONT_PATH}", file=sys.stderr)
        return 1
    BUILD.mkdir(parents=True, exist_ok=True)
    icns = build_app_icon()
    for path in build_menu_icons():
        print(f"menu icon: {path}")
    print(f"app icon:  {icns}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
