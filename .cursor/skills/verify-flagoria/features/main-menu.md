# Main menu

Drive: not player-facing

The main menu offers Map Settings, Host, Join (with an address field), Music / Sound effects sliders and a Mob spawns slider, styled by a pixel-art Theme.

## Sub-features

- `menu-theme` `art/ui/main_menu_theme.tres`, applied in `flagoria_main.tscn`.
- `menu-host-join` Host and Join buttons; an empty address joins localhost on UDP 9786. A hostname or IPv4 address may add `:port` (see [Join an address with an optional port](./join-port.md)). Tapping the address opens the on-screen letter keyboard (see [Touch controls](./touch-controls.md)).
- `menu-volume` Music and Sound effects sliders (see `audio.md`).
- `menu-mob-rate` Mob spawns slider (`MobRateRow`, `Scripts/game_settings.gd`): 0.5 to 3.0 in 0.25 steps, default 2.0, saved in user settings section `gameplay`. Only the host's rate places mobs (see [Mobs](./mobs.md)).
- `menu-sfx` every button plays the UI click, Back plays back (see `audio.md`).
- `menu-quiet-log` unhandled input on the menu logs no InputMap errors.
- `menu-quit` back or window close asks before quitting (see [In-game menu and quit prompt](./ingame-menu.md)).

## How to get to it (user POV)

- Launch the game; the menu is the first screen.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_audio_settings`, `-- test_dedicated_server_join`, `-- test_mob_spawn_rate`, `-- test_main_menu_letter_keyboard`, `-- test_main_menu_input_no_log_spam` (runs a separate headless process, ~2 s) appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- The theme's Button styles are checked by `verify-generators` (`PASS menu theme (5 Button styles) used by the main menu`) and `-- test_map_settings_uses_menu_theme`. How it looks still needs a screenshot under xvfb (same recipe as `map-settings-panel.md`).
