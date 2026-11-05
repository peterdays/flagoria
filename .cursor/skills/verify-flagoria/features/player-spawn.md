# Player spawn

Drive: not player-facing

Players spawn on walkable land from which they can reach at least 200 clear cells, so they never start in water or boxed in by trees.

## Sub-features

- `spawn-land` `resolve_player_spawn` (`Scripts/world/spawn_finder.gd`, called through `Scripts/TileMap.gd`) picks walkable land.
- `spawn-reachable` the spawn has 200+ reachable clear cells.
- `spawn-nodes` spawning a player finds every node it needs.
- `spawn-free-spot` each player gets its own clear walkable spot within `SPAWN_RADIUS` (64 px) of the spawn point, at least `SPAWN_CLEARANCE` (16 px) from every other player, on join and on respawn (#164). The search walks at least `SPAWN_SEARCH_LIMIT` (400) clear cells and keeps going outward when every spot is taken.
- `spawn-late-join` the server picks each joiner's spot; the joiner stands on it once the map arrives.

## How to get to it (user POV)

- Host on several seeds (Map Settings → Random seeds → Host with these).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `-- test_spawn_late_join` starts one Godot process per joiner on a dedicated server and on a listen host, ~12 s alone with `--only=` (each check waits up to 10 s for every peer's copies to match their owners); the other spawn tests together ~1.8 s.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_spawn_on_land`, `-- test_spawn_reachable`, `-- test_player_spawn_no_missing_nodes`, `-- test_spawn_radius_no_overlap`, `-- test_spawn_full_area_searches_outward`, `-- test_spawn_late_join` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- `resolve_player_spawn` searches up to 96 cells from the origin and falls back to the candidate with the largest reachable area; a test that needs a specific spawn should pin the seeds, not the cell.
