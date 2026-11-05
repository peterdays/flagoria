# Points

Drive: drives/combat_hud.gd

Players earn points for discovering ground and for killing mobs. The host owns every total and tells each peer. The score shows top left as `N pts`.

## Sub-features

- `points-core` `Points` (`Scripts/points.gd`): server-owned totals per peer, an award RPC, `points_changed` for the HUD.
- `points-discovery` `Scripts/discovery_points.gd`: `DISCOVERY_POINTS` 1 per new chunk-sized square walked into, checked every `CHECK_FRAMES` (15) frames and counted after two checks in a row.
- `points-mob-kill` `MOB_KILL_POINTS` slime 5, crab 8, piglet 10, paid to the player whose hit kills.
- `points-hud` `ScoreHud` shows `N pts` for the local player.

## How to get to it (user POV)

- Host, watch the top-left score, walk to new ground, kill a mob.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the six tests add about 3 s to `tools/verify.sh` (~4.2 s alone with `--only=`, mostly engine start and the two-player server).

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_points_award`, `-- test_points_hud_in_scene`, `-- test_points_mob_kill`, `-- test_points_sync`, `-- test_points_discovery`, `-- test_points_discovery_two_players` with no `FAIL` after them.
- **Drive (live).** `bin/launch.sh drives/combat_hud.gd` checks the HUD reads `0 pts` in a fresh game (see [Combat and aiming](./combat-and-aiming.md)).

## Gotchas

- Points are not saved in world saves; a new game starts at 0.
