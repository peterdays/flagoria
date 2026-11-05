# Construction placement

Shared placement for every buildable (#296). `ConstructionPlacer`
(`Scripts/mechanics/building/construction_placer.gd`) checks a kind on a list
of cells, reports the wood cost, and places through `BuildCosts.buy` into the
kind's writer. The plank bridge is the first kind: a straight water run that
touches land or an existing plank, written by `TileMap.build_bridge` /
`BridgeBuilder`. Walls (#276) and towers (#273) add more kind entries later.
The placement UI (#225) only talks to this module.

Refusal reasons (each at most once): `empty cells`, `unknown kind`,
`wrong ground`, `occupied`, `not straight`, `not adjacent`, `not enough wood`,
`multiplayer on`. A floating water cell with no land or plank neighbour is
`not adjacent` (2026-11-02: no floating planks).

Host-alone: while multiplayer is on, `can_place` includes `multiplayer on` and
`place` writes nothing. Sync of placed blocks between peers is #297.

## Sub-features

- `construction-plank` a straight water run next to land or a plank places and
  spends one wood per cell; land, an existing plank, a bent run, a floating
  cell, too little wood and multiplayer on are refused with a reason and spend
  nothing.
- `build-spend-failed` when a place callable empties the inventory, `BuildCosts.buy`
  returns `spend failed` instead of success (#377).

## How to get to it (user POV)

- None on `main`: there is no in-game build action yet. The live drive is
  **verified-unreachable** until the interact-mode build picker lands (#225).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_construction_placer_plank`
about 0.4 s in `tools/verify.sh` (~2.0 s alone with `--only=`);
`test_build_costs_spend_failed` about 0.15 s (~1.8 s alone with `--only=`).

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=construction_placer_plank,build_costs_spend_failed`, or the full `tools/verify.sh`.
- **Proof.** Headers `-- test_construction_placer_plank` and
  `-- test_build_costs_spend_failed` in `artifacts/verify.log` with no `FAIL`
  after them. A live drive reports **verified-unreachable: no in-game build
  action** (prerequisite: #225).

## Gotchas

- Never paint planks from a drive to make placement pass; report the missing UI.
- Callers must go through `ConstructionPlacer.place` (or `can_place` then
  `BuildCosts.buy`) so the adjacency rule, the cost and the writer stay together.
- `TileMap.build_bridge` stays as the low-level writer for tests that only
  check the tiles; play and the shared module go through `ConstructionPlacer`.
