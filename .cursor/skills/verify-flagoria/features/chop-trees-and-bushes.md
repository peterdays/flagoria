# Chopping trees and bushes

In interact mode the hero chops trees and bushes for wood. Each choppable kind is a data file (`data/interactables/tree.tres`, `pine.tres`, `bush.tres`, script `Scripts/mechanics/interactables/interactable_type.gd`) that sets its tiles, hits, `yields` (wood), what it leaves (STUMP, BUSH_STUMP), `regrow_delay`, `save_key`, sounds and effect frames. The pine (`TREE_PINE_SMALL`, generated as `PINE`) is its own type with the tree's values (#266). `InteractableCatalog` (a preload list) maps a foliage tile to its type.

## Sub-features

- `chop-tap` a tap chops the nearest choppable next to the tapped cell: two hits (140 ms and 460 ms), it falls at 560 ms (`ChopAction.step_chop`, `fell_at` in `Scripts/mechanics/trees/chop_action.gd`, driven by `Interaction`).
- `chop-range` a drag cuts every choppable in the range within reach at once (`Interaction.cut_range` in `Scripts/mechanics/interact/interaction.gd`).
- `chop-yield` a fallen plant gives its type's `yields` (tree and pine 3 wood, bush 1, tunable in the `.tres`).
- `bush-effects` a bush hit draws `art/flagoria/fx/bush_hit.png` in place of the bush tile (the tile switches to its invisible alternative 1 with the same collision) and `fx_leaves.png` frames 0-1; the fall plays frames 2-3, the bush break sound, and no puff.
- `tree-effects` a tree, bushy tree or pine hit hides the tile the same way (alternative 1, collision kept) and draws its own row of the type's hit sheet in its place: `art/flagoria/fx/tree_hit.png` row 0 for `TREE`, row 1 for `TREE_BUSHY` (`InteractableType.hit_row`), `pine_hit.png` for `TREE_PINE_SMALL`. Each sheet has 2 frames, 50 ms each, the canopy swaying while the trunk stays put. Over it `fx_tree.png` or `fx_pine.png` frames 0-1 play (hit spark and wood chips, then a leaf or needle off the canopy). The fall at 560 ms keeps the puff and adds frames 2-3 (leaves or needles bursting out, then landing). The frames are drawn from the tiles by `tools/art/gen_tree_chop_frames.py` (#333).
- `chop-sounds` each type's sound slots (`hit_sounds`, `hit_layer_sounds`, `last_hit_sounds`, `fell_sounds`, `pickup_sounds`, `hit_no_repeat`); the tree fills all of them, the bush only `hit_sounds` and `fell_sounds` (`docs/audio.md`, Chop sounds).
- `chop-death` the hero dying before the fall cancels the chop with no stump and no wood (`ChopAction.step_chop`). A dead hero's taps and drags cut nothing ([Dead player cuts nothing](./dead-player-cut.md)).
- `stump-kept` the stump stays when the chunk is drawn again and is open ground for mobs (`TileMap.cut_choppable`, kept in `TreeCuts._cut_cells` in `Scripts/mechanics/trees/tree_cuts.gd`).
- `wood-hud` the wood counter (`ResourceHud`) sits centred at the top at the hearts' scale, starts at 0 and follows the inventory.
- `type-checklist` every `.tres` in `data/interactables/` is in `InteractableCatalog.TYPES` and passes each machine-checkable step of the `docs/interactables.md` checklist (#269, #326); a broken copy fails naming the type and step.
- `regrow` after its type's `regrow_delay` seconds of play (300 for every type; 0 = never) the stump turns back into the same tree or bush (`TileMap.regrow_due`, forwards to `TreeCuts`). Setting `TileMap.regrow_delay` (default -1) overrides it for every type; tests set 30. A due stump waits while a player's body box or a mob's feet box (`Mob.feet_cells`, the cells `Mob.can_stand_at` checks) covers it, and regrows on a later check once the cell is free (`TileMap.player_on_cell`, `TileMap.mob_on_cell`, #232), so a regrown tree never traps a mob. Only the host (or a single-player game) runs this check.

## How to get to it (user POV)

- Start or join a game, tap the mode button to switch to interact, then tap a tree or bush next to the hero. The wood count on the HUD goes up when it falls.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `-- test_catalog_resolves_cells` and `-- test_regrow_delay_per_type` (#266) each add under 0.1 s to `tools/verify.sh` (~1.3–1.4 s alone with `--only=`, mostly engine start). `-- test_tree_regrows_under_mob` (#232) adds about 0.1 s (~1.5 s alone with `--only=`, mostly engine start). `-- test_chop_tree_frames` (#333) adds about 0.1 s (~1.5 s alone with `--only=`, mostly engine start).

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`. One test: `godot --headless --path . --script res://tests/run_tests.gd -- --only=chop_bush` with scratch `XDG_*` dirs.
- **Proof.** Headers `-- test_interact_cut_trees`, `-- test_chop_tree_two_hits`, `-- test_chop_bush`, `-- test_chop_tree_frames`, `-- test_chop_tree_sounds`, `-- test_chop_cancel_on_death`, `-- test_cut_bush_stays_stump_and_regrows`, `-- test_cut_tree_stays_stump`, `-- test_tree_regrows`, `-- test_tree_regrows_under_mob`, `-- test_catalog_resolves_cells`, `-- test_regrow_delay_per_type`, `-- test_resource_hud_in_scene`, `-- test_checklist_types_on_main`, `-- test_checklist_fixtures_fail` appear with no `FAIL` line after them, and the run ends with `All tests passed.`
- **End state.** The chopped cell has no foliage tile, a STUMP or BUSH_STUMP on `GROUND_DECOR_LAYER`, the wood count rose by the type's yield, and the hero can walk through the cell.
- **Visual.** For a screenshot, run the game windowed under `xvfb-run` with `--rendering-driver opengl3`, start a chop and capture the viewport between 140 ms and 240 ms (hit frames and leaves) and after 960 ms (stump only). For the frames alone, `python3 tools/art/gen_tree_chop_frames.py` redraws the tree and pine sheets; compare them next to `bush_hit.png` and `fx_leaves.png`.

## Gotchas

- Cuts are saved in world saves (`world.object_changes`, `tests/saves/test_cut_save.gd`) and synced in two-player play: the host decides each cut and every peer shows the stump ([Cut sync](./cut-sync.md)). Regrowth is the host's too (#298): a client's `regrow_due` does nothing while connected, and the host sends each regrowth to every peer.
- `has_tree` is true for the tree and pine types; use `choppable(cell)` for any choppable.
- A saved cut names its type by `save_key` and stores its age in seconds of play, so nothing regrows while the game is closed.
- A type with several `tiles` needs one hit sheet row per tile, in the order of `tiles`; the checklist test fails a sheet with the wrong number of rows.
- A type with a `hit_sheet` needs alternative tile `ChopAction.HIDDEN_ALT` (also `Interaction.HIDDEN_ALT`) in the TileSet, invisible and with the same collision, or the hit frames draw over the tile.
- Headless, played sounds never finish, so a run that chops a tree or bush ends with its streams listed as "still in use at exit"; that is not a failure.
