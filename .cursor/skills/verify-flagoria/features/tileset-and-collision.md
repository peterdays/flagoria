# Tileset and collision

The world map uses tileset v3.1 through named tiles. Water, and rows of trees or bushes, block movement.

## Sub-features

- `tiles-catalog` every tile is looked up by name through `TileCatalog` (`Scripts/tile_catalog.gd`; inventory in `docs/tiles.md`).
- `tiles-water` cells that are not walkable land have collision.
- `tiles-forest-walls` adjacent trees or bushes form a wall.
- `tiles-no-deco-on-water` no trees or flowers on water.
- `tiles-chunks` chunk refresh cadence (`chunk_refresh_frames`).

## How to get to it (user POV)

- Host and walk into water or a tree line.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_tile_catalog`, `-- test_water_blocks_player`, `-- test_forest_walls`, `-- test_no_decorations_on_water`, `-- test_flowers`, `-- test_chunk_refresh_frames` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- A tile used in `Scripts/` but missing from `TileCatalog.TILES` fails `test_tile_catalog`; add it to the catalog rather than using raw atlas coords.
