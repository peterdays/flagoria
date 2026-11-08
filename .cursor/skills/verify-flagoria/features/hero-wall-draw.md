# Hero in front of walls

Drive: drives/hero_wall_draw.gd

A wall tile is drawn above the hero (`World/worldMap` layer 1 is z 1, wall caps are z 2 through 5). The hero's body is 16 px tall and reaches up into that tile, so the head used to disappear behind the wall while the hero was still standing in front of it.

`Scripts/player.gd` measures how much of that body rect lies on a `WALL_`, `PALISADE_` or `TOWER_STONE_` cell, including an open gate's lintel. Under about two thirds, the hero's `z_index` is one above the upper cap layer, so the whole sprite, head included, draws over the wall. At or above two thirds, `z_index` drops to 0 and the wall draws over the hero. Open ground stays at 0, so trees still draw over the hero.

## Sub-features

- `hero-wall-front` standing against a wall with only the head on the tile keeps the hero above the wall.
- `hero-wall-inside` once about two thirds of the body is on the wall, the wall covers the hero.

## How to get to it (user POV)

Host a world. The hero starts outside the castle gate, in front of the south wall. The head is in front of the stone, not behind it.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `-- test_hero_draws_over_wall_face` is about 0.3 s in `tools/verify.sh` (~1.5 s alone with `--only=`). The live drive is about 4 s with `--display`.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=hero_draws_over_wall_face`.
- **Drive (live).** `bin/launch.sh drives/hero_wall_draw.gd --seed 49 --display`. Steps `in-front`, `constrained`: `start_game()`, `snapshot("in-front")` at 1280×720, shrink to 854×480, `snapshot("in-front-constrained")`. The hero's `z_index` is one above the top wall-cap layer. No portrait shot.
- **Proof.** `01-in-front.png` and `02-in-front-constrained.png` show the hero's head in front of the castle wall. The drive fails if `z_index` is not above the caps.

## Gotchas

- The check uses the 16 px walk body, not the wider chop sheet, so an axe over a wall does not by itself push the hero behind it.
- An open gate still counts: its lintel is a wall tile, and the hero starts in that opening.
