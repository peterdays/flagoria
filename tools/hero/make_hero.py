#!/usr/bin/env python3
"""Build player sprite sheets from layered pixel parts.

A hero is a recipe (art/hero/heroes/<name>.ini) that lists parts and colour
ramps. Parts (art/hero/parts/<part>.txt) are small character grids, one per
facing and optional walk pose. The script stacks the parts, adds a 1 px
outline and writes a sheet with the same layout as the current player sheet,
so a later swap only changes the texture of the player's Sprite2D.

Sheet layout (16x16 frames, 8 columns x 16 rows, 128x256 px):
  rows 0-3: walk down, left, right, up; columns 0-3 = walk frames
  rows 4-7: attack down, left, right, up; columns 0-3 = the same lunge pose
Everything else is transparent. Player/character_body_2d.tscn reads rows 0-3
for walking and column 2 of rows 5-7 for attacks.

Usage:
  python3 tools/hero/make_hero.py [--out DIR] [--scale N] [hero ...]

With no hero names, every recipe is built. Output per hero (DIR defaults to
artifacts/hero, which git ignores):
  <hero>_sheet.png     128x256 sheet in the player layout
  <hero>_preview.png   4 facings + one walk frame, upscaled (nearest)
and all_heroes.png with every preview on one board.
"""
import argparse
import configparser
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERO = os.path.join(ROOT, "art", "hero")
PARTS = os.path.join(HERO, "parts")
RECIPES = os.path.join(HERO, "heroes")

FRAME = 16
COLS, ROWS = 8, 16
FACINGS = ["down", "left", "right", "up"]
# Walk cycle: pose index per frame (0 = stand, 1 and 2 = steps).
WALK = [1, 0, 2, 0]
# Attack frames reuse step pose 1, nudged 1 px towards the facing.
LUNGE = {"down": (0, 1), "left": (-1, 0), "right": (1, 0), "up": (0, -1)}

# Lower-case symbol = lit tone of a ramp, upper case = its shade.
RAMPS = {
    "s": "skin", "h": "hair", "a": "outfit", "b": "trim", "p": "pants",
    "k": "boots", "m": "metal", "c": "cape", "f": "flag", "x": "wood",
    "t": "hat", "g": "gold",
}
# Single colours (no shade).
SINGLE = {"e": "eye", "w": "white"}
DEFAULT_COLOURS = {"eye": "#141b1b", "white": "#f2eaf1", "outline": "#141b1b"}
SECTION = re.compile(r"^\[(down|left|right|up)(?:/(\d))?((?:\s+\w+=-?\d+)*)\]$")


def hex_rgb(value):
    value = value.strip().lstrip("#")
    if not re.fullmatch(r"[0-9a-fA-F]{6}", value):
        raise ValueError("bad colour '%s'" % value)
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def load_part(name):
    """Return {(facing, pose or None, z): [x, y, rows]}.

    Section header: [facing] or [facing/pose], optional y=N (first row,
    default 0), x=N (column shift) and z=-1|0|1 (behind every part, in
    recipe order, or in front of every part; default 0).
    """
    path = os.path.join(PARTS, name + ".txt")
    if not os.path.exists(path):
        sys.exit("unknown part '%s' (%s)" % (name, path))
    grids, current = {}, None
    with open(path, encoding="utf-8") as f:
        for n, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            m = SECTION.match(line)
            if m:
                opts = dict(o.split("=") for o in m.group(3).split())
                z = int(opts.get("z", 0))
                if z not in (-1, 0, 1):
                    sys.exit("%s:%d: z must be -1, 0 or 1" % (path, n))
                pose = None if m.group(2) is None else int(m.group(2))
                current = [int(opts.get("x", 0)), int(opts.get("y", 0)), []]
                grids[(m.group(1), pose, z)] = current
                continue
            if current is None:
                sys.exit("%s:%d: grid row before any [section]" % (path, n))
            if len(line) != FRAME:
                sys.exit("%s:%d: row must be %d characters, got %d" % (path, n, FRAME, len(line)))
            for ch in line:
                if ch != "." and ch.lower() not in RAMPS and ch not in SINGLE:
                    sys.exit("%s:%d: unknown symbol '%s'" % (path, n, ch))
            current[2].append(line)
    for (facing, _pose, _z), (_x, y, rows) in grids.items():
        if y + len(rows) > FRAME:
            sys.exit("%s: [%s] runs past row %d" % (path, facing, FRAME))
    return grids


def load_recipe(name):
    cp = configparser.ConfigParser()
    path = os.path.join(RECIPES, name + ".ini")
    if not cp.read(path, encoding="utf-8"):
        sys.exit("unknown hero '%s'" % name)
    hero = cp["hero"]
    colours = {k: hex_rgb(v) for k, v in DEFAULT_COLOURS.items()}
    for key, value in cp["colours"].items():
        tones = value.split()
        if key in SINGLE.values() or key == "outline":
            colours[key] = hex_rgb(tones[0])
        elif key in RAMPS.values():
            if len(tones) != 2:
                sys.exit("%s: ramp '%s' needs two colours (lit, shade)" % (path, key))
            colours[key] = (hex_rgb(tones[0]), hex_rgb(tones[1]))
        else:
            sys.exit("%s: unknown colour '%s'" % (path, key))
    return {
        "name": hero.get("name", name),
        "title": hero.get("title", ""),
        "parts": hero.get("parts").split(),
        "colours": colours,
    }


