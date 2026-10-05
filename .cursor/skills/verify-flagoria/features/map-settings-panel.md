# Map Settings panel

Map Settings lets a player edit map generation parameters from the main menu before hosting, without rebuilding.

## Sub-features

- `settings-open` opens the panel from Main Menu → Map Settings.
- `settings-edit` changes seeds and numeric parameters (scrollable on 480×270).
- `settings-host` starts a host with the chosen parameters (Host with these / Host after Back).
- `settings-persist` restores last-used values from `user://` across restarts.

## How to get to it (user POV)

- Launch the game → Main Menu → **Map Settings**.
- Adjust controls → **Random seeds** / **Defaults** / **Back** or **Host with these**.

## Driving it with verify-flagoria helpers

Preconditions:

- `doctor.sh` exits `0`.
- `xvfb-run` available for visual proof; otherwise skip and record the skip.

- **Screenshot open panel.** Run `./.cursor/skills/verify-flagoria/bin/drive-map-settings-screenshot.sh`. Exit `0` writes `artifacts/map_settings.png`. Exit `2` means xvfb missing (skip visual).
- **Headless coverage.** Parameter application and map output are covered by map characterization + verify, not by clicking every numeric field.
- **Proof.** PNG shows the title `Map Generation` (or Map Settings chrome) and seed fields; keep the file under `artifacts/`.

## Gotchas

- Viewport is 480×270 with stretch; use a ScrollContainer mindset — not all fields are on screen at once.
- Joining clients receive host params over RPC; editing Map Settings on a pure client does not author the world.
- Do not claim screenshot proof when GL/xvfb failed.
