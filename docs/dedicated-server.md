# Dedicated server

Time-boxed findings for a headless dedicated server, plus the dedicated-server boot path that followed the spike (`-- --server`, see [Dedicated server boot](#dedicated-server-boot)).

**Current state.** The project targets Godot 4.7 (feature tags `4.7`, `Mobile`). The spike checks below were re-run on Godot 4.7.2 with the same results unless a section says otherwise. Since the spike, `-- --server` boots a headless host with no local player, and `test_dedicated_server_join` in `tests/run_tests.gd` proves that a client can join it. `export_presets.cfg` now exists but has only the Android preset. There is still no dedicated-server export preset.

## Go / no-go

**Conditional go** on the engine. **No-go** on shipping a dedicated server from product code alone.

Godot 4.7.2 can run headless, bind ENet on UDP, and accept peers. At spike time Flagoria was a listen-server only: Main Menu Host always spawns a local player. The `-- --server` boot path now hosts headless without a local player. There is still no dedicated-server export preset. Two GUI clients moving and fighting on a headless host have still not been proven. Headless movement of two joiners is a different check: `test_two_player_smoke` (below).

## Environment

- Engine: Godot 4.7.2 stable (`$GODOT --version` reports `4.7.2.stable.official…`)
- Project feature tags include `4.7` and `Mobile`
- Product networking: `ENetMultiplayerPeer`, port `9786` in `flagoria_main.gd`

Run commands from the repo root with `GODOT` set to the 4.7.x editor binary.

## 1. Headless project launch

After import (`./tools/verify.sh` or `$GODOT --headless --path . --editor --quit`), start the project headless:

```bash
timeout 15 "$GODOT" --headless --path .
```

Result: exit `124`. The project does not quit on its own, so `timeout` stops it after 15 seconds and reports 124. Output is the engine banner only. The main scene loads (main menu). No window or GPU (`--headless` uses the headless display driver and dummy audio).

Without `-- --server`, a headless launch does not call `create_server`. GUI hosting goes through Main Menu Host (`setup_server`, then `enet_peer.create_server(PORT)`), which adds the host as a player.

Without a prior import, the first headless open can fail to load `flagoria_main.tscn` until resources are imported. That matches the CI import step.

## 2. Dedicated Server export vs editor `--headless --path`

### Engine support

- `$GODOT --help` documents `--headless` and the export flags.
- The 4.7.2 binary includes dedicated-server export support (`dedicated_server` preset option, editor string "Export as dedicated server").

### This repo and host

- `export_presets.cfg` has one preset, `Android` (`dedicated_server=false`). There is no Linux or dedicated-server preset.
- Godot 4.7.2 export templates are installed on the verification host.

Attempt:

```bash
"$GODOT" --headless --path . --export-release "Dedicated Server" "$TMPDIR/flagoria_ds"
```

Result:

```text
ERROR: Invalid export preset name: Dedicated Server.
The following presets were detected in this project's `export_presets.cfg`:
```

Conclusion: for server spikes, `$GODOT --headless --path .` (editor binary plus project) is enough and matches CI. A Linux Dedicated Server export needs a Linux preset with `dedicated_server=true`. None is committed yet.

## 3. Startup options (`OS.get_cmdline_user_args()`)

Godot forwards arguments after `--` to user code:

```bash
"$GODOT" --headless --script <throwaway_script> -- --server --port=9786
```

Observed from a throwaway script (not in the repo):

```text
USER_ARGS=["--server", "--port=9786"]
```

`flagoria_main.gd` reads these arguments for the dedicated-server boot below.

## 4. ENet UDP 9786 under headless (throwaway)

A minimal throwaway project outside the game repo showed:

| Step | Result |
| --- | --- |
| `ENetMultiplayerPeer.create_server(9786)` headless | `CREATE_SERVER_ERR=0`, `SERVER_BOUND port=9786` |
| OS listen check | UDP `*:9786` owned by the Godot process |
| Second process `create_client("127.0.0.1", 9786)` | `CREATE_CLIENT_ERR=0`, client sees `PEERS=[1]`, `CLIENT_DONE connected=true` |

Headless ENet listen and peer connect work on 4.7.2 without a GPU. Re-run on a free port when 9786 is already taken by another local server.

Headless movement of two joiners is `test_two_player_smoke` in `tests/net/test_two_player_smoke.gd`, run by `./tools/verify.sh`. It starts one `--dedicated` process and two headless clients (`tests/late_join_probe.gd`). Client A holds an input action (`ui_right`, `ui_left`, `ui_down`, or `ui_up`) until it has moved at least 4 px. The server and client B then see A within 1 px of where A has itself. The test does not click Main Menu Host or Join. Two humans at two GUI windows, a cut seen by the other client, and a sword hit seen by the other client are not this test. The menu Host/Join pair `drives/two_player/` clicks those buttons and is not this CI test. The Join-port drive `drives/join_port.gd` clicks Join only, against a dedicated server, and checks that server's map seeds and nearby ground; it is one client, not two humans.

## Dedicated server boot

After import, start a dedicated server from the repo root:

```bash
"$GODOT" --headless --path . -- --server
"$GODOT" --headless --path . -- --server --port 9799
```

`--port N` and `--port=N` are accepted. The default is UDP `9786`. `--params <file>` (or `--params=<file>`) hosts the map in a map save (`MapSave`, `.json`; `user://`, `res://` or an absolute path):

```bash
"$GODOT" --headless --path . -- --server --params /srv/flagoria/island.json
```

Without `--params` the server uses the current `MapGen.params`. On success the log shows:

```text
Dedicated server listening on UDP port 9786
```

What the boot does (`start_dedicated_server` in `flagoria_main.gd`):

- Hides the main menu and spawns no local player (no node `1` under `World`).
- Calls `setup_server` with the `--params` map save, or else the current `MapGen.params`, the same path as Main Menu Host. Seeds left at 0 are randomized.
- Generates the origin chunk. `with_castle` is false, so this boot does not place a starting castle. That is intentional: a dedicated host has no local player.
- Joining clients get a player and the full map params through the existing Join path (`receive_map_params`).

A port outside 1 to 65535, a port that cannot be bound, or a `--params` file that is missing or not a map save logs an error and exits `1`. A launch without `--server` behaves as before.

The server runs until it is stopped. `kill -TERM <pid>` closes ENet, prints one line `Dedicated server stopped.`, and exits 0. A joined client returns to the main menu. The dedicated path does not call UPnP. A laptop LAN runbook is [Laptop dedicated server](laptop-dedicated-server.md): default UDP `9786`, optional `--port`, and the machine's LAN IPv4. That LAN join is manual, not a CI gate. Friends off that LAN use [Private VPN access](private-server.md). The process still has no bind flag; the VPN address and the host firewall are a manual step.

`--params <file>` loads generation parameters only. Cuts, bridges, structures, and walls are not restored, and the server does not autosave (#15).

Current limits of this boot, not open bugs to fix in this note:

- No starting castle, as above (`setup_server(..., with_castle)` is false).
- Chunk refresh on a peer follows `World/<that peer's unique id>` (`TileMap._process`). The dedicated server is peer 1 and has no player node, so it does not move its chunk center after someone joins. A listen host refreshes around peer 1 only, not around remote players.
- Cities do nothing while `Interaction.multiplayer_on` is true. Tower capture and flags-held points run on the host and replicate to peers (#497). A client does not advance either.

Clients join with Main Menu Join. A blank address uses `localhost` on UDP `9786`. A hostname or an IPv4 address may include `:port` (`127.0.0.1:9799`, `localhost:9799`); a bare host keeps port `9786`. The typed text stays in the address field and in `Could not join …`. A missing host, a non-numeric port, or a port outside 1 to 65535 is rejected on the menu before any connection attempt. An address with more than one colon (such as `::1`) is rejected instead of being read as a host and a port.

`drives/join_port.gd` clicks that Join button. For a blank address it waits until `world_params` are the dedicated server's seeds (not the client's local map fixture) and 81 of 81 nearby layer-0 cells are drawn (`ground=81/81`). It then returns to the menu and does the same for `127.0.0.1:9799` against a server on 9799. That drive is one client. It does not press Host, and it does not show a second human, a synced cut, or a synced sword hit.

`test_dedicated_server_join` in `tests/net/test_dedicated_server.gd` starts a `-- --server` process, joins it through the main scene's Join path, and checks that the client gets map params and its own player and that the host has no node `1`. Waits are bounded at 30 seconds, and the server process is killed at the end. `test_dedicated_server_params_file` starts one with `--params` on a byte copy of the save and checks that the joining client gets exactly the saved params, and that a missing file exits `1`. `test_params_mount_copy` checks that byte copy, and that version 1 and 2 files still load, without starting a server.

## 5. CPU and memory (rough)

Single samples on the verification host (not a full bench):

| Process | RSS (approx) | CPU (approx, short sample) |
| --- | --- | --- |
| Throwaway headless ENet server (idle) | ~104 MiB | ~29% during startup |
| Flagoria `$GODOT --headless --path .` (idle main menu) | ~123 MiB | ~15% during startup |

Idle dedicated hosting should be close to headless editor plus project. Two real GUI clients were not sampled here. Headless movement of two joiners is `test_two_player_smoke`, not this spike.

## 6. Docker

[Docker dedicated server](docker-dedicated-server.md) is the container path: the official Godot 4.7.2 Linux editor, `--headless -- --server`, UDP `9786`, a read-only generation-params mount, and at most three restarts after a crash. It is not an export preset and it does not keep world changes. The bare `godot -- --server` command in [Laptop dedicated server](laptop-dedicated-server.md) is still the path without Docker. `tools/docker_dedicated_smoke.sh` is the loopback build, join, params, and SIGTERM check.

## 7. Engine upgrade blockers

None found for headless ENet on 4.7.2. `--headless`, `ENetMultiplayerPeer`, and cmdline user args behave as needed.

Blockers are product and process, not engine version:

1. No dedicated-server export preset for a slim dedicated binary.
2. No GUI proof of two humans moving, cutting, or landing a sword hit on a headless host. The headless smoke is `test_two_player_smoke`.

The listen-server-only flow and the missing server-mode flag were blockers at spike time. `-- --server` addresses both.

## Verification

- Run `./tools/verify.sh`. It must print `All tests passed.` and `Verification passed.`, including `PASS test_two_player_smoke`.
- When `.cursor/skills/verify-flagoria/` is present, `./.cursor/skills/verify-flagoria/bin/check-map.sh` must exit 0. This feature file is `Drive: not player-facing`.

## Suggested next steps

1. Prove two GUI clients moving and fighting on a `-- --server` host. The headless input smoke does not do that.
2. SIGTERM quit is in place (`kill -TERM`, one `Dedicated server stopped.` line, exit 0). Join already accepts `host:port`.
3. Add a Linux dedicated-server export preset; document UDP `9786`.

## Acceptance vs this doc

| Criterion | Status |
| --- | --- |
| Commands and logs for headless and ENet | Documented above |
| Headless process boots as a server without a local player | Yes (`-- --server`, automated test) |
| Headless process accepts a game client that gets map params | Yes (automated test, one client) |
| Headless process accepts two headless clients; one walks with an input action and the server and the other client see that position | Yes (`test_two_player_smoke`). Not a GUI Host/Join click, and not a cut or a sword hit. |
| In-game Host unchanged; Join accepts an optional port | Yes. Host still listens on `9786`. `drives/join_port.gd` clicks Join for blank `localhost:9786` and for `127.0.0.1:9799`, and checks that server's seeds plus `ground=81/81`. One client. Two GUI humans are not that drive. |
