# Map Settings panel

Drive: not player-facing

Map Settings lets a player edit map generation parameters from the main menu before hosting, without rebuilding.

## Sub-features

- `settings-open` opens the panel from Main Menu → Map Settings.
- `settings-edit` changes seeds and numeric parameters (scrollable on 480×270).
- `settings-host` starts a host with the chosen parameters (Host with these / Host after Back).
- `settings-persist` restores last-used values from `user://` across restarts, and shows the in-use value on reopen even when a field still holds a dirty string.
- `settings-rows` rows come from `MapGenParams` `@export_range` hints, so a new parameter gets a row and reaches clients (`to_dict`) with no UI code; rows are centered at a fixed width in the menu theme.
- `settings-number-pad` tapping a seed or number field opens the on-screen number pad (`Scripts/number_pad.gd`, see [Touch controls](./touch-controls.md)), and on a phone it stays open after the tap.

## How to get to it (user POV)

- Launch the game → Main Menu → **Map Settings**.
- Adjust controls → **Random seeds** / **Defaults** / **Back** or **Host with these**.

## Driving it with verify-flagoria helpers

Preconditions:

- `doctor.sh` exits `0`.
- `xvfb-run` available for visual proof; otherwise skip and record the skip.

- **Screenshot open panel.** Run `./.cursor/skills/verify-flagoria/bin/drive-map-settings-screenshot.sh`. Exit `0` writes `artifacts/out/map_settings.png` (~10 s); the committed `artifacts/map_settings.png` is the reference to compare by eye. Exit `2` means xvfb missing (skip visual).
- **Headless coverage.** Parameter application and map output are covered by map characterization + verify, not by clicking every numeric field. Headers `-- test_map_settings_covers_params`, `-- test_new_param_needs_no_ui_code`, `-- test_map_settings_rows_from_hints`, `-- test_map_settings_rows_centered`, `-- test_map_settings_uses_menu_theme`, `-- test_map_settings_water_reopen`, `-- test_map_settings_number_pad`, `-- test_map_settings_number_pad_spin_boxes`, `-- test_map_settings_number_pad_touch_tap` with no `FAIL` after them (about 2 s of `tools/verify.sh`).
- **Proof.** PNG shows the title `Map Generation` (or Map Settings chrome) and seed fields; keep the file under `artifacts/`.

## Gotchas

- Viewport is 480×270 with stretch; use a ScrollContainer mindset — not all fields are on screen at once.
- Joining clients receive host params over RPC; editing Map Settings on a pure client does not author the world.
- Do not claim screenshot proof when GL/xvfb failed.
