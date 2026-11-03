#!/usr/bin/env python3
"""Draw the tree and pine chop frames (#333) from the tileset atlas.

Writes, under art/flagoria/fx/:
- tree_hit.png (32x32): the hit sheet of tree.tres, one row per tile in its
  `tiles` (TREE, then TREE_BUSHY), 2 frames of 16x16: the canopy sways right
  on the impact, then its top swings back left. The trunk stays put.
- pine_hit.png (32x16): the same for TREE_PINE_SMALL.
- fx_tree.png, fx_pine.png (64x16): fx sheets like fx_leaves.png. Frames 0-1
  after each impact: the white hit spark on the trunk and wood chips, then the
  chips flying out with a leaf or needle off the canopy. Frames 2-3 when it
  falls (under the puff): leaves or needles burst out, then land.

Colours come from the atlas palette, and the leaf shape is the bush's in
fx_leaves.png, so the frames match the bush ones (#293). Run from the repo
root: python3 tools/art/gen_tree_chop_frames.py (needs Pillow).
"""
from PIL import Image

ATLAS = "art/flagoria/flagoria_tiles_v3.png"
OUT = "art/flagoria/fx/"
TILE = 16
# Atlas cells (Scripts/tile_catalog.gd) and the first row of each trunk.
TREE, TREE_BUSHY, TREE_PINE_SMALL = (7, 0), (7, 1), (7, 2)
TRUNK_FROM = {TREE: 10, TREE_BUSHY: 12, TREE_PINE_SMALL: 12}

PAL = {
    "a": (42, 34, 56, 255),  # outline
    "b": (182, 224, 76, 255),  # leaf light
    "c": (111, 191, 58, 255),  # leaf
    "d": (63, 138, 60, 255),  # leaf dark
    "e": (36, 96, 74, 255),  # leaf darkest
    "f": (116, 69, 42, 255),  # bark
    "g": (176, 111, 60, 255),  # wood
    "i": (224, 169, 107, 255),  # cut wood
    "W": (255, 255, 255, 255),  # hit spark
}
LEAF = [".aa.", "abca", ".ada", "..a."]  # the bush's leaf
LEAF_SMALL = ["abda", ".aa."]
NEEDLE = [".aa.", "adea", ".aea", "..a."]
NEEDLE_SMALL = ["adea", ".aa."]
CHIP = [".aa.", "agia", ".aa."]
CHIP_SMALL = ["aga", ".a."]
SPARK = [".W.", "W.W", ".W."]


def tile(atlas: Image.Image, cell: tuple) -> Image.Image:
    x, y = cell[0] * TILE, cell[1] * TILE
    return atlas.crop((x, y, x + TILE, y + TILE))


def sway(src: Image.Image, trunk_from: int, top_dx: int, low_dx: int) -> Image.Image:
    """Canopy rows above trunk_from moved sideways: the top half by top_dx,
    the lower half by low_dx. Trunk rows stay where they are. A row that
    already touches the tile edge it moves to keeps its outline there."""
    out = Image.new("RGBA", (TILE, TILE))
    for y in range(TILE):
        dx = 0 if y >= trunk_from else (top_dx if y < trunk_from // 2 else low_dx)
        row = src.crop((0, y, TILE, y + 1))
        out.paste(row, (dx, y), row)
        edge = TILE - 1 if dx > 0 else 0
        if dx != 0 and src.getpixel((edge, y))[3] > 0:
            out.putpixel((edge, y), PAL["a"])
    return out


def stamp(img: Image.Image, shape: list, x: int, y: int) -> None:
    for dy, line in enumerate(shape):
        for dx, ch in enumerate(line):
            if ch != "." and 0 <= x + dx < img.width and 0 <= y + dy < img.height:
                img.putpixel((x + dx, y + dy), PAL[ch])


def hit_sheet(atlas: Image.Image, cells: list) -> Image.Image:
    sheet = Image.new("RGBA", (2 * TILE, TILE * len(cells)))
    for row, cell in enumerate(cells):
        src = tile(atlas, cell)
        for col, (top, low) in enumerate([(1, 1), (-1, 0)]):
            sheet.paste(sway(src, TRUNK_FROM[cell], top, low), (col * TILE, row * TILE))
    return sheet


def fx_sheet(leaf: list, leaf_small: list) -> Image.Image:
    frames = [
        # 0: the axe lands: spark on the trunk, chips off both sides.
        [(SPARK, 6, 10), (CHIP_SMALL, 2, 10), (CHIP_SMALL, 11, 11)],
        # 1: chips fly out, a leaf shakes off each side of the canopy.
        [(CHIP, 0, 8), (CHIP_SMALL, 13, 9), (leaf_small, 1, 1), (leaf, 11, 0)],
        # 2: it falls: leaves burst out past the puff.
        [(leaf, 6, 0), (leaf, 0, 4), (leaf, 12, 5), (CHIP_SMALL, 2, 12)],
        # 3: they land.
        [(leaf, 0, 9), (leaf_small, 11, 12), (CHIP_SMALL, 6, 13)],
    ]
    sheet = Image.new("RGBA", (4 * TILE, TILE))
    for i, shapes in enumerate(frames):
        for shape, x, y in shapes:
            stamp(sheet, shape, i * TILE + x, y)
    return sheet


def main() -> None:
    atlas = Image.open(ATLAS).convert("RGBA")
    hit_sheet(atlas, [TREE, TREE_BUSHY]).save(OUT + "tree_hit.png")
    hit_sheet(atlas, [TREE_PINE_SMALL]).save(OUT + "pine_hit.png")
    fx_sheet(LEAF, LEAF_SMALL).save(OUT + "fx_tree.png")
    fx_sheet(NEEDLE, NEEDLE_SMALL).save(OUT + "fx_pine.png")


if __name__ == "__main__":
    main()
