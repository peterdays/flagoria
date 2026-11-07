# Wall and tower junctions

Drive: drives/wall_junctions.gd

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
baked join piece. The first collar is drawn on `wall_caps` and the second on
`wall_caps_2`. A third or fourth side is still listed by the solver, but there
is no approved third layer and no baked tile, so it is not drawn. Caps have no
collision; the palisade underneath keeps its own. Removing a cell clears caps
that no longer apply, including on the cell that went away, and repaints every
result that changed, so a loop closing or opening flips inside and outside
corners that are not next to the edit.

## Sub-features

- `wall-junctions` straight, corner, T and cross palisades pick the mask piece
  and a collar on each stone side; two stone sides draw both collars; castle
  and guard-post corners solve as wall pieces; a tower ring keeps the centre
  flag and grows an arm toward a palisade; closing a loop flips a distant
  corner; removing the joining cell clears both collar layers. Save and load
  restore the same pieces.

## How to get to it (user POV)

Host alone. The starting castle's corners are connected wall pieces. Build a
wooden tower and run a palisade into it: the tower grows a stone arm and the
palisade gains a collar. A palisade with stone on two sides shows both
collars. Closing a wall loop turns distant outside corners into inside
corners; opening it turns them back and drops collars that no longer apply.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_wall_junctions` is
about 1 s in `tools/verify.sh` (~2.4 s alone with `--only=wall_junctions`,
against ~1.6 s for runner start-up). The drive is about 10 s under xvfb.
`test_wall_solver` still covers the mask table, and now also the collar list
(including three stone sides) and a tower cell closing an enclosure.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=wall_junctions,wall_solver`, or the full `tools/verify.sh`.
- **Drive (live).** `bin/launch.sh drives/wall_junctions.gd --display` (under xvfb, seed 11). Steps `castle`, `guard-post`, `joins`, `loop-open`, `loop-closed`, `caps-cleared`, `constrained`: `start_game()`, hide the minimap, read the solved castle corner, `snapshot("castle")`, place a guard post, `snapshot("guard-post")`, place two towers with a palisade between them plus straight, corner, T and cross joins, `snapshot("joins")`, place an open loop, `snapshot("loop-open")`, close it, `snapshot("loop-closed")`, remove the two-collar cell, `snapshot("caps-cleared")`, put it back, shrink the window to 854×480, `snapshot("constrained")`.
- **Proof.** `-- test_wall_junctions` and `-- test_wall_solver` in `artifacts/verify.log` with no `FAIL` after them. Drive snapshots `01-castle`, `02-guard-post`, `03-joins`, `04-loop-open`, `05-loop-closed`, `06-caps-cleared`, `07-constrained` under `--display`. The first six are the 1280×720 window; `constrained` is the 854×480 landscape window. No portrait shot.

## Gotchas

- The game window is landscape (480×270 viewport, 1280×720 by default). A constrained check uses the 854×480 landscape window, not a portrait one.
- Three or four collars on one cell are solved and stored. Only the first two, in N, E, S, W order, are drawn.
- `PALISADE_*_JOIN_*` cells stay in the atlas and are not selected.
- Tower ring cells are not city barriers. A tower still needs a free-form or stone loop around it to make a city.
- Placements and free-form walls are still host-alone; joining peers get the lists with the map and solve them locally. No new net message.
