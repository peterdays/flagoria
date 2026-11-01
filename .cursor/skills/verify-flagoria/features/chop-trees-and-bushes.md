# Chopping trees and bushes

In interact mode the hero chops trees and bushes for wood. Each choppable kind is a data file (`data/interactables/tree.tres`, `bush.tres`, script `Scripts/mechanics/interactables/interactable_type.gd`) that sets its tiles, hits, `yields` (wood), what it leaves (STUMP, BUSH_STUMP), sounds and effect frames. `InteractableCatalog` maps a foliage tile to its type.

## Sub-features

- `chop-tap` a tap chops the nearest choppable next to the tapped cell: two hits (140 ms and 460 ms), it falls at 560 ms (`ChopAction.step_chop`, `fell_at` in `Scripts/mechanics/trees/chop_action.gd`, driven by `Interaction`).
- `chop-range` a drag cuts every choppable in the range within reach at once (`Interaction.cut_range` in `Scripts/mechanics/interact/interaction.gd`).
- `chop-yield` a fallen plant gives its type's `yields` (tree 3 wood, bush 1, tunable in the `.tres`).
- `bush-effects` a bush hit draws `art/flagoria/fx/bush_hit.png` in place of the bush tile (the tile switches to its invisible alternative 1 with the same collision) and `fx_leaves.png` frames 0-1; the fall plays frames 2-3, the bush break sound, and no puff.
- `chop-sounds` each type's sound slots (`hit_sounds`, `hit_layer_sounds`, `last_hit_sounds`, `fell_sounds`, `pickup_sounds`, `hit_no_repeat`); the tree fills all of them, the bush only `hit_sounds` and `fell_sounds` (`docs/audio.md`, Chop sounds).
- `chop-death` the hero dying before the fall cancels the chop with no stump and no wood (`ChopAction.step_chop`).
- `stump-kept` the stump stays when the chunk is drawn again and is open ground for mobs (`TileMap.cut_choppable`, kept in `TreeCuts._cut_cells` in `Scripts/mechanics/trees/tree_cuts.gd`).
- `regrow` after `regrow_delay` seconds of play the stump turns back into the same tree or bush (`TileMap.regrow_due`, forwards to `TreeCuts`).

## How to get to it (user POV)

- Start a single-player game (interact mode is off with a peer connected), tap the mode button to switch to interact, then tap a tree or bush next to the hero. The wood count on the HUD goes up when it falls.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`. One test: `godot --headless --path . --script res://tests/run_tests.gd -- --only=chop_bush` with scratch `XDG_*` dirs.
- **Proof.** Headers `-- test_interact_cut_trees`, `-- test_chop_tree_two_hits`, `-- test_chop_bush`, `-- test_chop_tree_sounds`, `-- test_chop_cancel_on_death`, `-- test_cut_bush_stays_stump_and_regrows`, `-- test_cut_tree_stays_stump`, `-- test_tree_regrows` appear with no `FAIL` line after them, and the run ends with `All tests passed.`
- **End state.** The chopped cell has no foliage tile, a STUMP or BUSH_STUMP on `GROUND_DECOR_LAYER`, the wood count rose by the type's yield, and the hero can walk through the cell.
- **Visual.** For a screenshot, run the game windowed under `xvfb-run` with `--rendering-driver opengl3`, start a chop and capture the viewport between 140 ms and 240 ms (hit frames and leaves) and after 960 ms (stump only).

## Gotchas

- Cuts are not saved (map saves hold generation inputs only) and not synced: interact mode is single-player, and `regrow_due` does nothing while multiplayer is active.
- `has_tree` is true only for the tree type; use `choppable(cell)` for any choppable.
- A type with a `hit_sheet` needs alternative tile `ChopAction.HIDDEN_ALT` (also `Interaction.HIDDEN_ALT`) in the TileSet, invisible and with the same collision, or the hit frames draw over the tile.
- Headless, played sounds never finish, so a run that chops a tree or bush ends with its streams listed as "still in use at exit"; that is not a failure.
