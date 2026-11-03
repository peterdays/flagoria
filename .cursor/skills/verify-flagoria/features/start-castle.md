# Starting castle

Each player starts with one castle (#271): `structures/castle.txt`, a walled courtyard with an open gate in its bottom wall and the team flag as its main tower (placeholder tiles until castle art exists). `StartCastle` (`Scripts/world/start_castle.gd`, called through `Scripts/TileMap.gd` `place_start_castle`) places it with `StructurePlacer` next to the spawn, and the land outside its gate becomes the player spawn. Host alone only, like every placement: a host that plays places its castle in `flagoria_main.gd` `setup_server` before the mobs and before any peer joins; a dedicated server places none, and joining peers get none until placements sync (#278).

## Sub-features

- `castle-placed` hosting on seeds 11, 42 and 99 places one castle, owned by peer 1, with walkable ground, an open gate, the blue team flag, clear land on both sides of the gate, and at least `SPAWN_MIN_REACHABLE` (200) clear cells reachable from outside the gate with the castle in the way.
- `castle-spawn` the player spawns on the cell outside the gate; `resolve_player_spawn` and the respawn spot (`player.spawn_position()`) return it.
- `castle-search` the spot is the nearest gate front to the original spawn (ties by y, then x) within `SEARCH_RADIUS` (32) cells where `can_place_structure` gives no reason; when the nearest spot is taken it moves outward. With no spot the spawn is unchanged and there is no castle.
- `castle-dedicated` a dedicated server places no castle.

## How to get to it (user POV)

- Main menu → Host. The player starts just below the castle gate and can walk into the courtyard.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: about 1.0 s in `tools/verify.sh` (~2.5 s alone with `--only=start_castle`, against ~1.5 s for runner start-up).

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Header `-- test_start_castle` with no `FAIL` after it.
- **Drive (live).** Host from the main menu and check the player stands outside the castle gate.

## Gotchas

- The castle is placed before peers join and is not synced yet, so a peer that joins later does not see it (#278). It is not saved yet either; reloading a saved world places it again from the restored map.
