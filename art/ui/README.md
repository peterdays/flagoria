# UI theme

`main_menu_theme.tres` styles the main menu: pixel font, button, line-edit and
slider styles, and a banded backdrop, all in the game palette.

## Hearts (placeholder)

`hearts/heart_full.png`, `heart_half.png` and `heart_empty.png` are 8x8
placeholder icons for the player's health row (top-left corner, one icon per
heart, half-heart steps). They are drawn from the text grids in
`hearts/hearts_8.txt` with colours from the Ninja Adventure palette:

    python3 tools/ui/make_hearts.py

To swap in final art, replace the three PNGs (keep the names, any square
size) or point the `ICON_FULL`, `ICON_HALF` and `ICON_EMPTY` constants in
`Scripts/hearts_hud.gd` at new files. That is the only place the icons are
referenced. The row lays out from the icon width, so larger icons only need
a new `SPACING` if the gap should change.

## Credits

- Font: `NormalFont.ttf` from the Ninja Adventure asset pack
  (`art/Sprites/NinjaAdventure/HUD/Font/`), CC0 1.0 — see
  `art/Sprites/NinjaAdventure/LICENSE.txt`. Its import is set to
  non-antialiased, unhinted rendering so glyphs stay crisp at integer scale.
- Everything else in the theme (style boxes, gradients) is defined directly in
  the `.tres` file and is original to this project.
