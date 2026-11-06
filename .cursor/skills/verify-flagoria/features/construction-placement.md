# Construction placement

Drive: not player-facing

Shared placement for every buildable (#296). `ConstructionPlacer`
(`Scripts/mechanics/building/construction_placer.gd`) checks a kind on a list
of cells, reports the wood cost, and places through `BuildCosts.buy` into the
kind's writer. Registered kinds: the plank bridge (a straight water run that
touches land or an existing plank, written by `TileMap.build_bridge` /
`BridgeBuilder`), the wooden tower (#273: one land anchor, 3×3
`tower_wood` through `StructurePlacer`), and free-form wall blocks (#276:
land cells, 2 wood each, written by `TileMap.place_wall_cells` /
`WallBuilder`).
The placement UI (#225) only talks to this module.

Refusal reasons (each at most once): `empty cells`, `unknown kind`,
`wrong ground`, `occupied`, `not straight`, `not adjacent`, `not enough wood`,
`multiplayer on`. A floating water cell with no land or plank neighbour is
`not adjacent` (2026-11-02: no floating planks).

Plank bridges sync between peers (#297): `can_place` / `place` allow planks
while multiplayer is on. Towers and walls still refuse with `multiplayer on`
until #278.

## Sub-features

- `construction-plank` a straight water run next to land or a plank places and
  spends one wood per cell; land, an existing plank, a bent run, a floating
  cell and too little wood are refused with a reason and spend nothing.
  Planks place while multiplayer is on (#297).
- `construction-tower` a clear land anchor places `tower_wood` for 10 wood,
  owned by the local peer; water, an overlapping structure/player/mob, short
  wood and multiplayer on are refused and spend nothing (#273).
- `construction-wall` a clear land cell or straight H/V run that 4-touches an
  existing wall, tower or castle places palisade pieces for 2 wood each; water,
  occupied (structure/wall/player/mob/tree/bush), bent, floating (not adjacent),
  short wood and multiplayer on are refused and spend nothing (#276).
- `build-spend-failed` when spend refuses after the check, `BuildCosts.buy`
  returns `spend failed` and never calls the writer (#380 item 3).
- `construction-atomic-spend` `ConstructionPlacer.place` leaves no written
  run, tower or wall when the charge fails: spend before write, refund on writer
  refusal (covers plank, tower and wall).

## How to get to it (user POV)

- Interact mode → Plank in the build picker (#225 / `build-placement.md`). The
  shared module itself stays headless-proven here; the live path is the picker.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_construction_placer_plank`
about 0.4 s in `tools/verify.sh` (~2.0 s alone with `--only=`);
`test_construction_placer_tower` about 0.6 s (~2.3 s alone);
`test_construction_placer_tower_atomic_spend` about 0.3 s (~2.0 s alone);
`test_construction_placer_wall` about 0.7 s (~2.5 s alone);
`test_construction_placer_wall_atomic_spend` about 0.3 s (~2.0 s alone);
`test_construction_placer_atomic_spend` about 0.1 s (~1.8 s alone with `--only=`);
`test_build_costs_spend_failed` about 0.15 s (~1.8 s alone with `--only=`).

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=construction_placer_plank,construction_placer_tower,construction_placer_tower_atomic_spend,construction_placer_wall,construction_placer_wall_atomic_spend,construction_placer_atomic_spend,build_costs_spend_failed`, or the full `tools/verify.sh`.
- **Proof.** Headers `-- test_construction_placer_plank`,
  `-- test_construction_placer_tower`,
  `-- test_construction_placer_tower_atomic_spend`,
  `-- test_construction_placer_wall`,
  `-- test_construction_placer_wall_atomic_spend`,
  `-- test_construction_placer_atomic_spend` and
  `-- test_build_costs_spend_failed` in `artifacts/verify.log` with no `FAIL`
  after them. Live placement is driven through the build picker; see
  [Build placement](./build-placement.md), [Build tower](./build-tower.md) and
  [Free-form walls](./free-form-walls.md).

## Gotchas

- Never paint planks from a drive to make placement pass; report the missing UI.
- Callers must go through `ConstructionPlacer.place` (or `can_place` then
  `BuildCosts.buy`) so the adjacency rule, the cost and the writer stay together.
  `buy` takes the wood before the writer runs; a failed place is unambiguous
  (nothing written, wood unchanged or refunded).
- `TileMap.build_bridge` stays as the low-level writer for tests that only
  check the tiles; play and the shared module go through `ConstructionPlacer`.
