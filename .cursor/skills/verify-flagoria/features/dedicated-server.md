# Dedicated server

Drive: not player-facing

`-- --server [--port N] [--params <file>]` boots a headless host with no local player that clients join through the normal Join path.

## Sub-features

- `ds-port` port parsing (`test_server_port_from_args`).
- `ds-join` a client joins a headless server and gets the map params and its own player.
- `ds-params` `--params <file>` hosts the map in that save (#193); a joining client gets exactly its params, and a missing file stops the server with exit 1 before it listens.
- `ds-two-move` `test_two_player_smoke`: one dedicated server and two headless clients. Client A holds an input action until it moves at least 4 px. The server and client B see that position. The test does not click Main Menu Host or Join.

## How to get to it (user POV)

- `godot --headless --path . -- --server --port 9799`, then Main Menu → Join `127.0.0.1:9799` (see [Join an address with an optional port](./join-port.md); details in `docs/dedicated-server.md`).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_server_port_from_args`, `-- test_dedicated_server_join`, `-- test_server_params_from_args`, `-- test_dedicated_server_params_file`, `-- test_two_player_smoke` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.` `test_two_player_smoke` is the CI move proof. It does not click Host or Join. The menu pair in [Two-player Host/Join](./two-player-host-join.md) is a different drive and is not this check. [Join an address with an optional port](./join-port.md) clicks Join for one client and checks server seeds plus rendered ground; it is not two humans and not `test_two_player_smoke`.

## Gotchas

- The join test picks a free UDP port and kills only the server it started.
- Dedicated boot passes `with_castle` false, so it places no starting castle. That is intentional.
- Chunk refresh follows `World/<local unique id>`. The dedicated server is peer 1 with no player node, so it does not follow joiners. A listen host refreshes around peer 1 only.
- Cities, tower capture, and flags-held points do nothing while a peer is connected (`Interaction.multiplayer_on`). Conquest runs only while the host is alone.
