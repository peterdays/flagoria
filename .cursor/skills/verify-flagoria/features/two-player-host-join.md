# Two-player Host/Join

Two-player Host/Join starts a listen-server on one instance and connects a second instance so both players share one map.

## Sub-features

- `mp-host` Main Menu → Host creates the server (UDP port `9786`) and spawns the host player.
- `mp-join` Main Menu → Join (empty address = localhost) connects and receives map params from the host.
- `mp-move-attack-regen` both players move, attack, and regenerate (manual checklist).

## How to get to it (user POV)

- Instance A: Host. Instance B: Join with empty address or the host address.
- Follow the README **Two-player play-test checklist** when present.

## Driving it with verify-flagoria helpers

Preconditions:

- Two display-capable game processes for the GUI checklist; none for the headless peer tests.
- `doctor.sh` exits `0`.

- **Automated today.** Tests start a second headless Godot as a dedicated server and join it (`test_dedicated_server_join` in `tests/net/`, `test_mob_*_two_players` and `test_mobs_sync_to_peer` in `tests/mobs/`), which proves ENet join, param sync and player spawn on both peers. It does **not** click the menu Host/Join buttons; do not mark the GUI path of `mp-host` / `mp-join` verified from verify.sh alone. See [Dedicated server](./dedicated-server.md).
- **Manual.** Run two instances; complete the README checklist (host, join, move, attack, regen, death).
- **Placeholder #45.** The remaining gap is a scripted menu Host/Join between two instances in CI.
- **Proof.** For manual runs: short note in `artifacts/out/e2e-summary.txt` that checklist steps passed. For #45: attach the smoke log path.

## Gotchas

- Transport is `ENetMultiplayerPeer` on port `9786` (UDP). Firewall/VPN must allow it for remote friends.
- Host params must sync to the client; a map mismatch means RPC/params regress.
- Never `pkill` by process name during cleanup — only recorded PIDs.
