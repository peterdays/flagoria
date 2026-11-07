# Build tower

Drive: not player-facing

Wooden palisade tower for 10 wood (#273). Interact mode shows a Tower icon
next to Cut and Plank. The tool previews the 3×3 `tower_wood` footprint under
the finger: all green and "10 wood" when `commit` will place, all red with a
refusal reason otherwise. On release, placement goes through
`ConstructionPlacer` (`BuildCosts.TOWER` → `StructurePlacer` writing
`structures/tower_wood.txt`). The builder owns the tower and its team flag so
`TowerCapture` can take it (#274). Land only; no overlap with structures,
players or mobs; unlimited count. While multiplayer is on, the Tower icon is
hidden (same gate as Plank). The placed ring is `TOWER_STONE_*` (the centre
stays the team flag). The file still names `TOWER_WOOD_POST` / `TOWER_WOOD_WALL`
as the auto entries the solver replaces. The picker icon comes from
`tools/art/gen_tower_wood_tiles.py`.

## Sub-features

- `build-tower-picker` Tower icon appears in interact mode with Cut / Plank,
  hides while multiplayer is on, and switches `BuildPlacement.tool` to Tower.
- `build-tower-preview` footprint cells and cost match what commit places and
  charges; red when refused (wrong ground, occupied, short wood, multiplayer).
  A clear anchor beyond reach reports `out of reach`, not `occupied` (#386).
- `build-tower-cache` the placer lazily reads/parses `tower_wood.txt` once and
  reuses its read-only `Structure` for footprint, checks and placement across
  cell changes (#386). No per-cell file read, parse or name-regex compile;
  a new placer reads the file again. Other named structures are unchanged.
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
`test_build_tower_tap_places` about 0.5 s (~2.2 s alone).
`test_build_tower_out_of_reach` about 0.12 s (~2.6 s alone with `--only=`);
`test_construction_tower_cached` about 0.06 s (~2.6 s alone).
The two new tests add about 0.18 s to `tools/verify.sh`, not to netcode stress.
Staged screenshot harness about 3 s under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=construction_placer_tower,construction_placer_tower_atomic_spend,build_picker_includes_tower,build_tower_preview_matches_commit,build_tower_tap_places,build_tower_out_of_reach,construction_tower_cached`, or the full `tools/verify.sh`.
- **Proof.** Headers `-- test_construction_placer_tower`,
  `-- test_construction_placer_tower_atomic_spend`,
  `-- test_build_picker_includes_tower`,
  `-- test_build_tower_preview_matches_commit`,
  `-- test_build_tower_tap_places`, `-- test_build_tower_out_of_reach` and
  `-- test_construction_tower_cached` in `artifacts/verify.log` with no `FAIL`
  after them. The reach test also checks no wood is spent / no tower is placed
  on refusal, then moving into reach restores the green preview. The cache
  test checks identity across anchors and that placement leaves the definition
  unchanged.
- **Visual (staged, not an input-only drive).** Run
  `bin/drive-build-tower-screenshot.sh`: it sets up clear land and 10 wood,
  captures `docs/screenshots/build_tower_preview.png` (green footprint,
  "10 wood"), then moves the player beyond reach and captures
  `docs/screenshots/build_tower_out_of_reach.png` (red footprint,
  "out of reach"). This supplements the headless proof; it does not verify
  gathering wood or walking through the live player flow. There is no
  input-only tower drive yet (`Drive: not player-facing` above); the staged
  harness is the visual check, not a claim of end-to-end play.

## Gotchas

- Placement must go through `ConstructionPlacer`; do not call
  `place_structure` from the UI layer.
- Preview green cells and cost must match what `commit` places; a short-wood
  or occupied footprint is all red with cost 0.
- Do not show the Tower icon while multiplayer is on; peer sync of placed
  towers is still #297 / #278.
