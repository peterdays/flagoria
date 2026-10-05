# Flagoria verification map

Maintained recipes for proving user-facing and CI-facing behavior. Read this index, then the matching feature file.

## Baseline preconditions

- Working directory is the Flagoria repo root (`project.godot` present).
- `GODOT` points at a Godot **4.1.x** editor binary (`$GODOT --version`).
- Run `./.cursor/skills/verify-flagoria/bin/doctor.sh` and require exit `0`.
- Prefer disposable evidence under `.cursor/skills/verify-flagoria/artifacts/`.
- Never drive a long-lived game instance that was not started for this verification run.

## Driving conventions

- Automated proof goes through `tools/verify.sh` via `bin/drive-verify.sh`.
- Visual proof uses `xvfb-run` and `--rendering-driver opengl3` when a display is required.
- Record skips with the unmet precondition; do not report a skipped path as verified through a different path.

## Proof and skip reporting

- Keep verify logs and screenshots in `artifacts/`; cleanup must not delete them.
- UI proof for Map Settings includes a PNG with the panel title visible.
- Two-player PvP is not fully scripted yet — see placeholders below.

## Features

- [Headless verify](./headless-verify.md) — `tools/verify.sh` load, parse, and tests.
- [Map characterization](./map-characterization.md) — pinned map-output / golden atlas check.
- [Map Settings panel](./map-settings-panel.md) — in-game admin parameters before Host.
- [Two-player Host/Join](./two-player-host-join.md) — multiplayer boot (partial automation).

## Placeholders (not verified here yet)

- **#45 automated two-player smoke** — CI-friendly Host/Join without a human GUI. When present, add a feature file and wire it into `drive-verify.sh` or a sibling helper.
- **#48 CLI map renders** — headless map image export for diffs. When present, document the CLI flags and expected artifact paths here.
