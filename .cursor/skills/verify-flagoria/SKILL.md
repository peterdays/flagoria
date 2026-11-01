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
| `.cursor/skills/verify-flagoria/artifacts/` | Proof outputs (logs, screenshots, summaries; per-run evidence in `out/runs/<run-id>/`). **Survives cleanup.** |
| `.cursor/skills/verify-flagoria/.run/` | `pids` and one dir per launch (scratch user dirs, `game.log`). Gitignored; removed by cleanup. |

## Launch

`tools/verify.sh` and the drives below are short runs. For a gameplay drive, launch the real game and either play a feature drive to its end or leave the game running for an agent:

```bash
./.cursor/skills/verify-flagoria/bin/launch.sh drives/smoke.gd           # a drive that finishes
./.cursor/skills/verify-flagoria/bin/launch.sh drives/wait.gd            # stays up; headless
./.cursor/skills/verify-flagoria/bin/launch.sh drives/wait.gd --display  # xvfb-run + opengl3
```

In a fresh checkout, import once first (`"$GODOT" --headless --path . --import`), as `tools/verify.sh` does.

The drive path is relative to the skill dir, to the repo, or a `res://` path. Each launch:

1. finds Godot (`GODOT` if set, else `godot` on `PATH`);
2. makes a fresh run dir `.run/<run-id>/` with empty `xdg/data`, `xdg/config` and `xdg/cache`, and exports `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` to them, so the game starts from an empty `user://` and never reads or writes the real one;
3. starts `godot --headless --path . --script <drive.gd>` in the background (with `--display`: under `xvfb-run -a` with `--rendering-driver opengl3`), logging to `.run/<run-id>/game.log`;
4. appends each exact PID to `.run/pids` as `<pid> <kind> <run-id> <path>`: the Godot PID, plus the `xvfb-run` PID with `--display`;
5. prints `launch: run=<run-id> pid=<pid> log=...`, then each `VERIFY_READY`, `VERIFY_STEP` and `VERIFY_DONE` line from `game.log` as it comes, and exits with the drive's result (below).

**Lines** a drive prints on stdout, all from `bin/drive_base.gd`:

| Line | Printed by | Meaning |
|---|---|---|
| `VERIFY_READY pid=<pid> scene=res://flagoria_main.tscn` | `start_game()` | The main scene is loaded, a game is started through the main menu's Host button and the local hero exists under `World`. A running process is not ready; a usable game is. |
| `VERIFY_STEP <name>` | `step(name)` | A drive step begins. |
| `VERIFY_DONE ok` or `VERIFY_DONE fail` | `done(ok)` | The drive finished; the game quits with `0` or `1`. |
| `VERIFY_IDLE pid=<pid>` | `idle()` | The drive stays up for an agent; stop it with Cleanup. It quits on its own after 10 minutes. |

**Exit code of `launch.sh`:**
- `0`: the drive printed `VERIFY_DONE ok` and the game exited `0`;
- `0`: the drive printed `VERIFY_IDLE`; launch returns at once and the game keeps running (`drives/wait.gd` does this right after the ready line);
- `1`: `VERIFY_DONE fail`, or the game exited without a `VERIFY_DONE` line (a crash, a kill, or a drive that quit on its own), or before `VERIFY_READY`;
- `1`: a timeout: no `VERIFY_READY` within 60 s (`VERIFY_READY_TIMEOUT`), or no `VERIFY_DONE` or `VERIFY_IDLE` within 300 s of it (`VERIFY_DRIVE_TIMEOUT`). The game is still running: stop it with Cleanup.

On every `1` launch prints the last 20 lines of `game.log` to stderr. Run Cleanup after every launch either way: finished runs still have their run dir.

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

Run it before the first drive step, after any failed step, and whenever a drive does something surprising. It needs the game up: after `VERIFY_IDLE`, or while a drive is still going. A drive that has printed `VERIFY_DONE` has exited, so its PID check fails. `<run-id>` is the `run=` value `launch.sh` printed. On top of the checks above, it checks every PID recorded for that run in `.run/pids`, and prints one `doctor: instance ok:` or `doctor: instance FAIL:` line per check:
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

### Feature drives

A feature drive is `drives/<feature>.gd`. It plays the real game through the input a player gives it and ends with `done(ok)`:

