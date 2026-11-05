# Build costs

What each buildable costs in wood, and buying one. `BuildCosts` (`Scripts/mechanics/building/build_costs.gd`) holds the table and `buy`; `Inventory.spend` (`Scripts/inventory.gd`) takes the wood. Wood comes from chopping: a tree gives 3, a bush 1 (`data/interactables/`).

| Kind | Wood per unit | Unit |
|---|---|---|
| `plank` | 1 | one bridge cell |
| `wall_block` | 2 | one wall cell |
| `tower` | 10 | one tower |
| `start_castle` | 0 | the castle each player starts with |

A removal gives back `REFUND_SHARE` (half) of the total cost of the units removed together, rounded down. Nothing removes a build yet, so nothing reads it in play.

`buy(inventory, kind, units, place)` checks first, takes the wood, then calls the writer `place` (for example `build_bridge`). Refusals, with nothing placed and nothing spent: `not enough wood`, `multiplayer on`, `unknown kind`. If `spend` fails after the check, `buy` returns `spend failed` and never calls the writer. If the writer refuses after the spend, the wood is put back and `buy` returns `not placed`. Charge and write stay atomic (#380 item 3).

With peers connected: wood is local to each game and not synced, so `buy` refuses with `multiplayer on` for a client and for a host with a peer, the same rule as `StructurePlacer`. Per-player wood for connected peers is #278.

## Sub-features

- `build-cost-table` the costs and refunds above, and -1 cost for an unknown kind.
- `inventory-spend` `spend` takes the amount and emits `changed` when there is enough; too little or a negative amount takes nothing and emits nothing. The wood HUD shows the new count.
- `build-buy` too little wood places nothing and keeps the wood; enough wood places and spends the cost; a writer refusal spends nothing; the starting castle needs no wood; multiplayer on refuses before the writer runs.

## How to get to it (user POV)

- Interact mode → Plank places through `ConstructionPlacer` → `BuildCosts.buy` (#225 / `build-placement.md`). The starting castle is still placed without going through `buy`.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_build_cost_table` and `test_inventory_spend` under 0.05 s each in `tools/verify.sh`; `test_build_costs_buy` about 0.2 s (~1.9 s alone with `--only=`, against ~1.7 s for runner start-up). The spend check added to `test_resource_hud_in_scene` adds no measurable time.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=build_cost_table,inventory_spend,build_costs_buy,resource_hud_in_scene`, or the full `tools/verify.sh`.
- **Proof.** Headers `-- test_build_cost_table`, `-- test_inventory_spend`, `-- test_build_costs_buy` and `-- test_resource_hud_in_scene` in `artifacts/verify.log` with no `FAIL` after them. Live spend is driven through the build picker; see [Build placement](./build-placement.md).

## Gotchas

- Never add wood from a drive to make a purchase pass in a live game; a drive that can't reach the feature reports that.
- `buy` must be the only place that spends wood for a build, so the check, the spend and the placement stay in one order (spend before write).
