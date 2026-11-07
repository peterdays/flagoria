# Chop trees (live drive)

Drive: drives/chop_trees.gd

In interact mode a tap on a tree in reach makes the hero face it and swing twice (`hits = 2` in `data/interactables/tree.tres`); the tree becomes a walkable stump and gives its wood once, with the tree sounds of #265. A drag past 6 viewport pixels that still holds only that tree plays the same swings. A drag whose box holds two or more plants cuts them at once and leaves the hero on the walk sprite. This file is the live-drive recipe. The mechanics, bushes, regrowth and their headless tests are in [Chopping trees and bushes](./chop-trees-and-bushes.md).

## Sub-features

- `chop-mode` the `CanvasLayer1/ModeButton` toggles `Interaction.Mode` between `COMBAT` and `INTERACT` (`Scripts/mechanics/interact/interaction.gd`).
- `chop-tap` a tap chops the choppable in reach (`REACH`, 80 px) nearest the tapped point, on the tapped cell or one of its 8 neighbours.
- `chop-swing` `ChopAction` (`Scripts/mechanics/trees/chop_action.gd`): the hero faces the tree and `ChopSprite` shows the chop sheet (4 columns, wind-up, swing, impact, recover). Each axe impact emits `chop_hit(cell, hit)` (re-emitted as `Interaction.chop_hit`), and the tree falls `ChopAction.fell_at(2)` = 0.56 s after the first wind-up.
- `chop-sounds` each impact plays a `tree_chop_01..03` clip (never the same twice in a row) with `leaf_rustle_01`, the last impact adds `tree_crack_01`, and the fall plays `tree_fall_01` then `wood_pickup_01..02` as the wood is added. Slots in `tree.tres`, one `AudioStreamPlayer2D` each on `SFX`, local only (`docs/audio.md`, Chop sounds).
- `chop-frames` each impact draws the tree's own hit frames in place of its tile (`tree_hit.png`, `pine_hit.png`) with chips and leaves over it (`fx_tree.png`, `fx_pine.png`); the fall keeps the puff and adds falling leaves (#333, headless `-- test_chop_tree_frames`).
- `chop-death` the hero dying mid-chop, before the fall, cancels it: no stump, no wood, no fall or pickup sound.
- `chop-result` the tree's foliage tile (layer 1, `TREE` or `TREE_BUSHY`, or `TREE_PINE_SMALL` for the `pine.tres` type with the same values) is erased, `STUMP` is set on `GROUND_DECOR_LAYER` (layer 2), and `Inventory` gains the tree's `yields` (3 `wood`) once.

## How to get to it (user POV)

- Host or join a world, tap `CanvasLayer1/ModeButton`, walk next to a tree and tap it.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: headless `-- test_chop_tree_two_hits`, `-- test_chop_tree_sounds` and `-- test_chop_cancel_on_death` are each under 0.5 s in `tools/verify.sh` (~1.3–1.5 s alone with `--only=`); `-- test_chop_sheet_on_single_cut` adds about 0.3 s (~1.5 s alone with `--only=`); the `chop_tree` step of `tools/audio_check.gd` adds about 1.9 s to that check; the live drive is about 5 s with `--display`, launch to `VERIFY_DONE`.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=chop_tree_two_hits` (also `chop_sheet_on_single_cut`, `chop_tree_sounds`, `chop_cancel_on_death`), or the full `tools/verify.sh`. The mixer-level sound check is the `chop_tree` step of `tools/audio_check.gd` (in `tools/verify.sh`).
- **Drive (live).** `bin/launch.sh drives/chop_trees.gd --seed 49 --display` (the drive's `## launch: --seed 49` line; `verify-drive.yml` reads it). Steps `start`, `interact-mode`, `chop`, `range`, `constrained`, `save`: `start_game()`, wait until the hero is still, pick the tree in reach nearest the hero (`map.choppable(cell)` with `id` `"tree"` or `"pine"` and `World/Interaction` `in_reach(cell)`; no walking), `snapshot("before")`, `toggle_mode()`, connect `World/Interaction` `chop_hit`, `tap_cell(cell)` on the tree's own cell, `snapshot("swing")` on chop-sheet column 1 and `snapshot("impact")` on column 2 or later while `ChopSprite` is visible, wait for `STUMP` on `GROUND_DECOR_LAYER`, check the wood and the chop's sounds (`Interaction.sfx_log`), `snapshot("after")`, drag across two other trees in one row, `snapshot("range")`, shrink the window to 854×480 and tap another tree, `snapshot("swing-constrained")`, restore 1280×720, `menu_save()`, `done(true)`. It prints `chop: target ...`, `chop: swing frame ...`, `chop: impact frame ...`, `chop: stump at ... tap N`, `chop: sounds [...]`, `chop: range cut true` and `chop: saved user://saves/...`.
- **Proof.** Read from `01-before.json`, `02-swing.json`, `03-impact.json` and `04-after.json` under `artifacts/out/runs/<run-id>/` (PNGs with `--display`): the swing and impact shots show `ChopSprite` (the walk sprite hidden) and at the target cell `04-after` has `foliage` `null` and `ground_decor` `STUMP`, and `inventory.wood` goes up by the tree's yield (0 to 3). `05-range` is two stumps with the hero still on the walk sprite. `06-swing-constrained` is the same swing at 854×480. The drive also fails if a `chop_hit` lands on any other cell, if the hits are not 2, if the wood is not exactly +3 ten frames after the first stump, if the chop sheet never reaches column 1 and column 2, or if the sounds are not `tree_chop, leaf_rustle, tree_chop, leaf_rustle, tree_crack, tree_fall, wood_pickup` in that order (clip numbers dropped). The death cancel is headless only (`-- test_chop_cancel_on_death`). The one-tree drag versus the two-tree drag is `-- test_chop_sheet_on_single_cut`. The world save is in `user/saves/`.

## Gotchas

- Moving more than 2 px (`MOVE_CANCEL`) or leaving interact mode mid-chop cancels it with no stump and no wood. The hero can still drift after `hold()` releases or settle after spawn; the drive waits 10 still physics frames before each tap. The first chop does not walk. The range cut and the constrained swing walk south only when no second tree, or no tree, is already in reach.
- In a two-player game the host decides each cut; a client's stump shows one round trip after its tree falls ([Cut sync](./cut-sync.md)). The mode button works in every session state (`-- test_interact_in_multiplayer`).
- The tap chops the nearest choppable in reach, which can be a neighbouring bush (1 wood) when the tapped cell itself is not in reach. Tap the tree's own cell while it is in reach (distance 0 wins) and check the cell in `chop_hit`, not only the wood count.
- Without `--seed` the map is random, and most spawns have no tree in reach (4 of seeds 1-60 do: 22, 48, 49, 58). The drive then fails with `chop: no tree in reach of the hero at ...; launch with the seed above` instead of walking.
- A tap that starts no chop, or a chop that ends with no stump, is printed with what the game saw (`hero`, distance, `in_reach`, mode, the tap's window position) and tried again, up to 3 taps. In 25 consecutive seed-49 runs every chop started on the first tap.
- `snapshot()` `foliage` names a `TREE_PINE_SMALL` cell `PINE` (same atlas coords). The stump is in `ground_decor`.
- `sfx_log` records streams as they start; headless playback is not heard. Whether they are heard is `tools/audio_check.gd`'s job (probe bus per sound player).
- Headless tests: `-- test_chop_tree_two_hits`, `-- test_chop_sheet_on_single_cut`, `-- test_chop_tree_frames`, `-- test_chop_tree_sounds`, `-- test_chop_cancel_on_death`, `-- test_interact_mode_toggle`.
