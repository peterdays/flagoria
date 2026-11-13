#!/usr/bin/env python3
"""Draw the placeholder owner flags (#274) into the tileset atlas.

Recolours the blue team flag PROP_FLAG_BLUE (2, 7) into:
- PROP_FLAG_NEUTRAL (4, 7): grey cloth, a tower nobody owns;
- PROP_FLAG_MOBS (5, 7): purple cloth, a tower the mobs took.

Only the two cloth blues change; the pole, its cap, the base and the emblem
keep the atlas palette. Placeholders until flag art exists. Rerunning
rewrites the same two cells. Run from the repo root:
python3 tools/art/gen_flag_tiles.py (needs Pillow).
"""
from PIL import Image

ATLAS = "art/flagoria/flagoria_tiles_v4.png"
TILE = 16
SOURCE = (2, 7)  # PROP_FLAG_BLUE
CLOTH_LIGHT = (59, 111, 224, 255)
CLOTH_DARK = (38, 67, 154, 255)
OUT = {
    (4, 7): {CLOTH_LIGHT: (196, 196, 204, 255), CLOTH_DARK: (128, 128, 142, 255)},  # neutral
    (5, 7): {CLOTH_LIGHT: (156, 84, 196, 255), CLOTH_DARK: (98, 48, 132, 255)},  # mobs
}


def main() -> None:
    atlas = Image.open(ATLAS).convert("RGBA")
    sx, sy = SOURCE[0] * TILE, SOURCE[1] * TILE
    src = atlas.crop((sx, sy, sx + TILE, sy + TILE))
    for cell, recolour in OUT.items():
        tile = src.copy()
        px = tile.load()
        for y in range(TILE):
            for x in range(TILE):
                px[x, y] = recolour.get(px[x, y], px[x, y])
        atlas.paste(tile, (cell[0] * TILE, cell[1] * TILE))
    atlas.save(ATLAS)


if __name__ == "__main__":
    main()
