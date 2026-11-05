# Build tower

Wooden palisade tower for 10 wood (#273). Interact mode shows a Tower icon
next to Cut and Plank. The tool previews the 3×3 `tower_wood` footprint under
the finger: all green and "10 wood" when `commit` will place, all red with a
refusal reason otherwise. On release, placement goes through
`ConstructionPlacer` (`BuildCosts.TOWER` → `StructurePlacer` writing
`structures/tower_wood.txt`). The builder owns the tower and its team flag so
`TowerCapture` can take it (#274). Land only; no overlap with structures,
players or mobs; unlimited count. While multiplayer is on, the Tower icon is
hidden (same gate as Plank). Placeholder tiles `TOWER_WOOD_POST` / `TOWER_WOOD_WALL`
and the picker icon come from `tools/art/gen_tower_wood_tiles.py`.

## Sub-features

- `build-tower-picker` Tower icon appears in interact mode with Cut / Plank,
  hides while multiplayer is on, and switches `BuildPlacement.tool` to Tower.
- `build-tower-preview` footprint cells and cost match what commit places and
  charges; red when refused (wrong ground, occupied, short wood, multiplayer).
- `build-tower-place` release spends 10 wood and writes `tower_wood` owned by
  the local peer; ConstructionPlacer refuses water, overlaps and multiplayer.

## How to get to it (user POV)

1. Start a local game (Host alone or offline) with at least 10 wood.
2. Tap the mode button to enter interact mode; the Cut / Plank / Tower picker
   appears.
3. Tap Tower, aim at clear land; the 3×3 footprint greens with "10 wood".
   Lift to place. The tower's flag takes the builder's colour.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_construction_placer_tower`
about 0.6 s in `tools/verify.sh` (~2.3 s alone with `--only=`);
`test_construction_placer_tower_atomic_spend` about 0.3 s (~2.0 s alone);
`test_build_picker_includes_tower` about 0.35 s (~2.0 s alone);
`test_build_tower_preview_matches_commit` about 0.5 s (~2.2 s alone);
`test_build_tower_tap_places` about 0.5 s (~2.2 s alone). Screenshot drive
about 15 s under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=construction_placer_tower,construction_placer_tower_atomic_spend,build_picker_includes_tower,build_tower_preview_matches_commit,build_tower_tap_places`, or the full `tools/verify.sh`.
- **Proof.** Headers `-- test_construction_placer_tower`,
  `-- test_construction_placer_tower_atomic_spend`,
  `-- test_build_picker_includes_tower`,
  `-- test_build_tower_preview_matches_commit` and
  `-- test_build_tower_tap_places` in `artifacts/verify.log` with no `FAIL`
  after them. Visual: `docs/screenshots/build_tower_preview.png` shows the
  Tower picker and a green footprint preview (captured under xvfb).

## Gotchas

- Placement must go through `ConstructionPlacer`; do not call
  `place_structure` from the UI layer.
- Preview green cells and cost must match what `commit` places; a short-wood
  or occupied footprint is all red with cost 0.
- Do not show the Tower icon while multiplayer is on; peer sync of placed
  towers is still #297 / #278.
