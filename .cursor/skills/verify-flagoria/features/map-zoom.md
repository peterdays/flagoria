# Map zoom

Pinch with two fingers on open map to zoom the local camera in or out; the default view stays the default. Zoom is local and never synced.

## Sub-features

- `zoom-pinch` two touches on open map zoom between `MIN_FACTOR` 0.75 and `MAX_FACTOR` 2.0 of the default (`Scripts/map_zoom.gd`).
- `zoom-hud-safe` touches that start on HUD controls (joystick, attack) do not zoom.
- `zoom-desktop` wheel or Ctrl +/- steps by `STEP`.

## How to get to it (user POV)

- On a phone or touch screen: Host, then pinch on the map away from the joystick and attack button.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_map_zoom` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- Headless tests feed synthetic touch events; real multi-touch on a device still needs a manual check.
