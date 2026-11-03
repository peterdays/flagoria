# Touch controls

On touch screens the hero moves with an on-screen joystick and attacks with a round attack button that also aims (see [Combat and aiming](./combat-and-aiming.md)). Both use the Castle Stone art (#240). Number fields and the join address open an on-screen number pad or letter keyboard.

## Sub-features

- `touch-joystick` a finger held still keeps the hero moving at top speed every physics frame; letting go stops it (#201).
- `touch-look` the attack button shows idle, pressed and aim art; the joystick shows its active knob only while dragged; the aim cone pulses 0.40 -> 0.55 -> 0.40 alpha every 0.8 s with one-pixel lines at any zoom.
- `number-pad` `Scripts/number_pad.gd` (`attach`, `attach_spin_box`): the first key replaces the value, keycaps use the menu theme. Used by [Map Settings](./map-settings-panel.md).
- `letter-keyboard` `NumberPad.attach_text`: the join address field on the [Main menu](./main-menu.md).

## How to get to it (user POV)

- Run on Android, or desktop with touch emulation, host a game and drag the joystick; tap a seed field in Map Settings.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: these five tests add about 3 s to `tools/verify.sh` (~4.3 s alone with `--only=`).

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_joystick_hold_keeps_moving`, `-- test_touch_controls_look`, `-- test_number_pad_first_key_replaces`, `-- test_number_pad_keycap_style`, `-- test_main_menu_letter_keyboard` with no `FAIL` after them.
- **Drive (live).** `bin/launch.sh drives/combat_hud.gd` drags on the attack button with emulated touch events (see `touch_drag` in `drives/combat_hud.gd`).

## Gotchas

- Whether the art reads well on a phone is a manual call; tests check textures and alpha, not looks.
