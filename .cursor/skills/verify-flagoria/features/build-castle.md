# Build castle

Drive: drives/build_castle.gd

Interact-mode Castle tool places an extra `structures/castle.txt` footprint for
50 wood (#527). The preview greens the full rotated footprint and charges
50 wood when `commit` will place. On release, placement goes through
`ConstructionPlacer` (`BuildCosts.CASTLE` → `StructurePlacer`). The builder
owns the castle and its team flag. Land only; no overlap with structures,
players or water. Rotation follows #493. In multiplayer the host validates and
syncs through `StructureRequests` (#527), including late joiners and world saves.

## Sub-features

- `build-castle-picker` Castle button appears in the Buildings column with
  Plank, Tower and Wall, stays visible while multiplayer is on, and switches
  `BuildPlacement.tool` to Castle.
- `build-castle-place` release spends 50 wood and writes `castle` owned by the
  local peer; refused water, overlap or short wood spends nothing.
- `build-castle-sync` a client request syncs owner, anchor and rotation to the
  host, connected peers and a late joiner.
- `build-castle-save` a placed castle with rotation survives save and reload.
- `build-castle-land-score` a placed castle's team flag is a LandScore tower like
  the start castle and adds covered land (#279).

## How to get to it (user POV)

1. Host alone or two-player with at least 50 wood.
2. Open Buildings, tap Castle, rotate if needed, aim at clear land.
3. Lift to place; the flag uses the builder's colour.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_construction_placer_castle`
about 0.8 s in `tools/verify.sh`; `test_build_castle_land_score_flag` about 0.5 s;
`test_build_castle_save_round_trip` about 1.2 s;
`test_castle_build_two_players` about 6–12 s per stress run. Drive about 25–45 s
under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=construction_placer_castle,build_castle_land_score_flag,build_castle_save_round_trip,castle_build_two_players`, or the full `tools/verify.sh`.
- **Proof.** `PASS test_construction_placer_castle`, `PASS test_build_castle_land_score_flag`, `PASS test_build_castle_save_round_trip`, and `PASS test_castle_build_two_players` with no `FAIL` after them.
- **Drive (live).** `bin/launch.sh drives/build_castle.gd --seed 7 --display`.

## Gotchas

- Placement must go through `ConstructionPlacer`; do not call `place_structure`
  from the UI layer.
- `BuildCosts.START_CASTLE` is only the free spawn castle via `place_start_castle`,
  not the build-picker Castle kind (`BuildCosts.CASTLE`).
- Peer sync uses `apply_structure` with structure name `castle`, same as joins (#278).