# Combat and aiming

A player swings the sword with space, a tap on the on-screen attack button, or an aimed attack (#231): hold the left mouse button on the map, or drag a finger out from the attack button, see the aim cone, and release to swing that way. The sword only hurts during the middle of the swing. Dead players neither block nor hit.

## Sub-features

- `sword-swing` the `attack` action (space) or a plain tap on the attack button swings the way the hero faces (`attack_animation` in `Scripts/player.gd`).
- `sword-mid-swing` the hitbox is active only mid-swing (`sword_active()` in `Scripts/player.gd`).
- `sword-dead` a dead player's sword and body are off.
- `aim-mouse` holding the left mouse button on the map in combat mode aims at the cursor (`Scripts/attack_aim.gd`, node `AttackAim` under the hero).
- `aim-touch` a finger that lands on the attack button (group `attack_button`, `CanvasLayer1/TouchScreenButton`) aims once it moves more than `TOUCH_DEAD_ZONE` (8 screen px) from the button's `aim_center()`.
- `aim-cone` a translucent cone from the hero shows the swing; its look is `AimConeStyle` (`Scripts/aim_cone_style.gd`).
- `aim-angle` the cone and the swing follow the exact aim angle (`aim_angle()`); the hero's sprite faces the nearest of the four directions (`aim_direction()`, `AttackAim.DIRECTIONS`: Up, Down, Left, Right), and the swing plays that direction's animation turned by `swing_turn` about `AttackAim.ORIGIN` (`_turn_swing` in `Scripts/player.gd`), hitbox included.
- `aim-cancel` right-click, or opening the in-game menu (`CanvasLayer1/InGameMenu`, Esc or its HUD button), cancels a mouse aim, and no aim starts while that menu is open; dragging back into the dead zone cancels a touch aim (lifting there does not swing; dragging out again aims again); a second touch that lands off the move stick (`CanvasLayer1/player_joystick`) cancels a touch aim and lets that finger go (its drags and lift do not swing), and opening the in-game menu cancels it too.
- `aim-release` releasing the mouse button or lifting the finger swings at the aimed angle, sent to every peer as a direction and an angle through the `attack_animation` RPC. Every peer, the server included, checks the angle: one more than 45 degrees (`MAX_TURN`) from its direction, or not finite, or an unknown direction, swings the way the hero faces; no angle (space, a tap) is a plain four-way swing.

## How to get to it (user POV)

- Host a world, then hold the left mouse button on the map, or drag a finger out from the on-screen attack button, and release. A plain tap or space swings the way the hero faces.
- PvP: two instances, stand next to the other player and attack (see [Two-player Host/Join](./two-player-host-join.md)).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the six tests below are under ~3.5 s each in `tools/verify.sh` (1.3-4.4 s alone with `--only`, ~1.1 s of that start-up; `attack_aim_mouse` ~4.4 s, `attack_aim_touch` ~3.1 s, `attack_angle_two_players` ~2.0 s); a live drive is ~1.5 s.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=sword_only_hits_mid_swing,attack_aim_mouse,attack_aim_touch,attack_aim_touch_guards,attack_angle_two_players,mob_sword`, or the full `tools/verify.sh` and read `artifacts/verify.log`.
- **Drive (live).** `start_game()`, then `tap("attack")` for a plain swing. For the aimed path, read the node in group `attack_button` at run time, send an `InputEventScreenTouch` (pressed) at its `aim_center()`, `InputEventScreenDrag` events out past `TOUCH_DEAD_ZONE` (for example 30 px up), then the release, with `Input.parse_input_event()` as `tap_cell()` does.
- **Proof.** End state: after `tap("attack")` the hero's `isAttacking` is true and `lastAnimDirection` is unchanged; during the drag `AttackAim.aiming` is true, `aim_angle()` is the drag's angle and `aim_direction()` the nearest four-way direction; after the release the hero swings with `lastAnimDirection` equal to that direction and `swing_turn` equal to the angle less that direction's. Headless: each header `-- test_sword_only_hits_mid_swing`, `-- test_attack_aim_mouse`, `-- test_attack_aim_touch`, `-- test_attack_aim_touch_guards`, `-- test_attack_angle_two_players`, `-- test_mob_sword` appears with no `FAIL` after it, and the run ends with `All tests passed.` and `Verification passed.`. The mob hit in the aimed direction is proven in two steps: `test_attack_aim_mouse` checks the cone covers the sword's hitbox mid-swing in every direction, `test_attack_aim_mouse` and `test_attack_aim_touch` check the hitbox turns to off-axis angles (30, -60, 160, 115 degrees), `test_attack_angle_two_players` checks the server's copy swings the client's angle and rejects a bad one, and `test_mob_sword` checks that hitbox hurts a mob once per swing.

## Gotchas

- `aim_center()` is a viewport position; the viewport is 480 x 270 and the window is not (1280 x 720 under `--display`), so convert with `root.get_final_transform() * aim_center()` before `Input.parse_input_event()`.
- Touches that start on a HUD control, mouse events made from touches, interact mode and a dead player never aim (`-- test_attack_aim_touch_guards`, `-- test_attack_aim_mouse`).
- The two-player sword test runs real physics on the spawn point; a slow machine can make it time out rather than fail an assert.
- The minimap panel is open by default and covers the top right of the screen, so a mouse press there is on the HUD and does not aim; hide it (`shown = false`) before aiming up and to the right.
- Swing sounds are covered by `-- test_combat_sfx` ([Audio](./audio.md)).
