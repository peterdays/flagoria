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

- Two display-capable game processes for the GUI checklist; none for the headless peer tests or the two-launch drive.
- `doctor.sh` exits `0`.

- **Automated today.** Tests start a second headless Godot as a dedicated server and join it (`test_dedicated_server_join` and `test_two_player_smoke`, a server and two clients that see each other move, in `tests/net/`, `test_mob_*_two_players` and `test_mobs_sync_to_peer` in `tests/mobs/`), which proves ENet join, param sync and player spawn on both peers. It does **not** click the menu Host/Join buttons; do not mark the GUI path of `mp-host` / `mp-join` verified from verify.sh alone. See [Dedicated server](./dedicated-server.md).
- **Drive (two launches, #283).** Start two `bin/launch.sh` runs, each with its own scratch XDG dirs and its own PID from its `launch:` line:
  - Host drive: `start_game()` (presses `CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/HostButton`), waits until two player nodes are under `World`, prints them and the seeds from `world_params`, waits a few seconds so the client can finish, then `done()`.
  - Client drive, started a few seconds later: loads the main scene, leaves `CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/AddressEntry` empty (localhost), clicks `CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinButton`, waits until two player nodes are under `World` and `world_params` arrived, prints the same, then `done()`.
  - Time cost: ~8 s for the pair, most of it the stagger and the host's wait.
- **Proof (two launches).** Both `game.log` files list the same two player nodes under `World` (`1` and the client's peer id) and the same map seeds (`altitude_seed`, `moisture_seed`, `temperature_seed`, `items_seed`), and both launches exit `0`.
- **Manual.** Run two instances; complete the README checklist (host, join, move, attack, regen, death).
- **Placeholder #45.** The two-launch drive clicks the menu buttons but is not run in CI; the full CI smoke stays with #45.
- **Proof.** For manual runs: short note in `artifacts/out/e2e-summary.txt` that checklist steps passed. For #45: attach the smoke log path.

## Gotchas

- Transport is `ENetMultiplayerPeer` on port `9786` (UDP). Firewall/VPN must allow it for remote friends.
- Host params must sync to the client; a map mismatch means RPC/params regress.
- Never `pkill` by process name during cleanup — only recorded PIDs.
- Both launches use UDP port `9786`; two pairs at once on one machine clash, so run one pair at a time.
- The client drive cannot use `start_game()`, which presses Host; it waits for `JoinButton` itself and prints its own `VERIFY_READY` line.
