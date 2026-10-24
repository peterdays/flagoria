# UI theme

`main_menu_theme.tres` styles the main menu: pixel font, button, line-edit and
slider styles, and a banded backdrop, all in the game palette.

## Hearts

The player's health row (top-left corner, one icon per heart, half-heart
steps) uses five 9x9 icons in `hearts/`:

| file | shown |
|---|---|
| `ui_heart_full.png` | a full heart |
| `ui_heart_half.png` | a half heart (split on the centre column) |
| `ui_heart_empty.png` | an empty heart |
| `ui_heart_flash_0.png`, `ui_heart_flash_1.png` | a heart that just lost health: flash 0, then flash 1, about 60 ms each, then the new state |

Layout: 1 px gap (10 px pitch), 4 px from the screen corner. The row is drawn
at a whole number of screen pixels per art pixel, even when the window
stretch is fractional. The flash is only on the HUD; the player's
invulnerability time and blink are separate.

To restyle the hearts, replace the PNGs (keep the names) or point the
`ICON_*` constants in `Scripts/hearts_hud.gd` at new files. That is the only
place the icons are referenced. The row lays out from the icon width.

## Credits

- Font: `NormalFont.ttf` from the Ninja Adventure asset pack
  (`art/Sprites/NinjaAdventure/HUD/Font/`), CC0 1.0 — see
  `art/Sprites/NinjaAdventure/LICENSE.txt`. Its import is set to
  non-antialiased, unhinted rendering so glyphs stay crisp at integer scale.
- Everything else in the theme (style boxes, gradients) is defined directly in
  the `.tres` file and is original to this project.
- Hearts: `hearts/ui_heart_*.png` are original pixel art made in-house for
  this project, drawn in code from text grids in the flagoria palette (1 px
  outline in the project ink colour `#2a2238`), with no third-party pixels.
  Repository licence (`LICENSE.md`).
