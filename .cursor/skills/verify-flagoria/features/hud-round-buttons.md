# Round HUD buttons

Drive: drives/hud_round_buttons.gd

The match starts with the wood minimap closed and the build list collapsed. Buildings, Map and Mode are round buttons on a quarter arc in the top-right corner, clear of the menu button and the wood counter. Each disc is 18 pixels, with a tap target of at least 24. Buildings opens Plank, Tower and Wall on the same discs in a column underneath; their icons are smaller so the disc and the gold ring stay visible, and each tap target is still at least 24. A second tap, or picking one, collapses the column. The picked tool keeps the gold ring. Map toggles the minimap, and the open panel sits left of the arc so it does not cover a button. Mode toggles attack and interact, and its icon follows the mode. Run sits beside the attack button, smaller than that button, and still holds, latches and follows Shift. Tower and Wall still hide while multiplayer is on. The icons are `assets/ui/hud/icon_buildings.png`, `icon_map.png`, `icon_run.png`, `icon_mode_attack.png` and `icon_mode_interact.png`.

## Sub-features

- `hud-round-arc` Buildings, Map and Mode sit in a top-right arc, each at least the round hit size, clear of the wood counter, the menu and each other. Run is a smaller neighbour of the attack button. `CanvasLayer1/MapReopen` is absent (`-- test_hud_round_buttons`).
- `hud-build-list` Buildings opens the column and a second tap closes it. Each entry is a round disc with the tool icon inside it. Picking a building selects that tool, collapses the list and keeps the gold ring (`-- test_hud_round_buttons`, `-- test_build_picker_switches_tool`).
- `hud-minimap-closed` the wood panel stays hidden until Map opens it, and a second press closes it. While it is open, every arc button sits outside the panel. Mode swaps the attack and interact icons (`-- test_hud_round_buttons`).

## How to get to it (user POV)

- Host a world. The arc is in the top-right and the minimap is closed. Tap Buildings to show Plank, Tower and Wall, tap Map to open the panel, and tap Mode to switch attack and chop. Run is the small button beside attack.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_hud_round_buttons` is about 0.8 s in `tools/verify.sh`. The live drive is about 25 s under xvfb.

- **Run.** `./tools/verify.sh`, or `godot --headless --path . --script res://tests/run_tests.gd -- --only=hud_round_buttons`.
- **Proof.** Header `-- test_hud_round_buttons` with no `FAIL` after it.
- **Drive (live).** `bin/launch.sh drives/hud_round_buttons.gd --seed 49 --display`. Snapshots: `match-start` (minimap closed, list collapsed), `building-list` (column of discs), `building-selected` (Plank's ring), `minimap` (panel open, arc clear of it), `interact` (interact icon, arc still clear).

## Gotchas

- Cut has no button. It is the tool while none of Plank, Tower or Wall is selected, and again after leaving interact mode.
- Collapse and maximize stay on the wood frame. Collapse hides the panel; Map opens it again.
- The wood panel sits left of the arc. With the minimap open, Buildings, Map and Mode each lie outside the panel rect. The drive checks that before the minimap and interact shots.
- The bright ring is the selected state. A darker face alone sits behind the icon and does not read as selected.
- The tap target is larger than the disc. The extra pixels are not drawn, and the three arc targets stay clear of each other and of the menu button.
- Replacing the four PNGs in `assets/ui/hud/` changes the icons with no code change. They import without mipmaps and the buttons draw them nearest-neighbour.
