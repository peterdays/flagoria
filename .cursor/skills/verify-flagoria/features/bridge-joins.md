# Bridge joins

Drive: drives/bridge_joins.gd

Separately placed plank runs that share a side become one deck (#416).
`BridgeBuilder` picks each cell's `_WATER` piece from the planks and walkable
ground beside it, then solves every placed cell again after a placement or a
removal. Plain `H` / `V` runs through the interior, including the cell that
used to end an earlier placement. `START`, `END` and `SINGLE` (the rope and
tying) stay only on a side that touches walkable ground. `TIP_*` stays only
on open water. That tip is the unfinished end of the planks, not shore rope
or an anchor. The longer straight run keeps its axis when a one-cell branch
meets it. The atlas has no corner piece. Vertical runs use the existing `V`
pieces the same way.

Support and placement checks are unchanged. A run still has to be straight
water, empty, and 4-touch land or an existing plank. `ConstructionPlacer`
still refuses land, a bend, an occupied cell and a floating run. Nothing in
play removes a bridge yet. `erase_cells` is how a removal refreshes the
pictures, and the drive calls it.

## Sub-features

- `bridge-joins` a run of three planks and a second run that continues it draw
  one deck, east-west and north-south. Removing the continuation puts the tip
  back on the third plank and water on the removed cells. Placing it again
  joins the deck. A missing vertical gap, or a vertical removal that does not
  land, fails the check. A side branch does not replace the straight interior
  planks.

## How to get to it (user POV)

Host alone. Interact mode, Plank, drag a short run from a shore across water,
then drag a second run that starts on the next water cell. The shared edge is
plain planks. Rope stays on the shores. An end that stops on open water keeps
a tip, the unfinished plank end, not a shore rope.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_bridge_joins` adds about
0.5 s in `tools/verify.sh` (~2.2 s for `--only=bridge_joins`, against ~1.7 s
of runner start-up). The drive is about 3 s under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=bridge_joins`, or the full `tools/verify.sh`. `test_bridge_planks` still checks one isolated run.
- **Drive (live).** `bin/launch.sh drives/bridge_joins.gd --display` (under xvfb, seed 11). Steps `separate`, `joined`, `removed`, `rejoined`, then the same four for a north-south gap: `vertical-separate`, `vertical-joined`, `vertical-removed`, `vertical-rejoined`. `start_game()`, hide the minimap, find a short shore-to-shore water gap, place the first three planks with `build_bridge`, `snapshot("separate")`, place the rest, `snapshot("joined")`, `erase_cells` the rest, `snapshot("removed")`, place them again, `snapshot("rejoined")`. Then a north-south gap that does not use those cells, with the same place, remove and rejoin, and `snapshot("vertical-separate")`, `snapshot("vertical-joined")`, `snapshot("vertical-removed")`, `snapshot("vertical-rejoined")`.
- **Proof.** `-- test_bridge_joins` in `artifacts/verify.log` with no `FAIL` after it, and the pass line names a vertical gap. Drive snapshots `01-separate`, `02-joined`, `03-removed`, `04-rejoined`, `05-vertical-separate`, `06-vertical-joined`, `07-vertical-removed`, `08-vertical-rejoined` under `--display`. Separate shows a tip at the third plank and open water after it. Joined and rejoined show plain planks across that edge and rope only at the two shores. Removed shows the tip back and water where the continuation was. The vertical four use the existing north-south pieces. Separate and removed end in a tip, the unfinished planks, over the cell that is not the far shore yet. Joined and rejoined are one column: plain planks between the runs, and a land joint only on an end that touches walkable ground.

## Gotchas

- The drive places and removes through `build_bridge` and `erase_cells`, the solver play uses when a plank run is written. It does not spend wood. `test_bridge_joins` checks the placer still accepts the continuation and still refuses land, an occupied cell and a floating cell.
- `bridge_pieces` remains the isolated-run table. A joined deck matches that table for the whole connected length, not for each placement on its own.
- No new art. `BROKEN` pieces are still unused.
