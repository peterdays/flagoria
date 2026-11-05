# Build placement

Interact-mode build picker and plank preview (#225). Entering interact mode
shows a small Cut / Plank icon row next to the mode button. Cut keeps the
existing tap, drag and chop behaviour. Plank snaps a drag to a horizontal or
vertical cell run, tints valid cells green and invalid cells red, shows the
wood cost (and a cheap refusal reason) near the finger, and on release places
the longest valid prefix through `ConstructionPlacer` (`can_place` / `cost` /
`place`). Wall and tower kinds are not in the picker yet. Ghost tiles wait on
art. Dead-player gating stays on `Interaction.player_dead`; multiplayer refuses
the same way the placer does.

Reach (`Interaction.REACH`) is the length bound for a drag preview; no separate
run-length cap was added (#380 item 1 left open).

## Sub-features

- `build-picker` Cut and Plank icons appear in interact mode, hide in combat,
  and switch `BuildPlacement.tool`.
- `build-plank-snap` a diagonal drag becomes a straight H or V cell run.
- `build-plank-preview` green/red cell tints, wood cost and refusal reason near
  the finger.
- `build-plank-place` release spends wood and writes the bridge through the
  placer; Cut mode still chops.

## How to get to it (user POV)

1. Start a local game (Host alone or offline).
2. Tap the mode button to enter interact mode; the Cut / Plank picker appears.
3. Tap Plank, drag across water next to land; green cells and the wood cost
   follow the finger. Lift to place.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_build_placement_snap_run`
under 0.05 s in `tools/verify.sh`; `test_build_picker_switches_tool` about 0.3 s;
`test_build_plank_preview_tint_and_cost` about 0.5 s;
`test_build_plank_places_and_spends` about 0.5 s; `test_build_cut_mode_unchanged`
about 0.4 s; `test_build_plank_drag_places` about 0.6 s (each ~2 s alone with
`--only=`, against ~1.7 s runner start-up). Screenshot drive about 15 s under
xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=build_placement_snap_run,build_picker_switches_tool,build_plank_preview_tint_and_cost,build_plank_places_and_spends,build_cut_mode_unchanged,build_plank_drag_places`, or the full `tools/verify.sh`.
- **Proof.** Headers `-- test_build_placement_snap_run`,
  `-- test_build_picker_switches_tool`,
  `-- test_build_plank_preview_tint_and_cost`,
  `-- test_build_plank_places_and_spends`,
  `-- test_build_cut_mode_unchanged` and
  `-- test_build_plank_drag_places` in `artifacts/verify.log` with no `FAIL`
  after them. Visual: `docs/screenshots/build_placement_preview.png` shows the
  picker and a green/red plank preview (captured under xvfb).

## Gotchas

- Placement must go through `ConstructionPlacer`; do not paint bridges from the
  UI layer.
- Do not invent a run-length cap for the preview; raise it as a question if
  REACH is not enough (#380).
