# Building block pieces (WFC slice #23)

Drive: not player-facing

Modular building-block piece definitions for procedural structures: eight kinds (empty, floor, straight wall, wall corner, door, window, roof edge, roof fill) with cardinal edge sockets and TileCatalog art. Data lives in `data/building_blocks/*.tres` and `BuildingBlockCatalog` (`Scripts/mechanics/building_blocks/building_block_catalog.gd`). A debug scene at `debug/building_block_pieces.tscn` lays out every piece with socket labels.

## Sub-features

- `building-block-catalog` `BuildingBlockCatalog.adjacency_table()` and `socket_compatible()` feed the WFC solver (#24).
- `building-block-sockets` `tests/mechanics/building_blocks/test_building_block_sockets.gd` checks partners, symmetric compat, symmetric adjacency, and writes `docs/screenshots/building_block_pieces.png`.

## How to get to it (user POV)

- Editor: open `debug/building_block_pieces.tscn`.
- Tests: headless via `tools/verify.sh`.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: under 0.2 s in `tools/verify.sh`.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Header `-- test_building_block_sockets` with no following `FAIL` lines.