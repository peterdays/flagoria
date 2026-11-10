# Round HUD buttons

Drive: drives/hud_round_buttons.gd

The match starts with the wood minimap closed. Under the wood counter, one row of round buttons replaces the old minimap chip: Run, then Plank, Tower, Wall, the minimap, and attack/interact. Plank, Tower and Wall select that build tool and do not change combat or interact by themselves. The minimap button opens and closes the wood panel. The mode button still switches attack and chop. Run keeps its hold, its tap latch and the Run / RUN label. Tower and Wall still hide while multiplayer is on. The wood panel and the parchment sheet stay as they are.

## Sub-features

- `hud-round-row` Plank, Tower, Wall, the minimap and attack/interact are round and visible under the wood counter, with Run in the same row, and `CanvasLayer1/MapReopen` is absent (`-- test_hud_round_buttons`).
- `hud-minimap-closed` the wood panel stays hidden until the minimap button opens it, and a second press closes it (`-- test_hud_round_buttons`).
- `hud-build-select` each building button selects that tool. Entering interact keeps the tool; leaving interact returns to Cut (`-- test_hud_round_buttons`, `-- test_build_picker_switches_tool`).

## How to get to it (user POV)

- Host a world. The row is under the wood count and the minimap is closed. Tap Plank, Tower or Wall to select that tool, tap the map button to open the panel, and tap the sword or axe button to switch attack and chop.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_hud_round_buttons` is about 0.5 s in `tools/verify.sh`. The live drive is about 20 s under xvfb.

- **Run.** `./tools/verify.sh`, or `godot --headless --path . --script res://tests/run_tests.gd -- --only=hud_round_buttons`.
- **Proof.** Header `-- test_hud_round_buttons` with no `FAIL` after it.
- **Drive (live).** `bin/launch.sh drives/hud_round_buttons.gd --seed 49 --display`. Snapshots: `match-start` (minimap closed, round buttons), `plank`, `tower`, `wall`, `minimap` (panel open).

## Gotchas

- Cut has no button. It is the tool while none of Plank, Tower or Wall is selected, and again after leaving interact mode.
- Collapse and maximize stay on the wood frame. Collapse hides the panel; the round minimap button opens it again.
- The row shifts left of the wood panel when a centred row would sit under it, so the open panel does not cover the buttons.
