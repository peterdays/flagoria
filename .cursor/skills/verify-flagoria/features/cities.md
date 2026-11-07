# Cities

Drive: drives/cities.gd

A closed wall loop around a flag tower makes a city (#277). `Cities`
(`Scripts/mechanics/conquest/cities.gd`, the `World/Cities` node) flood-fills
from each placement's team flag through non-barrier cells. Barriers are
free-form walls and structure `WALL_*` / `PALISADE_*` cells (gates included).
Water and map edges do **not** close a city (design decision for #277): reaching
either means the region is open. A closed region with a flag tower becomes a
city owned by the tower's owner. Capturing the tower (#274) transfers the
city. Breaking the loop dissolves it. Boundary tint is drawn on the city
walls in the world; the minimap paints the same walls in the owner's colour.
Host alone only: while multiplayer is on the city list stays empty (sync is
#278). Tower ring cells (`TOWER_STONE_*`) are not barriers — a free-form or
stone/palisade ring must enclose them. Castle and guard_post use `WALL_*`, so
their own courtyards are cities.

## Sub-features

- `cities-closed-loop` a free-form wall ring around a wooden tower makes a
  city owned by the tower's owner; the ring is in wall cells and the flag is
  in the interior.
- `cities-open-loop` an incomplete ring around a wooden tower does not make a
  city; an enclosed guard_post does.
- `cities-capture-owner` `StructurePlacer.set_owner` on the city's tower makes
  `owner_of` follow the new owner.
- `cities-dissolve` erasing one free-form wall from a closed ring dissolves
  that city.
- `cities-water-escape` water and map edges are escapes, not barriers (design decision for #277); a U open to water does not make a city.
- `cities-off-in-multiplayer` while multiplayer is on the city list is cleared
  and stays empty.

## How to get to it (user POV)

1. Host alone. The starting castle courtyard is already a city (stone walls
   enclose the flag); its walls show a blue tint.
2. Build a free-form wall ring around a wooden tower until it closes: the
   ring tints and the minimap paints those walls. Open a gap and the tint
   goes away.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the six tests in
`tests/mechanics/conquest/test_cities.gd` take about 2.5 s together in
`tools/verify.sh` (~0.4 s each; ~2.5 s alone with `--only=` for all six,
against ~1.5 s for runner start-up). Drive about 20 s under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=cities_closed_loop_makes_city,cities_open_loop_does_not,cities_capture_changes_owner,cities_dissolve_when_loop_breaks,cities_water_does_not_close,cities_off_in_multiplayer`, or the full `tools/verify.sh`.
- **Drive (live).** `bin/launch.sh drives/cities.gd --display` (under xvfb). Steps `start`, `closed`, `open`, `minimap`: `start_game()`, settle, hide minimap for play shots, `snapshot("start")` (castle city tint), place a wooden tower + closed free-form ring, `snapshot("closed")`, erase one wall cell, `snapshot("open")`, show minimap, `snapshot("minimap")`, `done(true)`.
- **Proof.** Headers `-- test_cities_closed_loop_makes_city`, `-- test_cities_open_loop_does_not`, `-- test_cities_capture_changes_owner`, `-- test_cities_dissolve_when_loop_breaks`, `-- test_cities_water_does_not_close`, `-- test_cities_off_in_multiplayer` in `artifacts/verify.log` with no `FAIL` after them. Drive snapshots `01-start`, `02-closed`, `03-open`, `04-minimap` under `--display`.

## Gotchas

- Water and map edges do not close a city (design decision for #277).
- Tower ring cells are not barriers; only free-form walls and `WALL_*` /
  `PALISADE_*` structure cells are.
- Drive evidence closes the default-open MinimapPanel for play shots, then
  opens it for the minimap city-wall shot.
- While multiplayer is on, cities stay empty; peer sync is #278.
