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

## Menu button

The in-game menu button (top-right corner of the HUD) shows
`ui_menu_icon.png`: an 11x11 three-bar icon, bars in the button text colour
with a 1 px ink shadow like the theme's labels. The button is an 18 px
square (48 screen px at 1280x720) using the theme's button styles.

## Mode button

The mode button, just left of the menu button and the same 18 px square,
switches between combat and interact mode. It shows the current mode:
`ui_mode_combat.png` (a sword) or `ui_mode_interact.png` (an axe), 11x11
icons in the menu icon's style, and looks pressed in interact mode.

## Resource counter

The wood counter (top centre of the HUD) shows `ui_wood_icon.png`, a 9x9
log end-on, followed by the count. It uses the hearts' pixel scale and top
margin, so the two rows line up.

## Map panel

The explored map in play is a wood panel in the top-right corner, below the
mode and menu buttons, 4 px from the right edge (224x144 at (252, 28) in the
480x270 UI space). It uses the files in `map/`:

| file | size | shown |
|---|---|---|
| `ui_map_panel_open.png` | 224x144 | the wood frame; its map window is the transparent 216x124 area at (4, 16) |
| `ui_map_marker_hero_{up,right,down,left}.png` | 16x16 | the local hero, pointing the way it faces; pixel (8, 8) sits on the hero's cell |

The window shows the world at 2 px per cell, centred on the hero. Explored
cells use the map colours in `Scripts/minimap_panel.gd` (water, shore,
sand, swamp, grass, trees, stones, flowers), with a 1 px ink line where
explored land meets explored water. Cells nobody has been near show as mist,
a 1 px dither of `#ffffff` and `#d9e6f2`. The panel is drawn at a whole
number of screen pixels per art pixel, rounding down, so at fractional
window stretches it stays clear of the attack button.

## Touch controls

The move stick and the attack button use the Castle Stone UI set in `touch/`.
Positions are in the 480x270 UI space, at scale 1.

| file | size | shown |
|---|---|---|
| `ui_joystick_base.png` | 56x56 | the stick base, centred on (77, 201); a drag may start within 28 px |
| `ui_joystick_knob.png` | 24x24 | the knob, travel 20 px from the centre |
| `ui_joystick_knob_active.png` | 24x24 | the knob while a finger drags the stick |
| `ui_attack_idle.png` | 40x40 | the attack button, centred on (398, 202), hit circle radius 24 |
| `ui_attack_pressed.png` | 40x40 | a finger on the button, inside the aim dead zone |
| `ui_attack_aim.png` | 40x40 | that finger dragged past the dead zone: aiming |

The textures are set on the `player_joystick` (`border`, `stick`,
`stick_active`) and `TouchScreenButton` (`texture_idle`, `texture_down`,
`texture_aim`) nodes in `flagoria_main.tscn`. The aim cone is drawn in code;
its colours, pulse and line widths are the `AimConeStyle` resource
(`Scripts/aim_cone_style.gd`).

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
- Menu icon: `ui_menu_icon.png` is original pixel art made in-house for this
  project, drawn in code in the theme palette. Repository licence
  (`LICENSE.md`).
- Wood icon: `ui_wood_icon.png` is original pixel art made in-house for this
  project, drawn in code in the flagoria palette. Repository licence
  (`LICENSE.md`).
- Mode icons: `ui_mode_combat.png` and `ui_mode_interact.png` are original
  pixel art made in-house for this project, drawn in code in the theme
  palette. Repository licence (`LICENSE.md`).
- Touch controls: `touch/ui_*.png` (Castle Stone UI set) are original pixel
  art made in-house for this project, drawn in code in the flagoria palette.
  Repository licence (`LICENSE.md`).
- Map panel: `map/ui_map_*.png` are original pixel art made in-house for this
  project, drawn in code in the flagoria palette. Repository licence
  (`LICENSE.md`).
