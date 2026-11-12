# Run control

Drive: drives/run_control.gd

A Run button on the HUD, beside the attack button and smaller than it, shows `icon_run.png` and makes the hero walk faster while it is held or latched on. The brighter on face shows run is active. Shift does the same hold without latching. Chop reach, the sword and the joystick direction stay as they are. Each player moves at the speed that player chose; position sync carries that speed to the other player.

## Sub-features

- `run-hold` a press longer than 12 process frames runs only while the button is down. Releasing it returns to the walk cap on the next physics step (`-- test_run_control`).
- `run-toggle` a shorter press latches run on, and the next one turns it off (`-- test_run_control`).
- `run-key` the `run` action (Shift) runs while held and does not latch (`-- test_run_control`).
- `run-speed` run uses twice the walk acceleration and twice the walk cap (keyboard 260 px/s, joystick 120 px/s), so a run is faster from the first step. The joystick axis is the same vector (`-- test_run_control`).
- `run-two-players` one peer latches run and the other walks; each copy follows the owner's position (`-- test_run_two_players`).

## How to get to it (user POV)

- Host or join, then tap **Run** (it stays on) or hold it. Hold Shift for the same faster walk without latching. Tap **Run** again, or let go of a hold, to walk.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the two tests add about 6 s to `tools/verify.sh`. The live drive is about 30 s under xvfb.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_run_control` and `-- test_run_two_players` with no `FAIL` after them.
- **Drive (live).** `bin/launch.sh drives/run_control.gd --seed 49 --display`. Snapshots: `before-run` (Run button up, at the spawn) and `after-run` (Run button latched, after the faster stretch). The second stretch in the same direction is farther than the first.

## Gotchas

- Footstep spacing is tuned for the 130 px/s walk cap, so a keyboard run can start the next step before the clip ends. `max_polyphony` drops the overlap.
- The cut-rate ceiling still uses the walk cap. This control does not change it.
