# Customize HUD layout

Drive: drives/hud_customize.gd

The in-game menu has a Customize HUD entry. It opens an edit mode over the live touch controls: joystick, attack, run, Buildings, Map and Mode. Solo play pauses while editing; in multiplayer only the local layout changes. Drag moves a control; the size slider or a pinch resizes it between today’s size and 1.75×. Controls stay on screen and cannot overlap. The Buildings tool column opens above or below to fit. Save writes the layout to user settings on this device (not in world saves). Reset restores the default arc layout. Positions are stored relative to screen size.

## Sub-features

- `hud-customize-entry` Customize HUD sits in the in-game menu and opens edit mode (the drive opens the menu; headless saves use `-- test_hud_layout_round_trip`).
- `hud-customize-save` Save and load round-trip in user settings (`-- test_hud_layout_round_trip` in `tests/ui/test_hud_layout.gd`).
- `hud-customize-clamp` Off-screen positions clamp; overlaps are rejected (`-- test_hud_layout_clamp_overlap`).
- `hud-customize-reset` Reset clears the saved file and brings back HudToolRow defaults (`-- test_hud_layout_reset`).
- `hud-customize-edit-guard` In edit mode HUD buttons do not open map, buildings, mode, attack, run, or move the stick (`-- test_hud_layout_edit_blocks_map` and the drive tap on Map).

## How to get to it (user POV)

- Host a world. Open the in-game menu (top-right or Esc). Tap Customize HUD. Drag a control and adjust size. Save layout, then Done. Open the menu again and Reset to restore defaults.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: four `tests/ui/test_hud_layout.gd` cases are about 1.5 s in `tools/verify.sh`. The live drive is about 30 s under xvfb.

- **Run.** `./tools/verify.sh`, or `godot --headless --path . --script res://tests/run_tests.gd -- --only=hud_layout_round_trip,hud_layout_clamp_overlap,hud_layout_reset,hud_layout_edit_blocks_map`.
- **Proof.** Headers for the four `test_hud_layout_*` cases with no `FAIL` after them.
- **Drive (live).** `bin/launch.sh drives/hud_customize.gd --seed 49 --display`. Snapshots: `default-layout`, `edit-mode`, `moved-control` (attack and Map moved; edit bar clear of every control visual rect), `no-overlap`, `after-save-restart`, `reset-layout`.

## Gotchas

- Layout is local only; multiplayer peers keep their own saved positions.
- Until Save, changes apply for this session but are not written to disk.
- The minimap panel still auto-positions left of the arc; only the listed touch controls move.
