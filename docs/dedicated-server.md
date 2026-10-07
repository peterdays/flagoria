# Dedicated-server spike (Godot 4.1.4)

Time-boxed findings for a headless dedicated server, plus the dedicated-server boot path that followed the spike (`-- --server`, see [Dedicated server boot](#dedicated-server-boot)).

## Go / no-go

**Conditional go** on the engine. **No-go** on shipping a dedicated server from product code alone.

Godot 4.1.4 can run headless, bind ENet on UDP, and accept peers. At spike time Flagoria was a listen-server only: Main Menu Host always spawns a local player. The `-- --server` boot path now hosts headless without a local player. There is still no `export_presets.cfg` and no export templates on the verification host, and two GUI clients moving on a headless host have not been proven.

## Environment

- Engine: Godot 4.1.4 stable (`$GODOT --version` reports `4.1.4.stable.official…`)
- Project feature tags include `4.1` and `Mobile`
- Product networking: `ENetMultiplayerPeer`, port `9786` in `flagoria_main.gd`

Run commands from the repo root with `GODOT` set to the 4.1.4 editor binary.

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
- The 4.1.4 binary includes dedicated-server export support (`dedicated_server`, editor string "Export as dedicated server").

### This repo and host

- No `export_presets.cfg` in the repository.
- No Godot export templates installed in the usual user templates location on the verification host.

Attempt:

```bash
"$GODOT" --headless --path . --export-release "Dedicated Server" "$TMPDIR/flagoria_ds"
```

Result:

```text
ERROR: This project doesn't have an `export_presets.cfg` file at its root.
Create an export preset from the "Project > Export" dialog and try again.
```

Conclusion: for server spikes, `$GODOT --headless --path .` (editor binary plus project) is enough and matches CI. A Linux Dedicated Server export needs an export preset plus Linux server or headless templates. Those were not available here and are not committed by this spike.

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

Headless ENet listen and peer connect work on 4.1.4 without a GPU.

Not shown: two Flagoria game clients moving on a headless dedicated host. That needs product boot and RPC work. In-game Host/Join on two GUI instances remains the supported play path (README two-player checklist).

## Dedicated server boot

After import, start a dedicated server from the repo root:

```bash
"$GODOT" --headless --path . -- --server
"$GODOT" --headless --path . -- --server --port 9799
```

`--port N` and `--port=N` are accepted. The default is UDP `9786`. On success the log shows:

```text
Dedicated server listening on UDP port 9786
```

What the boot does (`start_dedicated_server` in `flagoria_main.gd`):

- Hides the main menu and spawns no local player (no node `1` under `World`).
- Calls `setup_server` with the current `MapGen.params`, the same path as Main Menu Host. Seeds left at 0 are randomized.
- Generates the origin chunk.
- Joining clients get a player and the full map params through the existing Join path (`receive_map_params`).

A port outside 1 to 65535, or a port that cannot be bound, logs an error and exits `1`. A launch without `--server` behaves as before.

The server runs until it is stopped. SIGTERM ends the process without a graceful shutdown (exit `143`). There is no quit command yet.

Clients join with Main Menu Join. Join always uses port `9786`, so a server on another port cannot be reached from the GUI yet.

`test_dedicated_server_join` in `tests/run_tests.gd` starts a `-- --server` process, joins it through the main scene's Join path, and checks that the client gets map params and its own player and that the host has no node `1`. Waits are bounded at 30 seconds, and the server process is killed at the end.

## 5. CPU and memory (rough)

Single samples on the verification host (not a full bench):

| Process | RSS (approx) | CPU (approx, short sample) |
| --- | --- | --- |
| Throwaway headless ENet server (idle) | ~81 MiB | ~7-8% during startup |
| Flagoria `$GODOT --headless --path .` (idle main menu) | ~93 MiB | ~8% during startup |

Idle dedicated hosting should be close to headless editor plus project. Two real game clients were not automated here.

## 6. Docker

`docker` was not available (`docker: command not found`). Feasibility note only:

- Likely image layout: Linux Godot 4.1.4 headless or editor binary, or a dedicated-server export plus `.pck`, run `--headless --path` or the exported binary, publish UDP `9786`.
- Blocked here by: no export preset or templates, and no Docker CLI to prove a build.

## 7. Engine upgrade blockers

None found for headless ENet on 4.1.4. `--headless`, `ENetMultiplayerPeer`, and cmdline user args behave as needed.

Blockers are product and process, not engine version:

1. No export preset or templates for a slim dedicated binary.
2. No automated two-player smoke yet (tracked elsewhere).

The listen-server-only flow and the missing server-mode flag were blockers at spike time. `-- --server` addresses both.

## Verification

- `./tools/verify.sh` on this docs branch passed (docs-only; map characterization is on current `main`).
- When `.cursor/skills/verify-flagoria/` is present, run Doctor then Drive verify.

## Suggested next steps

1. Prove two GUI clients moving and fighting on a `-- --server` host.
2. Add a clean quit for the server (signal or command), and a way for Join to use a non-default port.
3. Add a Linux dedicated-server export preset once templates are installed; document UDP `9786`.
4. Automate the two-player smoke against the headless host.

## Acceptance vs this doc

| Criterion | Status |
| --- | --- |
| Commands and logs for headless and ENet | Documented above |
| Headless process boots as a server without a local player | Yes (`-- --server`, automated test) |
| Headless process accepts a game client that gets map params | Yes (automated test, one client) |
| Headless process accepts two game clients that see each other move | Not proven (manual GUI check pending) |
| In-game Host/Join unchanged | Yes (GUI launch takes no new path without `--server`) |
