# Structure placement

A parsed structure file can be placed on the generated map at an anchor cell. `StructurePlacer` (`Scripts/mechanics/structures/structure_placer.gd`, owned by `Scripts/TileMap.gd`) checks the footprint, writes the ground and object cells, picks wall and gate pieces with `WallSolver`, sets the team flag, and records the placement so `generate_chunk` draws it again after a redraw. Only a host that is still alone places; callers in game are the [starting castle](./start-castle.md) and the buildable wooden tower (#273 / [build-tower](./build-tower.md)). A peer that joins gets the host's placements with the map (`receive_map_params`, after the cuts) and draws them before its player is placed; placements made after a join do not reach peers yet (rest of #278).

## Sub-features

- `structure-place` `can_place_structure(structure, anchor_cell)` returns no reasons on a clear spot; `place_structure(structure, anchor_cell, owner)` returns a placement id, the cells show the structure's ground, solved walls, gate and flag, walls collide and the flag does not, `predict_cell` matches the drawn cells, and `placed_structures()` lists the id with name, owner and anchor. A redraw keeps it; a new map clears it.
- `structure-place-stump` a structure placed over a stump drops the cut, so a later regrowth tick regrows nothing there and the structure stays drawn.
- `structure-join-sync` a host places a guard post while alone; a client that joins holds the same `placed_structures()` and every footprint cell predicts, draws and collides as on the host. The client's own `can_place_structure` says `multiplayer on`, and a forged `receive_map_params` from another client is refused with an engine error and changes nothing.
- `structure-place-refused` each refusal reason (`water`, `tree`, `bush`, `out of map`, `overlaps another structure`, `overlaps a player`, `multiplayer on`) is returned, `place_structure` returns `-1`, and no cell changes.

## How to get to it (user POV)

- Through the [starting castle](./start-castle.md) on spawn, and through interact-mode Tower in the build picker (#273 / [build-tower](./build-tower.md)).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: about 0.3 s per test in `tools/verify.sh` (~1.7 s each alone with `--only=`, against ~1.4 s for runner start-up); `test_structure_place_over_stump` about 0.2 s. `test_structure_sync_join` (`tests/net/test_structure_sync.gd`, host and two clients as `tests/cut_sync_probe.gd` processes) takes about 3.3 s alone, so about 2 s in `tools/verify.sh`, and runs 20 times in the Netcode stress job.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_structure_place`, `-- test_structure_place_refused`, `-- test_structure_place_over_stump` and `-- test_structure_sync_join` with no `FAIL` after them.
- **Drive (live).** Host from the main menu: the starting castle is a placed structure. Join that host from a second instance: the castle's walls block the joiner too.
