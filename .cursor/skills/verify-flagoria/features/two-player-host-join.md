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

- Two display-capable game processes (or a future #45 harness).
- `doctor.sh` exits `0`.

- **Automated today.** Limited: headless verify loads the main scene and map code paths but does **not** click Host/Join or spawn two peers. Do not mark `mp-host` / `mp-join` verified from verify.sh alone.
- **Manual.** Run two instances; complete the README checklist (host, join, move, attack, regen).
- **Placeholder #45.** When an automated two-player smoke exists, drive it from CI and record peer connect logs here.
- **Proof.** For manual runs: short note in `artifacts/e2e-summary.txt` that checklist steps passed. For #45: attach the smoke log path.

## Gotchas

- Transport is `ENetMultiplayerPeer` on port `9786` (UDP). Firewall/VPN must allow it for remote friends.
- Host params must sync to the client; a map mismatch means RPC/params regress.
- Never `pkill` by process name during cleanup — only recorded PIDs.
