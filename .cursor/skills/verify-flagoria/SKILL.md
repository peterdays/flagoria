---
name: verify-flagoria
description: "Verify Flagoria (Godot 4.7 island PvP): headless project load/parse/tests, map generation golden checks, and Map Settings / Host-Join surfaces via tools/verify.sh and optional xvfb screenshots. Use when proving a change to map gen, the admin panel, multiplayer boot, or before opening a PR."
---

# Verify Flagoria

Project-local verification for Flagoria. Read this cold mid-task. Prefer the feature map under `features/` for user-facing recipes. Always run **Doctor** before trusting a drive.

**Engine:** the latest stable Godot, which is the version in `project.godot` (`config/features`, currently `4.7`). When a newer stable Godot ships, move the project to it; older editors are not supported. The tools use `GODOT` if it is set, else `godot` on `PATH`, and refuse a binary whose `--version` does not match `project.godot`.

**Repo root:** every command below assumes the current working directory is the Flagoria checkout root (the directory that contains `project.godot` and `tools/verify.sh`).

**Scratch / evidence:**

| Path | Purpose |
|---|---|
| `.cursor/skills/verify-flagoria/artifacts/` | Proof outputs (logs, screenshots, summaries). **Survives cleanup.** |
| `.cursor/skills/verify-flagoria/.run/` | `pids` and one dir per launch (scratch user dirs, `game.log`). Gitignored; removed by cleanup. |

## Launch

`tools/verify.sh` and the drives below are short runs. For a gameplay drive, launch the real game and wait until it is usable:

```bash
./.cursor/skills/verify-flagoria/bin/launch.sh drives/wait.gd            # headless
./.cursor/skills/verify-flagoria/bin/launch.sh drives/wait.gd --display  # xvfb-run + opengl3
```

In a fresh checkout, import once first (`"$GODOT" --headless --path . --import`), as `tools/verify.sh` does.

The drive path is relative to the skill dir, to the repo, or a `res://` path. Each launch:

1. finds Godot (`GODOT` if set, else `godot` on `PATH`);
2. makes a fresh run dir `.run/<run-id>/` with empty `xdg/data`, `xdg/config` and `xdg/cache`, and exports `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` to them, so the game starts from an empty `user://` and never reads or writes the real one;
3. starts `godot --headless --path . --script <drive.gd>` in the background (with `--display`: under `xvfb-run -a` with `--rendering-driver opengl3`), logging to `.run/<run-id>/game.log`;
4. appends each exact PID to `.run/pids` as `<pid> <kind> <run-id> <path>`: the Godot PID, plus the `xvfb-run` PID with `--display`;
5. waits up to 60 s (`VERIFY_READY_TIMEOUT`) for the ready line, then prints `launch: run=<run-id> pid=<pid> log=...` and the ready line, and exits `0`.

**Ready line:** `VERIFY_READY pid=<pid> scene=res://flagoria_main.tscn`. The drive prints it only after the main scene is loaded, a game is started through the main menu's Host button and the local hero exists under `World`. A running process is not ready; a usable game is. `drives/wait.gd` does only this and then waits for cleanup (it quits on its own after 10 minutes).

If the game exits first, or the line does not come in time, launch exits non-zero with the log tail. On a timeout the game is still running: stop it with Cleanup.

Two launches side by side each get their own run dir, user dir and PID.

`drive-verify.sh` and `drive-map-settings-screenshot.sh` record their PIDs in `.run/pids` the same way, and the screenshot drive also runs from a scratch run dir.

For **visual** proof a display is required (`xvfb-run` and software GL, `llvmpipe`, are fine). If `xvfb-run` or a usable GL path is missing, skip visual drives and record the skip in evidence (do not fake screenshots).

## Doctor

Read-only. Run whenever anything looks off:

```bash
./.cursor/skills/verify-flagoria/bin/doctor.sh
```

Expect exit `0` and lines confirming: `GODOT` version matches the major.minor in `project.godot` `config/features` (currently `4.7`), `test_map_characterization` present in `tests/world/test_map_characterization.gd`, and repo root OK (`project.godot`, `tools/verify.sh`, `tests/run_tests.gd`). Fail if Godot is not found (`GODOT`, or `godot` on `PATH` when `GODOT` is unset), wrong major/minor, the characterization test is missing, or the checkout is not Flagoria.

### A launched instance

```bash
./.cursor/skills/verify-flagoria/bin/doctor.sh --instance <run-id>
```

