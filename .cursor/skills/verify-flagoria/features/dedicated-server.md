# Dedicated server

Drive: not player-facing

`-- --server [--port N] [--params <file>]` boots a headless host with no local player that clients join through the normal Join path.

## Sub-features

- `ds-port` port parsing (`test_server_port_from_args`).
- `ds-join` a client joins a headless server and gets the map params and its own player.
- `ds-params` `--params <file>` hosts the map in that save (#193); a joining client gets exactly its params, and a missing file stops the server with exit 1 before it listens. A byte copy of a current gzip save loads the same way, and version 1 and 2 files still load (`test_params_mount_copy`). The file's generation params are what is hosted. Cuts, bridges, structures, and walls are not restored, and the server does not autosave (#15).
- `ds-quit` SIGTERM closes ENet, prints `Dedicated server stopped.` once, and exits 0 (`test_server_quit`). A client that joined with `add_player_joined` is back on the main menu within 6 s of SIGTERM. The dedicated path does not call UPnP.
- `ds-docker` the same process in a non-root image (`docs/docker-dedicated-server.md`). Generation params are a read-only mount. A crash restarts at most three times. Not a player drive.
- `ds-vpn` private VPN access is a manual runbook (`docs/private-server.md`). It is not a player drive and not a CI gate.

## How to get to it (user POV)

- `godot --headless --path . -- --server --port 9799`, then Main Menu → Join `127.0.0.1:9799` (see [Join an address with an optional port](./join-port.md); details in `docs/dedicated-server.md`).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_server_port_from_args`, `-- test_dedicated_server_join`, `-- test_server_params_from_args`, `-- test_dedicated_server_params_file`, `-- test_params_mount_copy`, `-- test_server_quit` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.` Time cost: `server_quit` ~4–8 s in verify, and about that for each netcode-stress run. `params_mount_copy` is file copies, under 0.2 s in verify.

## Gotchas

- The join test picks a free UDP port and kills only the server it started.
- This is a partial step toward the CI two-player smoke in #45.
