# Interact mode

Drive: not player-facing

`CanvasLayer1/ModeButton` switches the hero between combat and interact mode (`Interaction.Mode` in `Scripts/mechanics/interact/interaction.gd`). Chopping, building and their sync are in [Chop trees (live drive)](./chop-trees.md), [Chopping trees and bushes](./chop-trees-and-bushes.md) and [Build placement](./build-placement.md).

## Sub-features

- `interact-mode-toggle` the mode button toggles `COMBAT` and `INTERACT` and shows the current mode's icon (`-- test_interact_mode_toggle` in `tests/mechanics/trees/test_interact.gd`).
- `interact-space-swing` the `attack` action (Space) still swings the sword the way the hero faces while interact mode is on (`attack_animation` in `Scripts/player.gd`, with no mode check). Mouse and touch aimed sword attacks stay combat-only (`Scripts/attack_aim.gd`, #231). Intended (#351).

## How to get to it (user POV)

- Host or join a world, tap `CanvasLayer1/ModeButton`, then press Space to swing while still in interact mode.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: none (no new test; `-- test_interact_mode_toggle` is listed under [Chop trees (live drive)](./chop-trees.md)).

- **Run.** `./tools/verify.sh`, or `godot --headless --path . --script res://tests/run_tests.gd -- --only=interact_mode_toggle` for the mode button.
- **Proof.** Header `-- test_interact_mode_toggle` with no `FAIL` after it. Space in interact mode is documentation-only; combat swings are in [Combat and aiming](./combat-and-aiming.md).

## Gotchas

- A plain tap on the on-screen attack button in interact mode starts a chop, not a sword swing (`-- test_attack_aim_touch_guards`).
