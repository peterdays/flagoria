# Build placement

Interact-mode build picker and plank preview (#225). Entering interact mode
shows a small Cut / Plank icon row next to the mode button. Cut keeps the
existing tap, drag and chop behaviour. Plank snaps a drag to a horizontal or
vertical cell run. The preview greens exactly the cells `commit` will place
(the longest placeable prefix) and shows that wood cost; the rest of the drag
is red. A refusal reason appears only when nothing is placeable. On release,
placement goes through `ConstructionPlacer` (`can_place` / `cost` / `place`).
Wall and tower kinds are not in the picker yet. Ghost tiles wait on art.
Dead-player gating stays on `Interaction.player_dead`. While multiplayer is
on, the Plank icon is hidden so it never shows a cost for something that
cannot be placed. `update_preview` skips the snap / `can_place` work when the
snapped start and end cells have not moved. The Cut icon uses the AxeTool
sprite padded into `art/ui/ui_tool_cut.png`.

Reach (`Interaction.REACH`) is the length bound for a drag preview; no separate
run-length cap was added (#380 item 1 left open).

## Sub-features

- `build-picker` Cut and Plank icons appear in interact mode, hide in combat,
  and switch `BuildPlacement.tool`. Plank is hidden while multiplayer is on.
- `build-plank-snap` a diagonal drag becomes a straight H or V cell run.
- `build-plank-preview` green cells and cost match what commit places and
  charges; red for the rest of the drag; refusal only when nothing places.
- `build-plank-place` release spends wood and writes the bridge through the
  placer; Cut mode still chops.

## How to get to it (user POV)

1. Start a local game (Host alone or offline).
2. Tap the mode button to enter interact mode; the Cut / Plank picker appears.
3. Tap Plank, drag across water next to land; green cells and the wood cost
   follow the finger (green = what will place). Lift to place.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_build_placement_snap_run`
under 0.05 s in `tools/verify.sh`; `test_build_picker_switches_tool` about 0.3 s;
`test_build_plank_preview_tint_and_cost` about 0.5 s;
`test_build_plank_places_and_spends` about 0.5 s; `test_build_cut_mode_unchanged`
about 0.4 s; `test_build_plank_drag_places` about 0.6 s;
`test_build_preview_matches_commit_short_wood` about 0.2 s;
`test_build_preview_matches_commit_mid_invalid` about 0.2 s (each ~1.9 s alone
with `--only=`, against ~1.7 s runner start-up). Screenshot drive about 15 s
under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=build_placement_snap_run,build_picker_switches_tool,build_plank_preview_tint_and_cost,build_plank_places_and_spends,build_cut_mode_unchanged,build_plank_drag_places,build_preview_matches_commit_short_wood,build_preview_matches_commit_mid_invalid`, or the full `tools/verify.sh`.
- **Proof.** Headers `-- test_build_placement_snap_run`,
  `-- test_build_picker_switches_tool`,
  `-- test_build_plank_preview_tint_and_cost`,
  `-- test_build_plank_places_and_spends`,
  `-- test_build_cut_mode_unchanged`,
  `-- test_build_plank_drag_places`,
  `-- test_build_preview_matches_commit_short_wood` and
  `-- test_build_preview_matches_commit_mid_invalid` in `artifacts/verify.log`
  with no `FAIL` after them. Visual: `docs/screenshots/build_placement_preview.png`
  shows the picker and a green/red plank preview (captured under xvfb).

## Gotchas

- Placement must go through `ConstructionPlacer`; do not paint bridges from the
  UI layer.
- Preview green cells and cost must come from the same `longest_placeable`
  prefix that `commit` places; do not tint from a full-run `can_place`.
- Do not invent a run-length cap for the preview; raise it as a question if
  REACH is not enough (#380).
