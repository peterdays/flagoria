# Hero sprites

Player sprite sheets are built from small text grids by
`tools/hero/make_hero.py`. Nothing is drawn by hand in an image editor and the
build is deterministic: the same sources always give the same PNGs.

## Build

    python3 tools/hero/make_hero.py                 # every hero
    python3 tools/hero/make_hero.py knight sage     # some heroes
    python3 tools/hero/make_hero.py --out DIR --scale 6

Output goes to `artifacts/hero/` (ignored by git) unless `--out` is given:

- `<hero>_sheet.png`: 128×256 sheet in the player layout (below).
- `<hero>_preview.png`: the four facings plus one walk frame, upscaled with
  nearest-neighbour.
- `all_heroes.png`: every preview on one board.

Requires Python 3 and Pillow, like `tools/icon/make_icon.py`.

## Sheet layout

The sheet matches the layout that `Player/character_body_2d.tscn` already
reads (`hframes = 8`, `vframes = 16`, 16×16 frames), so switching the player
to a generated hero only changes the `Sprite2D` texture.

| Rows | Content | Columns |
|---|---|---|
| 0–3 | walk down, left, right, up | 0–3: step, stand, other step, stand |
| 4–7 | attack down, left, right, up | 0–3: one lunge pose (1 px towards the facing) |

The feet sit on the bottom row of the frame. The Sprite2D is drawn 8 px above
the body origin, so the feet line up with the 8×10 collision box.

## Recipes

A hero is `art/hero/heroes/<name>.ini`:

    [hero]
    name = Island Knight
    title = closed helm, plume, red cape
    parts = cape body legs helmet pauldrons

    [colours]
    skin = #ffcba9 #d3865f
    metal = #abc2bc #8d977f
    ...

`parts` lists part files in drawing order. `[colours]` gives each ramp a lit
and a shade colour. Colours come from the NinjaAdventure palette
(`art/Sprites/NinjaAdventure/Palette.png`), the same palette as the app icon.

## Parts

A part is `art/hero/parts/<part>.txt`: one 16-character grid per facing.

    # Comment
    [down y=9]
    ...mm......mM...
    [left y=9]
    ......mmM.......
    [up y=9]
    ...Mm......mm...

Section header options:

- `[down]`, `[left]`, `[right]`, `[up]`: the facing. A part without a
  `[right]` section uses its `[left]` grid mirrored.
- `[down/1]`: a grid for one walk pose only (0 = stand, 1 and 2 = steps).
  Without a pose number the grid is used for every pose.
- `y=N`: first row of the grid in the 16×16 frame (default 0), so a grid only
  needs the rows it covers. `x=N` shifts it sideways.
- `z=-1`: draw behind every part (capes and banners seen from the front).
  `z=1`: draw in front of every part (a cape seen from the back). Default 0
  keeps recipe order.

Symbols: `.` is transparent. A lower-case letter is the lit tone of a ramp and
the upper-case letter its shade.

| Symbol | Ramp | Symbol | Ramp |
|---|---|---|---|
| `s` `S` | skin | `m` `M` | metal |
| `h` `H` | hair | `c` `C` | cape |
| `a` `A` | outfit | `f` `F` | flag |
| `b` `B` | trim | `x` `X` | wood |
| `p` `P` | pants | `t` `T` | hat |
| `k` `K` | boots | `g` `G` | gold |
| `e` | eye (single colour) | `w` | white (single colour) |

Draw fills only: the script adds a 1 px outline (`outline` colour, default
`#141b1b`) around the finished figure.

To add a part, create the file, list it in a recipe's `parts` and rebuild.
The script stops with the file and line of any row that is not 16 characters
or uses an unknown symbol.

## Licence

The parts, recipes and generated sheets are original work for this project
and use the repository licence (`LICENSE.md`).
