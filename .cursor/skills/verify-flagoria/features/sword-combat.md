# Sword combat (PvP)

A player swings the sword with space or the on-screen attack button. The sword only hurts during the middle of the swing. Dead players neither block nor hit.

## Sub-features

- `sword-swing` attack input plays the swing.
- `sword-mid-swing` the hitbox is active only mid-swing (`sword_active()` in `Scripts/player.gd`).
- `sword-dead` a dead player's sword and body are off.

## How to get to it (user POV)

- Two instances: stand next to the other player and attack (README checklist step 4).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_sword_only_hits_mid_swing`, `-- test_combat_sfx` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- The two-player sword test runs real physics on the spawn point; a slow machine can make it time out rather than fail an assert.
