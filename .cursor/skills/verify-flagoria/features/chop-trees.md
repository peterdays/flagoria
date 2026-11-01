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

Preconditions: `doctor.sh` exits `0`. Time cost: headless `-- test_chop_tree_two_hits` is under 0.5 s in `tools/verify.sh` (~1.2 s alone with `--only=chop_tree_two_hits`); a live drive is a few seconds (scratch runs took 3-9 s, most of it walking).

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=chop_tree_two_hits`, or the full `tools/verify.sh`.
- **Drive (live, to write as `drives/chop_trees.gd`).** `start_game()`, `toggle_mode()`, find the nearest tree by reading `World/worldMap` layer 1 near the hero (`map.choppable(cell)` with `id == "tree"`), walk toward it with `hold()` until `World/Interaction` `in_reach(cell)`, wait until the hero is still, connect `World/Interaction` `chop_hit`, `snapshot("before")`, `tap_cell(cell)`, `wait_until()` two hits, `snapshot("after")`, `done()`.
- **Proof.** End state: layer 1 at the cell goes from a tree tile to empty and `GROUND_DECOR_LAYER` holds `STUMP`; `Inventory.count_of(&"wood")` rose by the tree's yield exactly once (a second tap on the stump adds no wood); two `chop_hit` signals for that cell, `hit` 1 then 2; `before` and `after` snapshots under `artifacts/out/runs/<run-id>/` (PNGs with `--display`).

## Gotchas

- Moving more than 2 px (`MOVE_CANCEL`) or leaving interact mode mid-chop cancels it with no stump and no wood. The hero can still drift after `hold()` releases; wait until it is still before tapping.
- A peer joining forces combat mode and hides the mode button (`-- test_interact_off_in_multiplayer`).
- The tap chops the nearest choppable in reach, which can be a neighbouring bush (1 wood). Check the cell in `chop_hit`, not only the wood count.
- The map is random per run. Some spawns have no tree within 30 cells, or the walk gets blocked; such a drive reports it found no tree in reach rather than passing.
- In scratch runs on main, one of six headless runs reached the full proof; the rest found no tree, drifted, or started no chop from a still hero. `drives/chop_trees.gd` should handle each case before it is trusted.
- `snapshot()` foliage names a `TREE_PINE_SMALL` cell `PINE` (same atlas coords), and it reads layer 1 only, so read the stump from `GROUND_DECOR_LAYER` directly.
- Headless tests: `-- test_chop_tree_two_hits`, `-- test_interact_mode_toggle`.
