#!/usr/bin/env python3
"""Render the Flagoria app icon from the hand-authored pixel grid.

Source of truth: art/icon/tower_32.txt (32x32 characters, legend below).
Everything is upscaled with nearest-neighbour so pixels stay crisp.

Outputs (art/icon/):
  icon.png                     256x256 project / window icon
  launcher_main_192.png        Android main icon (pre-Android 8)
  launcher_fg_432.png          Android adaptive foreground (transparent)
  launcher_bg_432.png          Android adaptive background (sky)

Usage:
  python3 tools/icon/make_icon.py [--preview DIR]
"""
import math
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "art", "icon")
GRID = os.path.join(ART, "tower_32.txt")

# Colours picked from art/Sprites/NinjaAdventure/Palette.png so the icon
# matches the in-game look.
PALETTE = {
    "O": (0x14, 0x1B, 0x1B),  # outline
    "L": (0xAB, 0xC2, 0xBC),  # stone, lit
    "M": (0x8D, 0x97, 0x7F),  # stone
    "D": (0x5F, 0x71, 0x60),  # stone, shade / mortar
    "K": (0x3B, 0x36, 0x43),  # doorway, deep shade
    "P": (0x81, 0x68, 0x55),  # flag pole
    "Y": (0xFF, 0xE1, 0x8D),  # gold finial / highlights
    "W": (0xF1, 0xC4, 0x71),  # lit window
    "R": (0xE0, 0x39, 0x4C),  # flag
    "r": (0x8F, 0x3E, 0x56),  # flag, shade
    "F": (0xF2, 0xEA, 0xF1),  # flag emblem
    "G": (0x74, 0xA3, 0x34),  # grass
    "g": (0x56, 0x86, 0x4C),  # grass, shade
}
# Sky bands, top to bottom (also from the game palette).
SKY = [(0x2D, 0x69, 0x7B), (0x54, 0x87, 0x89), (0x79, 0xB8, 0xCE), (0x8F, 0xEF, 0xF1)]
CLOUD = (0xF2, 0xEA, 0xF1)
CLOUD_SHADE = (0xB8, 0xDC, 0xE5)

# Adaptive icons: 108dp layer, critical art inside a centred 66dp circle.
ADAPTIVE = 432
SAFE_RADIUS = ADAPTIVE * 66 / 108 / 2  # 132 px


def load_grid():
    with open(GRID, encoding="utf-8") as f:
        rows = [line.rstrip("\n") for line in f if line.strip("\n")]
    if len(rows) != 32 or any(len(r) != 32 for r in rows):
        sys.exit("tower_32.txt must be 32 rows of 32 characters")
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            if ch not in PALETTE:
                sys.exit("unknown colour '%s' at %d,%d" % (ch, x, y))
            img.putpixel((x, y), PALETTE[ch] + (255,))
    return img


