# Two-player Host/Join

Drive: drives/two_player/two_player_host.gd

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

- **Automated today.** `test_two_player_smoke` (`tests/net/test_two_player_smoke.gd`) starts one headless dedicated server and two headless clients. Client A holds an input action (`ui_right`, `ui_left`, `ui_down`, or `ui_up`) until it has moved at least 4 px. The server and client B see A within 1 px of where A has itself. `test_dedicated_server_join` is one client and map params. `test_mob_*_two_players` and `test_mobs_sync_to_peer` are headless mob sync. None of these click Main Menu Host or Join. Do not mark the GUI path of `mp-host` / `mp-join` verified from `./tools/verify.sh` alone. The Join-port drive in [Join an address with an optional port](./join-port.md) does click Join, for one client, and checks that server's seeds and nearby ground. It is not this pair and it does not prove two humans, a synced cut, or a synced sword hit. See [Dedicated server](./dedicated-server.md).
- **Drive (two launches, #283).** `drives/two_player/two_player_host.gd` and `drives/two_player/two_player_client.gd`. Start the host in the background, then the client about 4 s later, each with its own scratch XDG dirs and its own PID from its `launch:` line:
  ```bash
  bin/launch.sh drives/two_player/two_player_host.gd & sleep 4; bin/launch.sh drives/two_player/two_player_client.gd; wait
  ```
  - Host drive: `start_game()` (presses `CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/HostButton`), waits until two player nodes are under `World`, prints them and the seeds from `world_params`, waits a few seconds so the client can finish, then `done()`.
  - Client drive, started a few seconds later: loads the main scene, leaves `CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/AddressEntry` empty (localhost), clicks `CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinButton`, waits until two player nodes are under `World` and `world_params` arrived, prints the same, then `done()`.
  - Time cost: ~10 s for the pair, most of it the stagger and the host's 5 s linger.
- **Proof (two launches).** Both `game.log` files have a `two_player: host players=... seeds=...` (or `client`) line listing the same two player nodes under `World` (`1` and the client's peer id) and the same map seeds (`altitude_seed`, `moisture_seed`, `temperature_seed`, `items_seed`), and both launches exit `0`.
- **Manual.** Run two instances; complete the README checklist (host, join, move, attack, regen, death).
- **Placeholder #45.** The headless move smoke is `test_two_player_smoke` inside `./tools/verify.sh`. The two-launch drive clicks the menu buttons but is not run in CI. Two GUI humans cutting or landing a sword hit are still not proven.
- **Proof.** For manual runs: short note in `artifacts/out/e2e-summary.txt` that checklist steps passed. For #45: attach the smoke log path.

## Gotchas

- Transport is `ENetMultiplayerPeer` on port `9786` (UDP). Firewall/VPN must allow it for remote friends.
- Host params must sync to the client; a map mismatch means RPC/params regress.
- Never `pkill` by process name during cleanup — only recorded PIDs.
- Both launches use UDP port `9786`; two pairs at once on one machine clash, so run one pair at a time.
- The pair lives in `drives/two_player/`, not `drives/`, so `verify-drive.yml` (which runs each `drives/*.gd` alone) does not start half a pair.
- The client drive cannot use `start_game()`, which presses Host; it waits for `JoinButton` itself and prints its own `VERIFY_READY` line.
