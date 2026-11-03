# Regrowth sync messages

In multiplayer the host alone decides when a stump regrows (#298), and tells every peer in one message per regrowth tick (#353). `TileMap.regrow_due` emits `plants_regrown(cells)` once, with every cell that regrew in that tick, and nothing when none did. `Interaction._on_plants_regrown` (`Scripts/mechanics/interact/interaction.gd`) sends `apply_regrow_cells(cells)` to every peer, so a tick where many stumps come due (for example after loading a world) is still one RPC per peer. The receiving handler regrows each listed cell with `TileMap.grow_back` only when `multiplayer.get_remote_sender_id()` is 1 (the host); any other sender is ignored, so the rule holds even if the RPC mode (`authority`) changes. The rest of cut and regrowth sync (who regrows, join lists, ages) is in [Cut sync](./cut-sync.md).

## Sub-features

- `regrow-batch` a host with a peer connected sends one `apply_regrow_cells` per `regrow_due` tick, to every peer, listing every cell that regrew; a tick with nothing due sends nothing. A client applying that message shows the same plants as the host.
- `regrow-host-only` a client's `apply_regrow_cells` handler applies nothing when the sender is not peer 1 (another client, or a local call with sender 0), and regrows every listed cut when the host sent it.

## How to get to it (user POV)

- Host and join, cut several trees close together, and wait out the regrow delay (300 s): they grow back on both screens at the same moment.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_regrow_one_rpc_per_tick` and `test_regrow_refuses_non_host` each add about 0.2 s to `tools/verify.sh` (~2.1 s alone with `--only=`, against ~1.9 s for runner start-up). Both run in one process with a `MultiplayerAPIExtension` stand-in and open no network peer, so they add nothing to the Netcode stress job. The two-process proof is `test_regrow_sync_two_players` in [Cut sync](./cut-sync.md), unchanged in cost.

- **Run.** `godot --headless --path . --script res://tests/run_tests.gd -- --only=regrow_one_rpc_per_tick,regrow_refuses_non_host` with scratch `XDG_*` dirs, or `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`. Two processes: `python3 tools/stress_netcode.py -n 10 --only regrow_sync_two_players`.
- **What the tests do.** `tests/net/test_regrow_batch.gd` loads the main scene with a stand-in `MultiplayerAPI` (`FakeApi`: a connected host with one peer, or client 2, that records RPCs and reports a chosen sender), cuts four plants near the origin on the first of a few seeds that has them, and moves play time past the 30 s delay. The batch test calls `regrow_due` once and reads the recorded RPCs, then applies the recorded message on a client scene of the same map. The guard test calls `apply_regrow_cells` as peers 3, 0 and 1.
- **Proof.** `PASS test_regrow_one_rpc_per_tick (4 cells, 1 RPC)` and `PASS test_regrow_refuses_non_host`.

## Gotchas

- `MultiplayerAPI.is_server()` is `get_unique_id() == 1`, and `Interaction.multiplayer_on` needs a peer whose status is connected, so the stand-in returns a `MultiplayerPeerExtension` that always reports `CONNECTION_CONNECTED`.
- The stand-in skips the engine's own RPC-mode check, which is what lets the guard test reach the handler with a non-host sender; between real peers the engine refuses a non-host `apply_regrow_cells` first (the forged message in `test_regrow_sync_two_players`).
