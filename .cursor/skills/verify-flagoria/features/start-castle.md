# Starting castle

Drive: not player-facing

Each player starts with one castle (#271): `structures/castle.txt`, a walled courtyard with an open gate in its bottom wall and the team flag as its main tower (placeholder tiles until castle art exists). `StartCastle` (`Scripts/world/start_castle.gd`, called through `Scripts/TileMap.gd` `place_start_castle`) places it with `StructurePlacer` next to the spawn, and the land outside its gate becomes the player spawn. Placed by the host while alone, like every placement: a host that plays places its castle in `flagoria_main.gd` `setup_server` before the mobs and before any peer joins; a dedicated server places none. A peer that joins gets the castle with the map (`receive_map_params`, #365) before its player is placed, so its walls block on both peers.

## Sub-features

- `castle-placed` hosting on seeds 11, 42 and 99 places one castle, owned by peer 1, with walkable ground, an open gate, the blue team flag, clear land on both sides of the gate, and at least `SPAWN_MIN_REACHABLE` (200) clear cells reachable from outside the gate with the castle in the way.
- `castle-spawn` the player spawns on the cell outside the gate; `resolve_player_spawn` and the respawn spot (`player.spawn_position()`) return it.
- `castle-gate-fit` the player's collision body, moved with a physics move check, walks from the gate front through the open gate into the courtyard without a collision, and a step from the gate into the wall beside it collides.
- `castle-search` the spot is the nearest gate front to the original spawn (ties by y, then x) within `SEARCH_RADIUS` (32) cells where `can_place_structure` gives no reason; when the nearest spot is taken it moves outward. With no spot the spawn is unchanged and there is no castle.
- `castle-dedicated` a dedicated server places no castle.
- `castle-join-sync` a host on seed 7 starts through `setup_server` and places its castle; a client that joins holds the same castle placement, every footprint cell predicts, draws and collides as on the host, and the joiner spawns next to the gate front (the host's player stands on it), on a clear cell outside the walls on both peers and where the host sees it.

## How to get to it (user POV)

- Main menu → Host. The player starts just below the castle gate and can walk into the courtyard.
- A second instance: Main menu → Join that host. The joiner starts beside the gate and the castle walls block it as they block the host.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_start_castle` about 0.8 s in `tools/verify.sh` (~2.3 s alone with `--only=start_castle`, against ~1.5 s for runner start-up; the gate-fit check adds no measurable time). `test_castle_sync_join` (`tests/net/test_structure_sync.gd`, host and client as `tests/cut_sync_probe.gd` processes) takes about 2.8 s alone, so about 1.3 s in `tools/verify.sh`, and runs 20 times in the Netcode stress job.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_start_castle` and `-- test_castle_sync_join` with no `FAIL` after them.
- **Drive (live).** Host from the main menu and check the player stands outside the castle gate; join from a second instance and check the joiner cannot walk through the walls.

## Gotchas

- The castle reaches a peer only when it joins; placements made after a join do not sync yet (rest of #278). It is not saved yet either; reloading a saved world places it again from the restored map (#42).