def colour_of(ch, colours):
    if ch in SINGLE:
        return colours[SINGLE[ch]]
    ramp = RAMPS[ch.lower()]
    if ramp not in colours:
        sys.exit("symbol '%s' needs a '%s' ramp in [colours]" % (ch, ramp))
    return colours[ramp][1 if ch.isupper() else 0]


def pick(grids, facing, pose, z):
    """The grid for a facing/pose; right falls back to a mirrored left."""
    options = [(facing, False)] + ([("left", True)] if facing == "right" else [])
    for f, mirror in options:
        for p in (pose, None):
            g = grids.get((f, p, z))
            if g is not None:
                return g, mirror
    return None, False


def compose(recipe, parts, facing, pose, dx=0, dy=0):
    img = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    for z in (-1, 0, 1):
        for name in recipe["parts"]:
            grid, mirror = pick(parts[name], facing, pose, z)
            if grid is None:
                continue
            gx, gy, rows = grid
            for y, row in enumerate(rows):
                for x, ch in enumerate(row):
                    if ch == ".":
                        continue
                    px = x + gx
                    if mirror:
                        px = FRAME - 1 - px
                    px, py = px + dx, y + gy + dy
                    if 0 <= px < FRAME and 0 <= py < FRAME:
                        img.putpixel((px, py), colour_of(ch, recipe["colours"]))
    return outline(img, recipe["colours"]["outline"])


def outline(img, colour):
    """1 px outline on every transparent pixel next to a filled one."""
    out = img.copy()
    for y in range(FRAME):
        for x in range(FRAME):
            if img.getpixel((x, y))[3]:
                continue
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < FRAME and 0 <= ny < FRAME and img.getpixel((nx, ny))[3]:
                    out.putpixel((x, y), colour)
                    break
    return out


def build_sheet(recipe, parts):
    sheet = Image.new("RGBA", (COLS * FRAME, ROWS * FRAME), (0, 0, 0, 0))
    for row, facing in enumerate(FACINGS):
        for col, pose in enumerate(WALK):
            sheet.paste(compose(recipe, parts, facing, pose), (col * FRAME, row * FRAME))
        attack = compose(recipe, parts, facing, 1, *LUNGE[facing])
        for col in range(4):
            sheet.paste(attack, (col * FRAME, (row + 4) * FRAME))
    return sheet


def preview(recipe, sheet, scale):
    """Four facings (stand) plus the down walk step, on a light backdrop."""
    cells = [(1, r) for r in range(4)] + [(0, 0)]
    pad = 2
    strip = Image.new("RGBA", (len(cells) * (FRAME + pad) + pad, FRAME + 2 * pad),
                      (0xb8, 0xdc, 0xe5, 255))
    for i, (c, r) in enumerate(cells):
        frame = sheet.crop((c * FRAME, r * FRAME, (c + 1) * FRAME, (r + 1) * FRAME))
        strip.alpha_composite(frame, (pad + i * (FRAME + pad), pad))
    big = strip.resize((strip.width * scale, strip.height * scale), Image.NEAREST)
    label_h = 28
    card = Image.new("RGBA", (big.width, big.height + label_h), (0x4a, 0x52, 0x70, 255))
    card.paste(big, (0, label_h))
    text = "%s  -  %s" % (recipe["name"], recipe["title"])
    ImageDraw.Draw(card).text((8, 8), text, fill=(0xf2, 0xea, 0xf1, 255))
    return card


def board(cards, per_row=2, gap=12):
    cw = max(c.width for c in cards)
    ch = max(c.height for c in cards)
    rows = (len(cards) + per_row - 1) // per_row
    img = Image.new("RGBA", (per_row * (cw + gap) + gap, rows * (ch + gap) + gap),
                    (0x3b, 0x36, 0x43, 255))
    for i, c in enumerate(cards):
        img.paste(c, (gap + (i % per_row) * (cw + gap), gap + (i // per_row) * (ch + gap)))
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("heroes", nargs="*")
    ap.add_argument("--out", default=os.path.join(ROOT, "artifacts", "hero"))
    ap.add_argument("--scale", type=int, default=8)
    args = ap.parse_args()
    names = args.heroes or sorted(f[:-4] for f in os.listdir(RECIPES) if f.endswith(".ini"))
    os.makedirs(args.out, exist_ok=True)
    cards = []
    for name in names:
        recipe = load_recipe(name)
        parts = {p: load_part(p) for p in recipe["parts"]}
        sheet = build_sheet(recipe, parts)
        sheet.save(os.path.join(args.out, name + "_sheet.png"))
        card = preview(recipe, sheet, args.scale)
        card.save(os.path.join(args.out, name + "_preview.png"))
        cards.append(card)
        print("built", name)
    if len(cards) > 1:
        board(cards).save(os.path.join(args.out, "all_heroes.png"))


if __name__ == "__main__":
    main()
