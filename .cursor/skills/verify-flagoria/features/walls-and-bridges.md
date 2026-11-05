# Walls and bridges

Drive: not player-facing

Wall pieces are picked from their neighbours by `WallSolver` (`Scripts/mechanics/walls/wall_solver.gd`, stone `WALL_*` and wooden palisade `PALISADE_*`, which connect to each other). Plank bridges over water are laid by `build_bridge(from, to)` in `Scripts/TileMap.gd`, which forwards to `Scripts/mechanics/bridges/bridge_builder.gd`. Play and the shared module place them through `ConstructionPlacer` (`construction-placement.md`). Free-form palisade walls in play are [Free-form walls](./free-form-walls.md) (#276). Closed loops around a flag tower become cities ([Cities](./cities.md), #277).

## Sub-features

- `wall-solve` each wall cell gets its piece (post, end, straight, corner, T, cross) from its N/E/S/W neighbours.
- `wall-collision` every stone and palisade piece blocks; an open gate leaves a 12 px gap for the player.
- `bridge-planks` `build_bridge` lays one straight run of planks over water; they stay when the chunk is drawn again, the hero walks across them, plain water still blocks, and a new map clears them.

## How to get to it (user POV)

- Plank bridges: interact mode → Plank (#225 / `build-placement.md`). Walls stay **verified-unreachable** until #276.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: each test below is under 0.5 s in `tools/verify.sh` (~1.1-1.3 s alone with `--only`).

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=wall_solver,wall_collision,bridge_planks`, or the full `tools/verify.sh`.
- **Proof.** Until a build action lands the proof is headless: each header `-- test_wall_solver`, `-- test_wall_collision`, `-- test_bridge_planks` appears in `artifacts/verify.log`, no `FAIL` line follows it, and the run ends with `All tests passed.`. Live plank bridges go through the build picker (`build-placement.md`). Free-form walls are reachable through the build picker; see [Free-form walls](./free-form-walls.md).

## Gotchas

- Never paint walls or planks from a drive to make it pass. A drive that can't reach a feature reports that, with the missing prerequisite.
- The only play path for planks is `ConstructionPlacer`; tests may still call `build_bridge` directly to check the tiles.
