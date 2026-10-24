# Player health

Each player has 3 hearts in half-heart steps. A hit costs half a heart and starts a short blink of invulnerability. A dead player disappears and respawns at the spawn point with full hearts. The host decides all damage.

## Sub-features

- `hearts-data` `PlayerHealth` (`Scripts/player_health.gd`): `max_health` 6 half-hearts, `invulnerable_time` 1 s, `respawn_delay` 1 s; signals `health_changed`, `damaged`, `died`, `respawned`, `state_received`.
- `hearts-hud` `HeartsHud` (`Scripts/hearts_hud.gd`): a corner row of full, half and empty icons that follows the local player and flashes on loss.
- `hearts-regen` the player's `regen_timer` (`Scripts/player.gd`) gives half a heart back every 5 s, skipping dead and full players.
- `hearts-sync` health is host-authoritative and replicated to every peer; a joiner sees a dead player as dead (no blocking body).
- `hearts-respawn` a respawned player's copies do not snap back to the death spot.

## How to get to it (user POV)

- Host, take a hit from the other player or a mob, and watch the top-left hearts.
- Hit a player to zero hearts to see death and respawn.
- README two-player checklist steps 4-6.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_player_regen`, `-- test_player_health`, `-- test_player_health_sync`, `-- test_player_health_join_while_dead`, `-- test_player_respawn_no_snapback` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- Regen timing right after a hit is a feel call; tests pin current behaviour, do not retune it in a verification change.
- The HUD flash is visual only; headless tests check the icon sequence through `HeartsHud.advance`, not pixels.