```gdscript
extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"

func run() -> void:
	if not await start_game():
		return
	var start := hero().position
	step("walk")
	await hold("ui_right", 30)
	done(hero().position.distance_to(start) >= 1.0)
```

Start it with `bin/launch.sh drives/<feature>.gd` and read its result from the exit code. `drives/smoke.gd` is this sample. Helpers in `bin/drive_base.gd` (await the ones that take frames):

| Helper | What it does |
|---|---|
| `start_game()` | Loads the main scene, clicks Host with a pointer click on the button, prints `VERIFY_READY` once the hero exists. `false` (after `done(false)`) if it does not. |
| `hero()` | The local hero under `World`, to read its state. |
| `hold(action, frames)`, `tap(action)` | Press an input action (`ui_left`, `ui_right`, `ui_up`, `ui_down`, `attack`) for some physics frames, or for one. |
| `toggle_mode()` | Clicks `CanvasLayer1/ModeButton` (combat or interact mode). |
| `tap_cell(cell)` | A touch tap at a map cell's screen position. A cell under the HUD (the minimap, the buttons) gets the HUD, as a finger would. |
| `menu_save()` | Clicks the in-game menu button, then Save. |
| `click(path)` | A left click at the centre of a `Control` under the main scene. |
| `wait_until(predicate, timeout_s)` | Waits frame by frame; `false` on timeout. |
| `step(name)`, `done(ok)`, `idle()` | Print the lines above; `done` quits `0` or `1`. |
| `snapshot(label)` | Writes `<NN>-<label>.json` (and `.png` under `--display`) to the run's evidence dir; see Evidence. Await it. |

Clicks and taps go to the centre of the node's rect or the cell, read at run time and converted to window pixels through the canvas and window stretch transforms, so they land in the same place headless (a 64x64 window) and under `--display` (1280x720). Never pass a screen position written as a literal.

**Drive rule:** a drive may read game state to decide when to go on or whether it passed, but never sets it: no `set_cell`, no inventory writes, no calls into `Interaction` internals, no emitting a button's `pressed`. Everything it changes goes through input. Setup is chosen by seed in `user://map_gen_params.cfg`, written into the run's scratch user dir before launch, never by the drive. `launch.sh` has no option to write that file yet, so every launch gets a random map, and a drive must pass on any map: the sample only checks that the hero moved at all, since a tree or water may stop it a few px to the right.

### Drives in CI (opt-in)

`.github/workflows/verify-drive.yml` runs drives on a GitHub runner, headless: import, `bin/doctor.sh`, then per drive `bin/launch.sh drives/<name>.gd`, `bin/doctor.sh --instance <run-id>` for a drive that idles (one that printed `VERIFY_DONE` has exited, so the PID check would fail), and `bin/cleanup.sh`. It uploads `artifacts/out/runs/` (under this skill) as the `drive-evidence` artifact, also when a drive fails. Start it from the Actions tab (**verify-drive**, **Run workflow**; `drives` is a space-separated list of names in `drives/`, empty for all), or add the `needs-drive` label to a pull request from this repository. It never runs on push or on a plain pull request, and `tools/verify.sh` and the required checks never run drives.

### Two-player Host/Join

