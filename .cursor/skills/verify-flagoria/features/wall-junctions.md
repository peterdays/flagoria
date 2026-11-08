# Wall and tower junctions

Drive: drives/wall_collar_sides.gd

Free-form palisades, castle and guard-post walls, and the wooden tower's ring
are solved together (`WallSolver`, `WallBuilder.resolve`). A cell's piece comes
from the N=1, E=2, S=4, W=8 mask: post, end, straight, outside corner, T or
cross. An outside corner becomes the inside corner when the cell along both
arms is outside every enclosure and the cell on the other side of the bend is
enclosed. Castle and guard-post corners are ordinary auto wall cells, so they
come out as corners (or a T or cross once a palisade attaches). Tower ring
cells count as stone neighbours. The centre cell stays the team flag.

A palisade that touches stone (`WALL_*` or `TOWER_STONE_*`) gets a
`CAP_COLLAR_*` overlay for every such side, in N, E, S, W order, instead of a
baked join piece. The collars are drawn on `wall_caps`, `wall_caps_2`,
`wall_caps_3` and `wall_caps_4`, one existing piece per side, so three and four
stone sides all show. Caps have no collision; the palisade underneath keeps
its own. Removing a cell clears every cap layer; placing it again restores
them. A loop closing or opening still repaints distant inside and outside
corners.

## Sub-features

- `wall-junctions` straight, corner, T and cross palisades pick the mask piece
  and a collar on each stone side; two stone sides draw both collars; castle
  and guard-post corners solve as wall pieces; a tower ring keeps the centre
  flag and grows an arm toward a palisade; closing a loop flips a distant
  corner; removing the joining cell clears the collar layers. Save and load
  restore the same pieces.
- `wall-collar-sides` three stone sides draw three collars and a fourth side
  adds the fourth; removing the palisade clears all four layers and placing
  it again restores them. One- and two-side cells still use only the first
  layers.

## How to get to it (user POV)

Host alone. The starting castle's corners are connected wall pieces. Build a
wooden tower and run a palisade into it: the tower grows a stone arm and the
palisade gains a collar. A palisade with stone on two, three or four sides
shows a collar on every one of those sides. Removing that palisade clears the
collars; placing it again brings them back.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_wall_junctions` is
about 1 s in `tools/verify.sh`. `test_wall_collar_sides` adds about 0.5 s
(~2 s alone with `--only=wall_collar_sides`, against ~1.6 s for runner
start-up). The collar-sides drive is about 10 s under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=wall_collar_sides,wall_junctions,wall_solver`, or the full `tools/verify.sh`.
- **Drive (live).** `bin/launch.sh drives/wall_collar_sides.gd --display` (under xvfb, seed 11). Steps `three`, `four`, `removed`, `readded`, `constrained`: `start_game()`, hide the minimap, place three towers around a palisade, `snapshot("three")`, place the fourth tower, `snapshot("four")`, erase the palisade, `snapshot("removed")`, place it again, `snapshot("readded")`, shrink the window to 854×480, `snapshot("constrained")`. `drives/wall_junctions.gd` still covers the one- and two-side gallery.
- **Proof.** `-- test_wall_collar_sides`, `-- test_wall_junctions` and `-- test_wall_solver` in `artifacts/verify.log` with no `FAIL` after them. Drive snapshots `01-three`, `02-four`, `03-removed`, `04-readded`, `05-constrained` under `--display`. The first four are the 1280×720 window; `constrained` is the 854×480 landscape window. No portrait shot.

## Gotchas

- The game window is landscape (480×270 viewport, 1280×720 by default). A constrained check uses the 854×480 landscape window, not a portrait one.
- Every stone side draws one existing `CAP_COLLAR_*`. A cell has at most four orthogonal sides, so four cap layers cover the list.
- `PALISADE_*_JOIN_*` cells stay in the atlas and are not selected.
- Tower ring cells are not city barriers. A tower still needs a free-form or stone loop around it to make a city.
- Placements and free-form walls are still host-alone; joining peers get the lists with the map and solve them locally. No new net message.
