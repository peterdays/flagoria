# Walls and bridges

Wall pieces are picked from their neighbours by `WallSolver` (`Scripts/mechanics/walls/wall_solver.gd`, stone `WALL_*` and wooden palisade `PALISADE_*`, which connect to each other). Plank bridges over water are laid by `build_bridge(from, to)` in `Scripts/TileMap.gd`, which forwards to `Scripts/mechanics/bridges/bridge_builder.gd`.

## Sub-features

- `wall-solve` each wall cell gets its piece (post, end, straight, corner, T, cross) from its N/E/S/W neighbours.
- `wall-collision` every stone and palisade piece blocks; an open gate leaves a 12 px gap for the player.
- `bridge-planks` `build_bridge` lays one straight run of planks over water; they stay when the chunk is drawn again, the hero walks across them, plain water still blocks, and a new map clears them.

## How to get to it (user POV)

- None on `main`: there is no in-game build action. The live drive is **verified-unreachable** until a build action lands (bridges #224; walls #270 and #276).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: each test below is under 0.5 s in `tools/verify.sh` (~1.1-1.3 s alone with `--only`).

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=wall_solver,wall_collision,bridge_planks`, or the full `tools/verify.sh`.
- **Proof.** Until a build action lands the proof is headless: each header `-- test_wall_solver`, `-- test_wall_collision`, `-- test_bridge_planks` appears in `artifacts/verify.log`, no `FAIL` line follows it, and the run ends with `All tests passed.`. A live drive reports **verified-unreachable: no in-game build action** (prerequisite: #224 for bridges, #270 and #276 for walls).

## Gotchas

- Never paint walls or planks from a drive to make it pass. A drive that can't reach a feature reports that, with the missing prerequisite.
- The only callers of `WallSolver` and `build_bridge` on `main` are tests (and the `TileMap.gd` wrapper).
