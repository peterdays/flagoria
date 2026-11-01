# Chop trees (live drive)

In interact mode a tap on a tree in reach makes the hero face it and swing twice (`hits = 2` in `data/interactables/tree.tres`); the tree becomes a walkable stump and gives its wood once. This file is the live-drive recipe for one tree. The mechanics, bushes, regrowth and their headless tests are in [Chopping trees and bushes](./chop-trees-and-bushes.md).

## Sub-features

- `chop-mode` the `CanvasLayer1/ModeButton` toggles `Interaction.Mode` between `COMBAT` and `INTERACT` (`Scripts/mechanics/interact/interaction.gd`).
- `chop-tap` a tap chops the choppable in reach (`REACH`, 80 px) nearest the tapped point, on the tapped cell or one of its 8 neighbours.
- `chop-swing` `ChopAction` (`Scripts/mechanics/trees/chop_action.gd`): the hero faces the tree, each axe impact emits `chop_hit(cell, hit)` (re-emitted as `Interaction.chop_hit`), and the tree falls `ChopAction.fell_at(2)` = 0.56 s after the first wind-up.
- `chop-result` the tree's foliage tile (layer 1, `TREE` or `TREE_PINE_SMALL`) is erased, `STUMP` is set on `GROUND_DECOR_LAYER` (layer 2), and `Inventory` gains the tree's `yields` (3 `wood`) once.

## How to get to it (user POV)

- Host a world alone (interact mode is off once a peer is connected), tap `CanvasLayer1/ModeButton`, walk next to a tree and tap it.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: headless `-- test_chop_tree_two_hits` is under 0.5 s in `tools/verify.sh` (~1.2 s alone with `--only=chop_tree_two_hits`); the live drive is about 2.5 s headless, launch to `VERIFY_DONE` (25 runs with cleanup took 61 s).

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=chop_tree_two_hits`, or the full `tools/verify.sh`.
- **Drive (live).** `bin/launch.sh drives/chop_trees.gd --seed 49` (the drive's `## launch: --seed 49` line; `verify-drive.yml` reads it). Steps `start`, `interact-mode`, `chop`, `save`: `start_game()`, wait until the hero is still, pick the tree in reach nearest the hero (`map.choppable(cell)` with `id == "tree"` and `World/Interaction` `in_reach(cell)`; no walking), `snapshot("before")`, `toggle_mode()`, connect `World/Interaction` `chop_hit`, `tap_cell(cell)` on the tree's own cell, wait for `STUMP` on `GROUND_DECOR_LAYER`, check the wood, `snapshot("after")`, `menu_save()`, `done(true)`. It prints `chop: target ...`, `chop: stump at ... tap N` and `chop: saved user://saves/...`.
- **Proof.** Read from `01-before.json` and `02-after.json` under `artifacts/out/runs/<run-id>/` (PNGs with `--display`): at the target cell `foliage` goes from `TREE` to `null` and `ground_decor` from `null` to `STUMP`, and `inventory.wood` goes up by the tree's yield (0 to 3). The drive also fails if a `chop_hit` lands on any other cell, if the hits are not 2, or if the wood is not exactly +3 ten frames after the stump. With seed 49 the hero spawns at cell (-2, 0) and the target is (-6, 0), 64 px away, so it is column 0 of row 4 in the 9x9 grids. The world save is in `user/saves/`.

## Gotchas

- Moving more than 2 px (`MOVE_CANCEL`) or leaving interact mode mid-chop cancels it with no stump and no wood. The hero can still drift after `hold()` releases or settle after spawn; the drive waits 10 still physics frames before each tap and does not walk.
- A peer joining forces combat mode and hides the mode button (`-- test_interact_off_in_multiplayer`).
- The tap chops the nearest choppable in reach, which can be a neighbouring bush (1 wood) when the tapped cell itself is not in reach. Tap the tree's own cell while it is in reach (distance 0 wins) and check the cell in `chop_hit`, not only the wood count.
- Without `--seed` the map is random, and most spawns have no tree in reach (4 of seeds 1-60 do: 22, 48, 49, 58). The drive then fails with `chop: no tree in reach of the hero at ...; launch with the seed above` instead of walking.
- A tap that starts no chop, or a chop that ends with no stump, is printed with what the game saw (`hero`, distance, `in_reach`, mode, `interact_allowed`, the tap's window position) and tried again, up to 3 taps. In 25 consecutive seed-49 runs every chop started on the first tap.
- `snapshot()` `foliage` names a `TREE_PINE_SMALL` cell `PINE` (same atlas coords). The stump is in `ground_decor`.
- Headless tests: `-- test_chop_tree_two_hits`, `-- test_interact_mode_toggle`.
