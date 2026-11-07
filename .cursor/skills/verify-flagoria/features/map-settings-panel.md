# Map Settings panel

Drive: drives/map_settings_random.gd

Map Settings lets a player edit map generation parameters from the main menu before hosting, without rebuilding.

## Sub-features

- `settings-open` opens the panel from Main Menu → Map Settings.
- `settings-edit` changes seeds and numeric parameters (scrollable on 480×270).
- `settings-host` starts a host with the chosen parameters (Host with these / Host after Back).
- `settings-persist` restores last-used values from `user://` across restarts, and shows the in-use value on reopen even when a field still holds a dirty string.
- `settings-rows` rows come from `MapGenParams` `@export_range` hints, so a new parameter gets a row and reaches clients (`to_dict`) with no UI code; rows are centered at a fixed width in the menu theme.
- `settings-number-pad` tapping a seed or number field opens the on-screen number pad (`Scripts/number_pad.gd`, see [Touch controls](./touch-controls.md)), and on a phone it stays open after the tap.
- `settings-bottom-visible` the five action buttons stay fully inside the 480×270 layout space, which the 1280×720 window and the 854×480 landscape window both show (stretch aspect keep). They are two equal pairs (Random seeds / Random specs, then Defaults / Back) and Host with these centered on its own row, pinned below the scroll area (#406 kept that pin; #217 is the five-button arrangement). Headless: `-- test_map_settings_bottom_buttons_visible`, `-- test_map_settings_five_button_rows`.
- `settings-random-specs` **Random specs** sets every map-gen property (except `chunk_*`) inside `MapGenParams.PLAYABLE_RANGES`, randomises seeds, keeps ordered thresholds, and picks island or archipelago so the map stays playable (#335). **Random seeds** still only changes seeds. Headless: `-- test_random_specs_playable`, `-- test_random_seed_unchanged_by_specs_contract`, `-- test_random_specs_panel_button`.

## How to get to it (user POV)

- Launch the game → Main Menu → **Map Settings**.
- Adjust controls → **Random seeds** / **Random specs** / **Defaults** / **Back** or **Host with these**.

## Driving it with verify-flagoria helpers

Preconditions:

- `doctor.sh` exits `0`.
- `xvfb-run` available for visual proof; otherwise skip and record the skip.

- **Random specs drive.** `bin/launch.sh drives/map_settings_random.gd --display` opens Map Settings and snapshots the five buttons at the 1280×720 window (`01-map-settings-before.png`), at the 854×480 landscape window (`02-map-settings-landscape.png`), then after **Random specs** back at 1280×720 (`03-map-settings-after-random.png`). It then clicks Back and checks the main menu returns. About 3 s. The five-button headless check adds about 0.05 s to `tools/verify.sh`.
- **Screenshot open panel (legacy).** Run `./.cursor/skills/verify-flagoria/bin/drive-map-settings-screenshot.sh`. Exit `0` writes `artifacts/out/map_settings.png` (~10 s); the committed `artifacts/map_settings.png` is the reference to compare by eye. Exit `2` means xvfb missing (skip visual).
- **Headless coverage.** Parameter application and map output are covered by map characterization + verify, not by clicking every numeric field. Headers `-- test_map_settings_covers_params`, `-- test_new_param_needs_no_ui_code`, `-- test_map_settings_rows_from_hints`, `-- test_map_settings_rows_centered`, `-- test_map_settings_bottom_buttons_visible`, `-- test_map_settings_five_button_rows`, `-- test_map_settings_uses_menu_theme`, `-- test_map_settings_water_reopen`, `-- test_map_settings_number_pad`, `-- test_map_settings_number_pad_spin_boxes`, `-- test_map_settings_number_pad_touch_tap`, `-- test_random_specs_playable`, `-- test_random_seed_unchanged_by_specs_contract`, `-- test_random_specs_panel_button` with no `FAIL` after them.
- **Proof.** Drive PNGs show all five action buttons and the pinned bottom row, at 1280×720 and at 854×480, with no overlap and no button cut by the window edge. Before/after **Random specs** differ in seed and/or numeric fields.

## Gotchas

- Viewport is 480×270 with stretch aspect keep, so a 1280×720 window and an 854×480 landscape window use the same layout space. Not every field is on screen at once. The scroll area has no fixed minimum height, so the three pinned button rows stay fully inside that space (#406, #217).
- Joining clients receive host params over RPC; editing Map Settings on a pure client does not author the world.
- Do not claim screenshot proof when GL/xvfb failed.
