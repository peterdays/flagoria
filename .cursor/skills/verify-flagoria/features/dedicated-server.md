# Dedicated server

`-- --server [--port N]` boots a headless host with no local player that clients join through the normal Join path.

## Sub-features

- `ds-port` port parsing (`test_server_port_from_args`).
- `ds-join` a client joins a headless server and gets the map params and its own player.

## How to get to it (user POV)

- `godot --headless --path . -- --server --port 9799`, then Main Menu → Join on a GUI instance (details in `docs/dedicated-server.md`).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_server_port_from_args`, `-- test_dedicated_server_join` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- The join test picks a free UDP port and kills only the server it started.
- This is a partial step toward the CI two-player smoke in #45.
