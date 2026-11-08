# Chop trees (live drive)

Drive: drives/chop_trees.gd

In interact mode one gesture starts one sweep. A tap aims the chop cone from the hero toward the finger, out to `CHOP_REACH` (240 px, 8× the sword's 30 px). A drag past 6 viewport pixels aims the same cone, and the drag's world length clamps that reach. Every plant in the cone is queued. Each plays the full two-hit chop, nearest first, before the next starts. Moving, dying, or leaving interact mode during the swing or the recovery clears the rest of the queue. This file is the live-drive recipe. The mechanics, bushes, regrowth and their headless tests are in [Chopping trees and bushes](./chop-trees-and-bushes.md).

## Sub-features

- `chop-mode` the `CanvasLayer1/ModeButton` toggles `Interaction.Mode` between `COMBAT` and `INTERACT` (`Scripts/mechanics/interact/interaction.gd`).
- `chop-tap` a tap aims one cone from the hero toward the finger, reach `CHOP_REACH` (240 px). It does not also chop a second target. Building still uses `REACH` (80 px). The sword reach stays 30 px.
- `chop-swing` `ChopAction` (`Scripts/mechanics/trees/chop_action.gd`): the hero faces the tree and `ChopSprite` shows the chop sheet (4 columns, wind-up, swing, impact, recover). Each axe impact emits `chop_hit(cell, hit)` (re-emitted as `Interaction.chop_hit`), and the tree falls `ChopAction.fell_at(2)` = 0.56 s after the first wind-up.
- `chop-sounds` each impact plays a `tree_chop_01..03` clip (never the same twice in a row) with `leaf_rustle_01`, the last impact adds `tree_crack_01`, and the fall plays `tree_fall_01` then `wood_pickup_01..02` as the wood is added. Slots in `tree.tres`, one `AudioStreamPlayer2D` each on `SFX`, local only (`docs/audio.md`, Chop sounds).
- `chop-frames` each impact draws the tree's own hit frames in place of its tile (`tree_hit.png`, `pine_hit.png`) with chips and leaves over it (`fx_tree.png`, `fx_pine.png`); the fall keeps the puff and adds falling leaves (#333, headless `-- test_chop_tree_frames`).
- `chop-death` the hero dying mid-chop, before the fall, cancels it: no stump, no wood, no fall or pickup sound.
- `chop-result` the tree's foliage tile (layer 1, `TREE` or `TREE_BUSHY`, or `TREE_PINE_SMALL` for the `pine.tres` type with the same values) is erased, `STUMP` is set on `GROUND_DECOR_LAYER` (layer 2), and `Inventory` gains the tree's `yields` (3 `wood`) once.

## How to get to it (user POV)

- Host or join a world, tap `CanvasLayer1/ModeButton`, walk next to a tree and tap it.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: headless `-- test_chop_tree_two_hits`, `-- test_chop_tree_sounds` and `-- test_chop_cancel_on_death` are each under 0.5 s in `tools/verify.sh` (~1.3–1.5 s alone with `--only=`); `-- test_chop_sheet_on_single_cut` adds about 0.3 s (~1.5 s alone with `--only=`); the `chop_tree` step of `tools/audio_check.gd` adds about 1.9 s to that check; the live drive is about 6 s with `--display`, launch to `VERIFY_DONE` (a one-tree drag at 1280×720 and another at 854×480 add about 1 s).

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=chop_tree_two_hits` (also `chop_sheet_on_single_cut`, `chop_tree_sounds`, `chop_cancel_on_death`), or the full `tools/verify.sh`. The mixer-level sound check is the `chop_tree` step of `tools/audio_check.gd` (in `tools/verify.sh`).
- **Drive (live).** `bin/launch.sh drives/chop_trees.gd --seed 49 --display` (the drive's `## launch: --seed 49` line; `verify-drive.yml` reads it). Steps `start`, `interact-mode`, `chop`, `one-drag`, `range`, `constrained`, `save`: `start_game()`, wait until the hero is still, pick the tree in reach nearest the hero, `snapshot("before")`, `toggle_mode()`, `tap_cell` that tree, `snapshot("swing")` and `snapshot("impact")` while `ChopSprite` is visible, wait for its stump, check wood and sounds, `snapshot("after")`. Then a finger drag of 7 viewport px whose box holds exactly one other tree (`choppables_in_rect` count 1, past the 6 px threshold): `snapshot("drag-impact")` on chop-sheet column 2 or later, then `snapshot("drag-cut")` once that cell is `STUMP` after 2 hits on it alone. Then drag across two trees, `snapshot("range")`. Shrink the window to 854×480 and repeat the one-tree drag, `snapshot("drag-impact-constrained")` and `snapshot("drag-cut-constrained")`, restore 1280×720, `menu_save()`, `done(true)`. It prints `chop: one-drag targets 1 ...`, `chop: one-drag impact frame ...` and `chop: one-drag stump ... after 2 hit(s)` at each window size.
- **Proof.** The drive paints a fixed set. A tap north selects the trees at 32, 64, 96 and 240 px and not the tree at 256 px or the tree to the south. `tap-first` shows the first chop. `tap-done` is after every selected tree is a stump, the queue is empty, and the wood matches. A drag through two more trees does the same for that pair (`drag-first`, `drag-done`). `recover-cancel` is a move during the 0.56–0.64 s recovery: the next tree stays up and the queue is empty. Headless `-- test_chop_sweep_bounds_and_cancel` checks the same boundary distances and recovery move, mode switch, and death. `-- test_sword_reach` still requires a 30 px sword cone.

## Gotchas

- Moving more than 2 px (`MOVE_CANCEL`) or leaving interact mode mid-chop cancels it with no stump and no wood. The hero can still drift after `hold()` releases or settle after spawn; the drive waits 10 still physics frames before each tap and before each one-tree drag. The first chop does not walk. Later steps walk south only when the needed trees are not already in reach.
- In a two-player game the host decides each cut; a client's stump shows one round trip after its tree falls ([Cut sync](./cut-sync.md)). The mode button works in every session state (`-- test_interact_in_multiplayer`).
- The tap chops the nearest choppable in reach, which can be a neighbouring bush (1 wood) when the tapped cell itself is not in reach. Tap the tree's own cell while it is in reach (distance 0 wins) and check the cell in `chop_hit`, not only the wood count.
- Without `--seed` the map is random, and most spawns have no tree in reach (4 of seeds 1-60 do: 22, 48, 49, 58). The drive then fails with `chop: no tree in reach of the hero at ...; launch with the seed above` instead of walking.
- A tap that starts no chop, or a chop that ends with no stump, is printed with what the game saw (`hero`, distance, `in_reach`, mode, the tap's window position) and tried again, up to 3 taps. In 25 consecutive seed-49 runs every chop started on the first tap.
- `snapshot()` `foliage` names a `TREE_PINE_SMALL` cell `PINE` (same atlas coords). The stump is in `ground_decor`.
- `sfx_log` records streams as they start; headless playback is not heard. Whether they are heard is `tools/audio_check.gd`'s job (probe bus per sound player).
- Headless tests: `-- test_chop_tree_two_hits`, `-- test_chop_sheet_on_single_cut`, `-- test_chop_tree_frames`, `-- test_chop_tree_sounds`, `-- test_chop_cancel_on_death`, `-- test_interact_mode_toggle`.
