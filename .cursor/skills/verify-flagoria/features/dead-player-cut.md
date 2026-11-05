# Dead player cuts nothing

Drive: not player-facing

A dead hero cannot cut trees or bushes (#349). In interact mode a tap or a drag does nothing while the local player is dead (`Interaction._unhandled_input` in `Scripts/mechanics/interact/interaction.gd`), and on the host `request_cut` refuses a cut from a peer whose player is dead, so a client that skips its own check still gets nothing. A chop already under way when the hero dies is cancelled by `ChopAction.step_chop` (`chop-death` in [Chopping trees and bushes](./chop-trees-and-bushes.md)); both use `Interaction.player_dead`. Cuts in two-player play are in [Cut sync](./cut-sync.md).

## Sub-features

- `dead-input` while the local player's `PlayerHealth.is_dead()` is true, interact-mode touches are ignored: a drag over a tree in reach and a tap on it leave the tree and add no wood. A touch that began while alive is dropped. After the respawn the same drag cuts again.
- `dead-host-refuse` the host's `request_cut` returns without cutting when the sender's player is dead, before the reach check: no stump on any peer and no wood for the sender.
- `painted-tree-survives-respawn` a TREE painted on grass stays a tree after `health.respawn()` even when MapGen seeds would grow a bush there (#359): the painted scene pins spawn on the stand cell and freezes TileMap processing so `resolve_player_spawn` does not `generate_chunk` over the paint.

## How to get to it (user POV)

- Start a game, switch to interact mode, die (to a mob), and drag across a tree next to the body before the respawn. Nothing is cut and the wood count stays the same.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_dead_cut_alone` about 0.15 s in `tools/verify.sh` (~1.8 s alone with `--only=`, against ~1.65 s for runner start-up). `test_painted_tree_survives_respawn` about 0.4 s alone. `test_dead_cut_client` about 2.6 s in `tools/verify.sh` (~4.3 s alone; 1 s of it is a fixed wait for the host's answer), and it runs 20 times in the Netcode stress job.

- **Run.** `godot --headless --path . --script res://tests/run_tests.gd -- --only=dead_cut_alone,painted_tree_survives_respawn,dead_cut_client` with scratch `XDG_*` dirs, or `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`. Stress: `python3 tools/stress_netcode.py -n 10 --only dead_cut_client`.
- **What the client scenario does.** `tests/net/test_cut_sync.gd` starts a host and a client of `tests/cut_sync_probe.gd` on seed 7. The host kills the client's player (`PATH.kill`, 600 s respawn delay). The dead client (`PATH.dead_cut`) steps next to a tree, drags a selection over it with screen touch events, then sends `request_cut` for it straight to the host.
- **Proof.** `PASS test_dead_cut_alone`, `PASS test_painted_tree_survives_respawn` and `PASS test_dead_cut_client (tree (x, y))`. The client test fails unless the drag covered at least one tree in reach, the client is still dead, and 1 s later neither peer holds a cut, the client has 0 wood and no peer logged an engine error.

## Gotchas

- Health is the server's, so the host knows a client's player is dead from its own copy; the client learns it through the health RPC.
- The client test checks an absence after a fixed 1 s wait. On a build without the host check the forged cut lands within a few ms locally, so the wait is ample.
