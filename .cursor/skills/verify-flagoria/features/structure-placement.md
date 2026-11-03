# Structure placement

A parsed structure file can be placed on the generated map at an anchor cell. `StructurePlacer` (`Scripts/mechanics/structures/structure_placer.gd`, owned by `Scripts/TileMap.gd`) checks the footprint, writes the ground and object cells, picks wall and gate pieces with `WallSolver`, sets the team flag, and records the placement so `generate_chunk` draws it again after a redraw. Host alone only; peer sync is a later step (#278). The [starting castle](./start-castle.md) is its first caller in game.

## Sub-features

- `structure-place` `can_place_structure(structure, anchor_cell)` returns no reasons on a clear spot; `place_structure(structure, anchor_cell, owner)` returns a placement id, the cells show the structure's ground, solved walls, gate and flag, walls collide and the flag does not, `predict_cell` matches the drawn cells, and `placed_structures()` lists the id with name, owner and anchor. A redraw keeps it; a new map clears it.
- `structure-place-stump` a structure placed over a stump drops the cut, so a later regrowth tick regrows nothing there and the structure stays drawn.
- `structure-place-refused` each refusal reason (`water`, `tree`, `bush`, `out of map`, `overlaps another structure`, `overlaps a player`, `multiplayer on`) is returned, `place_structure` returns `-1`, and no cell changes.

## How to get to it (user POV)

- Only through the [starting castle](./start-castle.md): no menu, key or build mode places a structure yet.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: about 0.3 s per test in `tools/verify.sh` (~1.7 s each alone with `--only=`, against ~1.5 s for runner start-up); `test_structure_place_over_stump` about 0.2 s.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_structure_place`, `-- test_structure_place_refused` and `-- test_structure_place_over_stump` with no `FAIL` after them.
- **Drive (live).** Host from the main menu: the starting castle is a placed structure.
