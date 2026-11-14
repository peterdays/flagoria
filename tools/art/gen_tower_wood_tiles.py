#!/usr/bin/env python3
"""Draw placeholder wooden-tower tiles (#273) into the tileset atlas and the
interact-mode Tower picker icon.

Atlas cells (empty in v3 before this runs):
- TOWER_WOOD_POST (6, 7): a short palisade post
- TOWER_WOOD_WALL (7, 7): a short palisade wall segment

Also writes art/ui/ui_tool_tower.png (16x16) from art/icon/tower_32.txt so the
build picker has a Tower icon. Placeholders until dedicated tower art exists.
Rerunning rewrites the same cells and icon. Run from the repo root:
python3 tools/art/gen_tower_wood_tiles.py (needs Pillow).
"""
from __future__ import annotations

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ATLAS = os.path.join(ROOT, "art", "flagoria", "flagoria_tiles_v4.png")
ICON_GRID = os.path.join(ROOT, "art", "icon", "tower_32.txt")
PICKER = os.path.join(ROOT, "art", "ui", "ui_tool_tower.png")
TILE = 16

# Wood palette (NinjaAdventure-adjacent browns).
OUTLINE = (0x14, 0x1B, 0x1B, 255)
WOOD_LIT = (0xC4, 0x8A, 0x4A, 255)
WOOD = (0x8D, 0x5A, 0x32, 255)
WOOD_SHADE = (0x5A, 0x38, 0x20, 255)
BAND = (0x6E, 0x45, 0x28, 255)

POST_CELL = (6, 7)
WALL_CELL = (7, 7)

# Same legend as tools/icon/make_icon.py for the picker glyph.
ICON_PALETTE = {
    "O": (0x14, 0x1B, 0x1B),
    "L": (0xAB, 0xC2, 0xBC),
    "M": (0x8D, 0x97, 0x7F),
    "D": (0x5F, 0x71, 0x60),
    "K": (0x3B, 0x36, 0x43),
    "P": (0x81, 0x68, 0x55),
    "Y": (0xFF, 0xE1, 0x8D),
    "W": (0xF1, 0xC4, 0x71),
    "R": (0xE0, 0x39, 0x4C),
    "r": (0x8F, 0x3E, 0x56),
    "F": (0xF2, 0xEA, 0xF1),
    "G": (0x74, 0xA3, 0x34),
    "g": (0x56, 0x86, 0x4C),
}


def _blank() -> Image.Image:
    return Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))


def _post() -> Image.Image:
    img = _blank()
    px = img.load()
    # Vertical log with a flat top band.
    for y in range(2, 15):
        for x in range(5, 11):
            if x in (5, 10) or y in (2, 14):
                px[x, y] = OUTLINE
            elif y == 3:
                px[x, y] = BAND
            elif x in (6, 7):
                px[x, y] = WOOD_LIT
            elif x == 8:
                px[x, y] = WOOD
            else:
                px[x, y] = WOOD_SHADE
    return img


def _wall() -> Image.Image:
    img = _blank()
    px = img.load()
    for y in range(4, 14):
        for x in range(1, 15):
            if y in (4, 13) or x in (1, 14):
                px[x, y] = OUTLINE
            elif y == 5:
                px[x, y] = BAND
            elif (x + y) % 3 == 0:
                px[x, y] = WOOD_SHADE
            elif x % 2 == 0:
                px[x, y] = WOOD_LIT
            else:
                px[x, y] = WOOD
    return img


def _write_atlas() -> None:
    atlas = Image.open(ATLAS).convert("RGBA")
    for cell, tile in ((POST_CELL, _post()), (WALL_CELL, _wall())):
        atlas.paste(tile, (cell[0] * TILE, cell[1] * TILE))
    atlas.save(ATLAS)


def _write_picker_icon() -> None:
    with open(ICON_GRID, encoding="utf-8") as f:
        rows = [line.rstrip("\n") for line in f if line.strip("\n")]
    if len(rows) != 32 or any(len(r) != 32 for r in rows):
        raise SystemExit("tower_32.txt must be 32 rows of 32 characters")
    src = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            if ch not in ICON_PALETTE:
                raise SystemExit("unknown colour %r at %d,%d" % (ch, x, y))
            src.putpixel((x, y), ICON_PALETTE[ch] + (255,))
    # Crop to the tower mass and scale to 16x16 for the picker row.
    bbox = src.getbbox()
    cropped = src.crop(bbox) if bbox else src
    icon = cropped.resize((16, 16), Image.Resampling.NEAREST)
    os.makedirs(os.path.dirname(PICKER), exist_ok=True)
    icon.save(PICKER)


def main() -> None:
    _write_atlas()
    _write_picker_icon()
    print("wrote TOWER_WOOD_POST (6,7), TOWER_WOOD_WALL (7,7), and", PICKER)


if __name__ == "__main__":
    main()
