# Player spawn

Players spawn on walkable land from which they can reach at least 200 clear cells, so they never start in water or boxed in by trees.

## Sub-features

- `spawn-land` `resolve_player_spawn` (`Scripts/world/spawn_finder.gd`, called through `Scripts/TileMap.gd`) picks walkable land.
- `spawn-reachable` the spawn has 200+ reachable clear cells.
- `spawn-nodes` spawning a player finds every node it needs.

## How to get to it (user POV)

- Host on several seeds (Map Settings → Random seeds → Host with these).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_spawn_on_land`, `-- test_spawn_reachable`, `-- test_player_spawn_no_missing_nodes` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- `resolve_player_spawn` searches up to 96 cells from the origin and falls back to the candidate with the largest reachable area; a test that needs a specific spawn should pin the seeds, not the cell.
