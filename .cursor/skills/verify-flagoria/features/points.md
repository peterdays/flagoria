# Points

Drive: drives/combat_hud.gd

Players earn points for discovering ground and for killing mobs. The host owns every total and tells each peer. The score shows top left as `N pts`.

## Sub-features

- `points-core` `Points` (`Scripts/points.gd`): server-owned totals per peer, an award RPC, `points_changed` for the HUD.
- `points-discovery` `Scripts/discovery_points.gd`: `DISCOVERY_POINTS` 1 per new chunk-sized square walked into, checked every `CHECK_FRAMES` (15) frames and counted after two checks in a row.
- `points-mob-kill` `MOB_KILL_POINTS` slime 5, crab 8, piglet 10, paid to the player whose hit kills. The mob's name is the kill id. Host and clients add those points once: a second award message for that id does not change the total. Spawning a world's mobs clears the credited ids, so the next map's `mob_0` can pay. A joining peer is told which ids already paid only after its map is queued, so that list is not the first packet of the join.
- `points-hud` `ScoreHud` shows `N pts` for the local player and toggles the scoreboard (see [Points scoreboard](./points-scoreboard.md)).
- `points-flags-held` `FlagsHeldPoints` (`Scripts/mechanics/conquest/flags_held_points.gd`): `FLAGS_HELD_POINTS` 1 per owned flag tower every `INTERVAL` (5 s), reason `flags_held`; host alone. The timer is off while land score is on. See [Flags held points](./flags-held-points.md).
- `points-land` `LandScore` (`Scripts/mechanics/conquest/land_score.gd`): the count of interior city cells inside an owned flag's range, reason `land`. See [Land score](./land-score.md).

## How to get to it (user POV)

- Host, watch the top-left score, walk to new ground, kill a mob.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the eight tests add about 9 s to `tools/verify.sh` (~10 s alone with `--only=`, mostly engine start, the two-player servers, and `test_points_kill_late_join`). `test_points_mob_kill_once` is one loopback handshake, about 1 s. `test_points_kill_late_join` is a dedicated server plus two join probes, about 5 s.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_points_award`, `-- test_points_hud_in_scene`, `-- test_points_mob_kill`, `-- test_points_mob_kill_once`, `-- test_points_sync`, `-- test_points_discovery`, `-- test_points_discovery_two_players`, `-- test_points_kill_late_join` with no `FAIL` after them. `test_points_mob_kill_once` delivers the `mob_0` award twice and checks the score rose once on the host and on the client. `test_points_kill_late_join` credits `mob_0`, then a joiner must already have the map when the kill snapshot arrives, keep that total across a mob respawn, and see the new `mob_0` pay once.
- **Drive (live).** `bin/launch.sh drives/combat_hud.gd` checks the HUD label matches the points total in a fresh game (the castle's land may already be in it; see [Combat and aiming](./combat-and-aiming.md)).

## Gotchas

- The local total is `player.score` in a world save (see [Player save](./player-save.md)). A new match starts at 0. Chunks that already paid are stored with it, so a load does not pay them again.
