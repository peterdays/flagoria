# Main menu

The main menu offers Map Settings, Host, Join (with an address field) and Music / Sound effects sliders, styled by a pixel-art Theme.

## Sub-features

- `menu-theme` `art/ui/main_menu_theme.tres`, applied in `flagoria_main.tscn`.
- `menu-host-join` Host and Join buttons; an empty address joins localhost.
- `menu-volume` Music and Sound effects sliders (see `audio.md`).

## How to get to it (user POV)

- Launch the game; the menu is the first screen.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_audio_settings`, `-- test_dedicated_server_join` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- No automated check of the theme itself yet; a theme edit needs a screenshot under xvfb (same recipe as `map-settings-panel.md`).
