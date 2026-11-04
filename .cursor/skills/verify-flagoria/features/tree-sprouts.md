# Tree sprouts

Where a biome holds fewer trees than its target share, a tree sprouts on a free cell of that biome (#361). `TreeSprouts` (`Scripts/mechanics/trees/tree_sprouts.gd`) runs a pass every 5 s on the host, or alone, over the 3x3 chunks around each player. Per biome in that area the target is the smaller of `BiomeCatalog.TREE_SHARE` times its land cells and the trees the untouched map grows there; a stump counts as a tree. So only trees lost for good (a structure on their stumps) are made up, and an untouched map never sprouts. Each missing tree sprouts with chance 5 s / `regrow_delay` per pass; a regrow delay of 0 turns sprouting off. A cell is skipped under a player or a mob, on a structure, a bridge, a plant or stump, water, or beach sand with biomes on. The host sends `apply_sprout_cells(cells)` once per pass (applied only from peer 1); sprouts are `"sprout"` entries in the cut list, so saves and joining peers get them. Shares and their derivation: [biomes.md](../../../../docs/biomes.md), Target tree share.

## Sub-features

- `sprout-target` a pass at chance 1 sprouts exactly the missing trees, more passes add none, an area still at its share after a loss sprouts none, and a chopped sprout regrows as itself.
- `sprout-blocked` no candidate cell is under a player or mob, on a structure, bridge, plant, stump, water, or beach sand.
- `sprout-sync` one `apply_sprout_cells` per pass, a client applies it only from the host and then shows the host's map; a peer joining later gets the sprouts.

## How to get to it (user POV)

- Host, chop a few trees near the spawn, build a guard post on the stumps, and wait out about one regrow delay (300 s): new trees appear on free cells nearby, on every screen.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost per run (with `--only=`, against ~1.6 s for runner start-up): `test_sprouts_stop_at_target` ~1.1 s, `test_sprouts_skip_blocked_cells` ~0.3 s, `test_sprout_sync_one_rpc` ~0.4 s, `test_sprout_sync_late_join` ~0.3 s, `test_sprout_sync_two_players` ~6.5 s (it waits for a 5 s sprout pass). Only `test_sprout_sync_two_players` opens real peers, so it is the one the Netcode stress job runs, at ~8 s worst per run.

- **Run.** `godot --headless --path . --script res://tests/run_tests.gd -- --only=sprouts_stop_at_target,sprouts_skip_blocked_cells,sprout_sync_one_rpc,sprout_sync_late_join,sprout_sync_two_players` with scratch `XDG_*` dirs. Two processes: `python3 tools/stress_netcode.py -n 10 --only sprout_sync_two_players`.
- **What the tests do.** `tests/mechanics/trees/test_tree_sprouts.gd` finds, on a biome-off seed, a guard post spot over chopped trees in an area short of its target, then drives `sprout_pass` directly. `tests/net/test_sprout_sync.gd` reuses that map with the `FakeApi` stand-in of `test_regrow_batch.gd`, and in `test_sprout_sync_two_players` hosts a save with those trees cut through `tests/cut_sync_probe.gd` (`--place` builds the post, `PATH.regrow` turns sprouting on once a client has joined).
- **Proof.** `PASS test_sprouts_stop_at_target (82 trees, target 82, 3 lost, 3 sprouted)`, `PASS test_sprouts_skip_blocked_cells`, `PASS test_sprout_sync_one_rpc (3 sprouts in 1 RPC)`, `PASS test_sprout_sync_late_join (3 sprouts in 1 join message(s))`, `PASS test_sprout_sync_two_players (N sprouts on host, client and late joiner)`.

## Gotchas

- The tests read `BiomeCatalog.TREE_SHARE` and `TreeSprouts` through `load()`, so on a tree without them they fail with a message instead of a parse error that would hang the runner.
- The client draws all 3x3 chunks of the area before it applies the sprouts, or the cells it compares are not drawn yet.
- OCEANIC's share rounds down to 0 trees in any area, so it never sprouts.