def sky(n):
    """n x n pixel sky: colour bands plus two small clouds."""
    img = Image.new("RGBA", (n, n))
    d = ImageDraw.Draw(img)
    for y in range(n):
        band = min(len(SKY) - 1, y * len(SKY) // n)
        d.line([(0, y), (n - 1, y)], fill=SKY[band] + (255,))

    def cloud(cx, cy, w):
        d.rectangle([cx, cy, cx + w, cy + 1], fill=CLOUD)
        d.rectangle([cx + 1, cy - 1, cx + w // 2, cy - 1], fill=CLOUD)
        d.line([(cx, cy + 2), (cx + w, cy + 2)], fill=CLOUD_SHADE)

    cloud(n * 3 // 32, n * 9 // 32, max(3, n * 4 // 32))
    cloud(n * 23 // 32, n * 18 // 32, max(3, n * 5 // 32))
    return img


def up(img, s):
    return img.resize((img.width * s, img.height * s), Image.NEAREST)


def fits_safe_zone(art, scale, ox, oy):
    """True if every opaque art pixel lies inside the adaptive safe circle."""
    c = ADAPTIVE / 2
    for y in range(art.height):
        for x in range(art.width):
            if art.getpixel((x, y))[3] == 0:
                continue
            for px, py in ((x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)):
                if math.hypot(ox + px * scale - c, oy + py * scale - c) > SAFE_RADIUS:
                    return False
    return True


def foreground(art):
    bbox = art.getbbox()
    crop = art.crop(bbox)
    for scale in range(12, 0, -1):
        w, h = crop.width * scale, crop.height * scale
        ox, oy = (ADAPTIVE - w) // 2, (ADAPTIVE - h) // 2
        if fits_safe_zone(crop, scale, ox, oy):
            fg = Image.new("RGBA", (ADAPTIVE, ADAPTIVE), (0, 0, 0, 0))
            fg.paste(up(crop, scale), (ox, oy))
            return fg, scale
    sys.exit("art does not fit the adaptive safe zone")


def full_icon(art, size):
    """Square icon: sky plus art, art scaled by an integer factor."""
    s = size // 32
    img = up(sky(32), s)
    img.alpha_composite(up(art, s))
    return img


def main():
    art = load_grid()
    full_icon(art, 256).save(os.path.join(ART, "icon.png"))
    full_icon(art, 192).save(os.path.join(ART, "launcher_main_192.png"))
    fg, scale = foreground(art)
    fg.save(os.path.join(ART, "launcher_fg_432.png"))
    bg = up(sky(ADAPTIVE // scale + 1), scale).crop((0, 0, ADAPTIVE, ADAPTIVE))
    bg.save(os.path.join(ART, "launcher_bg_432.png"))
    print("icons written; adaptive foreground scale x%d" % scale)
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1], art, fg, bg)


def adaptive_masked(fg, bg, size):
    """What a launcher shows: layers composited, outer 18dp cropped, circle mask."""
    comp = bg.copy()
    comp.alpha_composite(fg)
    inset = ADAPTIVE * 18 // 108
    comp = comp.crop((inset, inset, ADAPTIVE - inset, ADAPTIVE - inset))
    comp = comp.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
    comp.putalpha(mask.resize((size, size), Image.LANCZOS))
    return comp


def preview(out, art, fg, bg):
    os.makedirs(out, exist_ok=True)
    full_icon(art, 512).save(os.path.join(out, "icon_512.png"))
    adaptive_masked(fg, bg, 512).save(os.path.join(out, "icon_adaptive_512.png"))
    # Safe-zone overlay for review.
    ov = bg.copy()
    ov.alpha_composite(fg)
    d = ImageDraw.Draw(ov)
    c = ADAPTIVE / 2
    d.ellipse([c - SAFE_RADIUS, c - SAFE_RADIUS, c + SAFE_RADIUS, c + SAFE_RADIUS],
              outline=(255, 0, 255, 255), width=2)
    ov.save(os.path.join(out, "adaptive_safe_zone.png"))
    # Phone home-screen mock with the icon at 48 px among placeholder icons.
    w, h = 360, 640
    phone = Image.new("RGBA", (w, h))
    pd = ImageDraw.Draw(phone)
    for y in range(h):
        t = y / h
        pd.line([(0, y), (w, y)], fill=(int(40 + 30 * t), int(30 + 20 * t), int(70 + 40 * t), 255))
    pd.rectangle([0, 0, w, 24], fill=(24, 18, 44, 255))
    pd.text((12, 6), "12:00", fill=(255, 255, 255, 255))
    icon48 = adaptive_masked(fg, bg, 48)
    cols, cell = 4, 80
    x0, y0 = (w - cols * cell) // 2, 380
    others = [(0xD1, 0x4B, 0x34), (0x4A, 0x52, 0x70), (0xA8, 0xA1, 0x29), (0x2D, 0x69, 0x7B),
              (0x8F, 0x3E, 0x56), (0x56, 0x86, 0x4C), (0xE4, 0x6D, 0x3A)]
    names = ["Clock", "Mail", "Notes", "Maps", "Music", "Files", "Camera"]
    k = 0
    for i in range(8):
        cx = x0 + (i % cols) * cell + (cell - 48) // 2
        cy = y0 + (i // cols) * 96
        if i == 5:
            phone.alpha_composite(icon48, (cx, cy))
            label = "Flagoria"
        else:
            pd.ellipse([cx, cy, cx + 47, cy + 47], fill=others[k] + (255,))
            label = names[k]
            k += 1
        tw = pd.textlength(label)
        pd.text((cx + 24 - tw / 2, cy + 54), label, fill=(255, 255, 255, 255))
    pd.rounded_rectangle([20, h - 40, w - 20, h - 12], radius=14, fill=(92, 80, 128, 255))
    phone.save(os.path.join(out, "phone_mock_48.png"))
    up(phone, 2).save(os.path.join(out, "phone_mock_48_x2.png"))
    print("previews written to", out)


if __name__ == "__main__":
    main()
