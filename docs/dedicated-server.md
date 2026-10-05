# Dedicated-server spike (Godot 4.1.4)

Time-boxed findings for a headless dedicated server. **No game code was changed** in this spike. Real implementation belongs in a follow-up issue.

**Go / no-go:** **Conditional go** for engine capability; **no-go for shipping** a dedicated server on current product code alone. Godot 4.1.4 can run headless, bind ENet UDP, and accept peers. Flagoria today is a **listen-server** (Host from the main menu always spawns a local player). There is no headless auto-host path, no `export_presets.cfg`, and no export templates on the verification machine. Meeting “two game clients join a headless process and see each other move” needs the dedicated-server boot work (follow-up), not an engine upgrade.

Part of the multiplayer-server track.

---

## Environment

- Engine: Godot **4.1.4** stable (`$GODOT --version` → `4.1.4.stable.official…`)
- Project targets `config/features=PackedStringArray("4.1", "Mobile")`
- Networking in product code: `ENetMultiplayerPeer`, listen port **9786** (`flagoria_main.gd`)

Commands below assume repo root as cwd and `GODOT` set to the 4.1.4 editor binary.

---

## 1. Headless project launch

After a normal import (`./tools/verify.sh` or editor `--quit`), the project starts headless:

```bash
timeout 15 "$GODOT" --headless --path .
```

**Result:** exit `0`. Engine banner only; main scene loads (main menu). No window/GPU required (`--display-driver headless` / dummy audio).

**Product gap:** headless launch does **not** call `create_server`. Hosting still requires the Main Menu **Host** path (`setup_server` → `enet_peer.create_server(PORT)`), which also adds the host as a player. There is no `--server` (or similar) boot flag in game code yet.

Without prior import, the first headless open can fail to load `flagoria_main.tscn` until resources are imported — same as CI’s import step.

---

## 2. Dedicated Server export mode vs editor `--headless --path`

### What the engine supports

- `$GODOT --help` documents `--headless` and export flags.
- The 4.1.4 binary includes dedicated-server export support (`dedicated_server` / “Export as dedicated server” in the editor plugin).

### What this repo / machine have

- **No** `export_presets.cfg` in the repository.
- **No** Godot export templates installed under the usual user templates location on the verification machine.

Attempt:

```bash
"$GODOT" --headless --path . --export-release "Dedicated Server" /tmp/flagoria_ds
```

**Result:**

```text
ERROR: This project doesn't have an `export_presets.cfg` file at its root.
Create an export preset from the "Project > Export" dialog and try again.
```

**Conclusion:** For day-to-day server spikes, **`$GODOT --headless --path .` (editor binary + project)** is enough and matches CI. A Linux “Dedicated Server” export is desirable later for smaller images, but needs an export preset plus Linux server/headless templates — not available here, and not committed by this spike.

---

## 3. Startup options (`OS.get_cmdline_user_args()`)

Godot forwards args after `--` to user code:

```bash
"$GODOT" --headless --script <throwaway_script> -- --server --port=9786
```

Observed (throwaway script, not in repo):

```text
USER_ARGS=["--server", "--port=9786"]
```

**Recommendation for follow-up:** parse user args (e.g. `--server`) in a boot path to call `create_server` without opening the menu / without a local player. Not implemented here (no game code).

---

## 4. ENet UDP 9786 under headless (throwaway)

Minimal throwaway project outside the game repo confirmed:

| Step | Result |
|---|---|
| `ENetMultiplayerPeer.create_server(9786)` headless | `CREATE_SERVER_ERR=0`, `SERVER_BOUND port=9786` |
| OS listen check | UDP `*:9786` owned by the Godot process |
| Second process `create_client("127.0.0.1", 9786)` | `CREATE_CLIENT_ERR=0`, client sees `PEERS=[1]`, `CLIENT_DONE connected=true` |

So **headless ENet listen + peer connect works on 4.1.4** without a GPU.

**Not demonstrated:** two **Flagoria** game clients moving on a headless dedicated host. That requires product boot/RPC changes (follow-up). In-game Host/Join on two GUI instances remains the supported play path today (README checklist).

---

## 5. CPU / memory (rough)

Single samples on the verification machine (not a bench suite):

| Process | RSS (approx) | CPU (approx, short sample) |
|---|---|---|
| Throwaway headless ENet server (idle) | ~81 MiB | ~7–8% during startup sample |
| Flagoria `$GODOT --headless --path .` (idle main menu) | ~93 MiB | ~8% during startup sample |

Idle dedicated hosting should be in the same ballpark as headless editor+project. Two real game clients were not automated here.

---

## 6. Docker

`docker` was **not available** on the verification machine (`docker: command not found`). Feasibility note only:

- Likely image: Linux Godot 4.1.4 headless/editor binary or a dedicated-server export + `.pck`, run `--headless --path` or the exported binary, publish **UDP 9786**.
- Blocked today by: no dedicated boot path in game code, no export preset/templates in this environment, no Docker CLI to prove an image build.

---

## 7. Engine upgrade blockers?

**None found for headless ENet itself on 4.1.4.** `--headless`, `ENetMultiplayerPeer`, and cmdline user args behave as needed.

Blockers are **product/process**, not engine version:

1. Listen-server-only flow (Host = local player).
2. No server-mode CLI flag wired up.
3. No export preset / templates for a slim dedicated binary.
4. No automated two-player smoke yet (tracked elsewhere).

---

## Verification

- `./tools/verify.sh` on this docs branch: passed (docs-only change; includes map characterization on current `main`).
- Use `.cursor/skills/verify-flagoria/` when that skill is present on the branch under test (Doctor → Drive verify).

---

## Suggested next steps (follow-up implementation)

1. Add a headless `-- --server` boot that calls `create_server` and does **not** spawn a local player.
2. Add a Linux dedicated-server export preset once templates are installed; document UDP `9786`.
3. Prove two GUI clients against that headless host (then automate as two-player smoke).

---

## Acceptance vs this doc

| Criterion | Status |
|---|---|
| Commands/logs for headless + ENet | Documented above |
| Headless process accepts two **game** clients that see each other move | **Not met** without game changes |
| In-game Host/Join unchanged | Yes (no game code touched) |

Therefore this PR documents the spike; it does **not** fully close the spike issue’s playable acceptance line.
