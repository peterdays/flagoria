# Dedicated-server spike (Godot 4.1.4)

Time-boxed findings for a headless dedicated server. No game code was changed. Implementation belongs in a follow-up issue.

## Go / no-go

**Conditional go** on the engine. **No-go** on shipping a dedicated server from product code alone.

Godot 4.1.4 can run headless, bind ENet on UDP, and accept peers. Flagoria today is a listen-server: Main Menu Host always spawns a local player. There is no headless auto-host path, no `export_presets.cfg`, and no export templates on the verification host. Getting two Flagoria clients onto a headless host so they see each other move needs dedicated-server boot work, not an engine upgrade.

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

Result: exit `0`. Engine banner only. The main scene loads (main menu). No window or GPU (`--headless` uses the headless display driver and dummy audio).

Product gap: headless launch does not call `create_server`. Hosting still goes through Main Menu Host (`setup_server` then `enet_peer.create_server(PORT)`), which adds the host as a player. There is no `--server` (or similar) boot flag in game code.

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

Follow-up: parse user args such as `--server` in a boot path that calls `create_server` without the menu and without a local player. Not implemented here.

## 4. ENet UDP 9786 under headless (throwaway)

A minimal throwaway project outside the game repo showed:

| Step | Result |
| --- | --- |
| `ENetMultiplayerPeer.create_server(9786)` headless | `CREATE_SERVER_ERR=0`, `SERVER_BOUND port=9786` |
| OS listen check | UDP `*:9786` owned by the Godot process |
| Second process `create_client("127.0.0.1", 9786)` | `CREATE_CLIENT_ERR=0`, client sees `PEERS=[1]`, `CLIENT_DONE connected=true` |

Headless ENet listen and peer connect work on 4.1.4 without a GPU.

Not shown: two Flagoria game clients moving on a headless dedicated host. That needs product boot and RPC work. In-game Host/Join on two GUI instances remains the supported play path (README two-player checklist).

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
- Blocked here by: no dedicated boot path in game code, no export preset or templates, no Docker CLI to prove a build.

## 7. Engine upgrade blockers

None found for headless ENet on 4.1.4. `--headless`, `ENetMultiplayerPeer`, and cmdline user args behave as needed.

Blockers are product and process, not engine version:

1. Listen-server-only flow (Host equals local player).
2. No server-mode CLI flag wired up.
3. No export preset or templates for a slim dedicated binary.
4. No automated two-player smoke yet (tracked elsewhere).

## Verification

- `./tools/verify.sh` on this docs branch passed (docs-only; map characterization is on current `main`).
- When `.cursor/skills/verify-flagoria/` is present, run Doctor then Drive verify.

## Suggested next steps

1. Add a headless `-- --server` boot that calls `create_server` and does not spawn a local player.
2. Add a Linux dedicated-server export preset once templates are installed; document UDP `9786`.
3. Prove two GUI clients against that headless host, then automate as two-player smoke.

## Acceptance vs this doc

| Criterion | Status |
| --- | --- |
| Commands and logs for headless and ENet | Documented above |
| Headless process accepts two game clients that see each other move | Not met without game changes |
| In-game Host/Join unchanged | Yes (no game code touched) |

This PR records the spike. It does not fully meet the playable acceptance line on the issue.
