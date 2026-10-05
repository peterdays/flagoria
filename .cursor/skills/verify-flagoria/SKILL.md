---
name: verify-flagoria
description: "Verify Flagoria (Godot 4.1 island PvP): headless project load/parse/tests, map generation golden checks, and Map Settings / Host-Join surfaces via tools/verify.sh and optional xvfb screenshots. Use when proving a change to map gen, the admin panel, multiplayer boot, or before opening a PR."
---

# Verify Flagoria

Project-local verification for Flagoria. Read this cold mid-task. Prefer the feature map under `features/` for user-facing recipes. Always run **Doctor** before trusting a drive.

**Engine:** Godot **4.1.x** only. Set `GODOT` to the editor binary (must report `4.1.*` from `$GODOT --version`). Do not use a newer editor: it can migrate `project.godot`.

**Repo root:** every command below assumes the current working directory is the Flagoria checkout root (the directory that contains `project.godot` and `tools/verify.sh`).

**Scratch / evidence:**

| Path | Purpose |
|---|---|
| `.cursor/skills/verify-flagoria/artifacts/` | Proof outputs (logs, screenshots, summaries). **Survives cleanup.** |
| `.cursor/skills/verify-flagoria/.run/` | Per-run PIDs and temp state. Removed by cleanup. |

## Launch

Flagoria is not a long-lived server for most checks. Launch means: confirm the engine, ensure the project can open headless, then start each drive as a short-lived process.

1. Require `GODOT` on the environment and version `4.1.*`:

```bash
test -n "${GODOT:-}" && "$GODOT" --version
```

2. Create run dirs:

```bash
mkdir -p .cursor/skills/verify-flagoria/artifacts .cursor/skills/verify-flagoria/.run
```

3. Optional warm import (same path CI uses first):

```bash
"$GODOT" --headless --path . --editor --quit
```

Ready when that command exits `0` (benign RID-leak `ERROR` lines on shutdown are normal and non-fatal).

4. For **visual** Map Settings proof only, a display is required. Prefer:

```bash
xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path . --rendering-driver opengl3 ...
```

Software GL (`llvmpipe`) is acceptable. If `xvfb-run` or a usable GL path is missing, skip visual drives and record the skip in evidence (do not fake screenshots).

**Teardown of launch scaffolding:** see Cleanup. Do not leave editor or game processes running after a drive.

## Doctor

Read-only. Run whenever anything looks off:

```bash
./.cursor/skills/verify-flagoria/bin/doctor.sh
```

Expect exit `0` and lines confirming: repo root, `GODOT` version `4.1.*`, `tools/verify.sh` present, `tests/run_tests.gd` present. Fail if `GODOT` is unset, wrong major/minor, or the checkout is not Flagoria.

## Drive

### Automated (primary)

```bash
./.cursor/skills/verify-flagoria/bin/drive-verify.sh
```

This runs `./tools/verify.sh` (import/load, parse every `.gd`, then `godot --headless --script res://tests/run_tests.gd`). Exit `0` and `Verification passed.` / `All tests passed.` are required.

Map characterization: when `tests/run_tests.gd` defines `test_map_characterization` (map golden / pinned atlas check), the verify log must include `PASS test_map_characterization`. On checkouts that only have the smoke test, expect `PASS test_smoke_true` only — still require verify green. See `features/map-characterization.md`.

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

Kills only PIDs recorded under `.cursor/skills/verify-flagoria/.run/` (never `pkill godot` by name). Removes `.run/` scratch. Leaves `artifacts/` intact.

## Helpers

All under `.cursor/skills/verify-flagoria/bin/` (executable):

| Script | Role |
|---|---|
| `doctor.sh` | Read-only health |
| `drive-verify.sh` | Run `tools/verify.sh`, copy log to artifacts |
| `drive-map-settings-screenshot.sh` | xvfb Map Settings PNG in `artifacts/out/` |
| `evidence-summarize.sh` | Write `artifacts/out/e2e-summary.txt` from latest logs |
| `cleanup.sh` | Tear down recorded PIDs + `.run/` |

## Feature map

Index: [`features/README.md`](features/README.md).