Run it before the first drive step, after any failed step, and whenever a drive does something surprising. `<run-id>` is the `run=` value `launch.sh` printed. On top of the checks above, it checks every PID recorded for that run in `.run/pids`, and prints one `doctor: instance ok:` or `doctor: instance FAIL:` line per check:
- each PID is still running (not exited or a zombie);
- each `godot` PID runs the recorded Godot binary (`/proc/<pid>/exe`), whose `--version` matches `project.godot`;
- each `godot` PID has `XDG_DATA_HOME` inside `.run/<run-id>/xdg/`, so it is our instance and not a play session sharing a real `user://`;
- `.run/<run-id>/game.log` has the `VERIFY_READY` line, and no `SCRIPT ERROR` or `Node not found` after it.

It exits `0` only when all of them pass. It only reads `.run/` and `/proc`: it changes no file and sends no input. A failure means relaunch (Cleanup, then Launch), not retry the step.

## Drive

### Automated (primary)

```bash
./.cursor/skills/verify-flagoria/bin/drive-verify.sh
```

This runs `./tools/verify.sh` (import/load, parse every `.gd`, `godot --headless --script res://tests/run_tests.gd`, then the `render_biomes` and `audio_check` gates). Exit `0` and `Verification passed.` / `All tests passed.` are required.

Map characterization: the verify log must include `PASS test_map_characterization` (pinned atlas check). See `features/map-characterization.md`. Each other feature's proof is the `-- test_<name>` headers listed in its feature file.

### Visual Map Settings (optional)

```bash
./.cursor/skills/verify-flagoria/bin/drive-map-settings-screenshot.sh
```

Uses `xvfb-run` + `opengl3` and a short SceneTree script to open **Map Settings** and write `artifacts/out/map_settings.png`. `artifacts/out/` is gitignored, so the run leaves `git status` clean. The committed `artifacts/map_settings.png` is the reference image; replace it only on purpose, by copying the new capture over it. If xvfb/GL is unavailable, the script exits non-zero with a clear message — treat as skipped visual proof, not as a product regression, unless the change was UI-only.

### Two-player Host/Join

Not fully automatable without a GUI harness yet (placeholder: issue #45). What is feasible now:

- Headless: main scene loads inside verify / characterization (no Host click).
- Manual: follow the README two-player play-test checklist (Host, Join localhost, move, attack, regen) on two instances.

Do not claim two-player PvP was proven by verify.sh alone.

## Evidence

Proof standards:

- Exercise the real user/CI path (`tools/verify.sh`, Map Settings UI), not internal-only setters that skip the menu or RPC.
- Capture action + result (log excerpt + screenshot when visual).
- Side effects: for map golden, failing after a threshold edit is the mutation proof (do that only in a throwaway edit and revert).

After a successful verify drive, write a short summary:

```bash
./.cursor/skills/verify-flagoria/bin/evidence-summarize.sh
```

Artifacts live in `.cursor/skills/verify-flagoria/artifacts/` (for example `verify.log`, `out/e2e-summary.txt`, `out/map_settings.png`). **Cleanup must not delete this directory's proof files.** `evidence-summarize.sh` writes to the gitignored `artifacts/out/`. The committed `artifacts/e2e-summary.txt` is a reference example of the format and changes only on purpose.

## Cleanup

```bash
./.cursor/skills/verify-flagoria/bin/cleanup.sh
```

Run it after every launch or drive, including failed ones. It stops only PIDs listed in `.run/pids`, by exact PID, and only while each one is still the process that was launched:
- a `godot` PID must run the recorded Godot binary (`/proc/<pid>/exe`) with `XDG_DATA_HOME` in its own `.run/<run-id>/xdg/`;
- an `xvfb-run` or `verify` PID must still have the recorded `xvfb-run` or `tools/verify.sh` path on its command line.

Anything else, such as a reused PID or a Godot started by hand, is left alone and reported.

Teardown order: first the Godot games, so `xvfb-run` sees its child exit and stops its own Xvfb; then the wrappers, after stopping any Godot left below them by exact PID. Each PID gets `TERM`, then `KILL` after 5 s. Then `.run/` is removed. `artifacts/` is never touched. Never `pkill`, `killall` or kill by name.

## Helpers

All under `.cursor/skills/verify-flagoria/bin/` (executable):

| Script | Role |
|---|---|
| `launch.sh` | Start a drive from a scratch user dir; wait for `VERIFY_READY` |
| `doctor.sh` | Read-only health of the checkout; `--instance <run-id>` also checks a launched game |
| `drive-verify.sh` | Run `tools/verify.sh`, copy log to artifacts |
| `drive-map-settings-screenshot.sh` | xvfb Map Settings PNG in `artifacts/out/` |
| `evidence-summarize.sh` | Write `artifacts/out/e2e-summary.txt` from latest logs |
| `cleanup.sh` | Stop recorded PIDs by exact PID; remove `.run/` |
| `run_lib.sh` | Sourced by the others: Godot lookup, run dirs, `.run/pids` |

Drives started with `launch.sh` live in `drives/` (`drives/wait.gd`: start a game, print the ready line, wait).

## Feature map

Index: [`features/README.md`](features/README.md).