Not fully automatable without a GUI harness yet (placeholder: issue #45). What is feasible now:

- Headless: main scene loads inside verify / characterization (no Host click).
- Manual: follow the README two-player play-test checklist (Host, Join localhost, move, attack, regen) on two instances.

Do not claim two-player PvP was proven by verify.sh alone.

## Evidence

A drive is a proof only if its evidence is readable after the run. Proof standards:

- Take the real player path: the main menu, pointer clicks and input actions (`start_game()`, `tap`, `click`), or the real CI path (`tools/verify.sh`), not internal setters that skip the menu or RPC.
- Record the action and the state it led to: a `step(name)` before the action and a `snapshot(label)` after it (before and after, when the change is the proof).
- Record side effects too, such as the world save under `user/saves/` after `menu_save()`. For the map golden, failing after a threshold edit is the mutation proof (do that only in a throwaway edit and revert).

Each launch keeps its evidence in `.cursor/skills/verify-flagoria/artifacts/out/runs/<run-id>/` (gitignored, kept by Cleanup):

| File | Written by | Contents |
|---|---|---|
| `<NN>-<label>.json` | `snapshot(label)` | Hero cell and facing, mode (`combat` or `interact`), inventory counts, explored cell count, and the foliage-layer tile names (`TileCatalog` names, `null` when empty) in a 9x9 square around the hero, top row first. |
| `<NN>-<label>.png` | `snapshot(label)` under `--display` | The window. A headless run has no image; its JSON says `"png": "skipped: headless run, ..."`. |
| `game.log` | `launch.sh` when the game exits; `collect-evidence.sh` | The game's output, with the `VERIFY_*` lines. |
| `user/` | `collect-evidence.sh` | The scratch `user://`: `saves/` and `*.cfg`. |
| `summary.txt` | `collect-evidence.sh` | Run id, drive, commit, Godot version, steps seen, result, snapshots. |

The result is `ok` or `fail` from `VERIFY_DONE`; `idle (then stopped by cleanup or killed)` after `VERIFY_IDLE`; `killed (...)` when the game ended by a signal, or launch was not there to see it end, without `VERIFY_DONE`; `exited <code> without VERIFY_DONE` otherwise. Cleanup runs `collect-evidence.sh <run-id>` for every run before it removes `.run/`, so a failed or killed drive keeps its evidence. Run it by hand to look at a run that is still up.

After a successful verify drive, write a short summary:

```bash
./.cursor/skills/verify-flagoria/bin/evidence-summarize.sh
```

Other artifacts live in `.cursor/skills/verify-flagoria/artifacts/` (for example `verify.log`, `out/e2e-summary.txt`, `out/map_settings.png`). **Cleanup must not delete this directory's proof files.** `evidence-summarize.sh` writes to the gitignored `artifacts/out/`. The committed `artifacts/e2e-summary.txt` is a reference example of the format and changes only on purpose.

## Cleanup

```bash
./.cursor/skills/verify-flagoria/bin/cleanup.sh
```

Run it after every launch or drive, including failed ones. It stops only PIDs listed in `.run/pids`, by exact PID, and only while each one is still the process that was launched:
- a `godot` PID must run the recorded Godot binary (`/proc/<pid>/exe`) with `XDG_DATA_HOME` in its own `.run/<run-id>/xdg/`;
- an `xvfb-run` or `verify` PID must still have the recorded `xvfb-run` or `tools/verify.sh` path on its command line.

Anything else, such as a reused PID or a Godot started by hand, is left alone and reported.

Teardown order: first the Godot games, so `xvfb-run` sees its child exit and stops its own Xvfb; then the wrappers, after stopping any Godot left below them by exact PID. Each PID gets `TERM`, then `KILL` after 5 s. Then `collect-evidence.sh` keeps each run's evidence (see Evidence) and `.run/` is removed. `artifacts/` is never touched. Never `pkill`, `killall` or kill by name.

## Helpers

All under `.cursor/skills/verify-flagoria/bin/` (executable):

| Script | Role |
|---|---|
| `launch.sh` | Start a drive from a scratch user dir; print its lines; exit with its result |
| `drive_base.gd` | Base script for drives: `start_game`, input helpers, `snapshot`, `step` / `done` / `idle` |
| `doctor.sh` | Read-only health of the checkout; `--instance <run-id>` also checks a launched game |
| `drive-verify.sh` | Run `tools/verify.sh`, copy log to artifacts |
| `drive-map-settings-screenshot.sh` | xvfb Map Settings PNG in `artifacts/out/` |
| `evidence-summarize.sh` | Write `artifacts/out/e2e-summary.txt` from latest logs |
| `collect-evidence.sh` | Copy a run's `game.log` and `user://` to `artifacts/out/runs/<run-id>/`; write `summary.txt` |
| `cleanup.sh` | Stop recorded PIDs by exact PID; collect each run's evidence; remove `.run/` |
| `run_lib.sh` | Sourced by the others: Godot lookup, run dirs, `.run/pids` |

Drives started with `launch.sh` live in `drives/` (`drives/wait.gd`: start a game, then `idle()`; `drives/smoke.gd`: start a game, walk right, check the hero moved).

## Feature map

Index: [`features/README.md`](features/README.md).
