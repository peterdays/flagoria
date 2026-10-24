#!/usr/bin/env python3
"""Render the placeholder HUD heart icons from a text grid.

Source: art/ui/hearts/hearts_8.txt, three 8x8 grids headed "# full",
"# half" and "# empty". One character per pixel, "." is transparent.
Writes heart_full.png, heart_half.png and heart_empty.png next to it.

Usage:
  python3 tools/ui/make_hearts.py
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "art", "ui", "hearts")
GRID = os.path.join(ART, "hearts_8.txt")
SIZE = 8

# Colours from art/Sprites/NinjaAdventure/Palette.png, as in the app icon.
PALETTE = {
    "O": (0x14, 0x1B, 0x1B, 255),  # outline
    "R": (0xE0, 0x39, 0x4C, 255),  # heart
    "r": (0x8F, 0x3E, 0x56, 255),  # heart, shade
    "H": (0xF2, 0xEA, 0xF1, 255),  # highlight
    "E": (0x3B, 0x36, 0x43, 255),  # empty
}


def load_grids():
    grids, name = {}, None
    with open(GRID, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("# "):
                name = line[2:].strip()
                grids[name] = []
            elif line and name:
                grids[name].append(line)
    for key in ("full", "half", "empty"):
        rows = grids.get(key, [])
        if len(rows) != SIZE or any(len(r) != SIZE for r in rows):
            sys.exit("hearts_8.txt: '%s' must be %d rows of %d characters" % (key, SIZE, SIZE))
    return grids


def main():
    for name, rows in load_grids().items():
        img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch != ".":
                    img.putpixel((x, y), PALETTE[ch])
        out = os.path.join(ART, "heart_%s.png" % name)
        img.save(out)
        print("wrote", os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main()
