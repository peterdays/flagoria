# Flags held points

Drive: not player-facing

Every owned flag tower pays points on a timer (#275). `FlagsHeldPoints` (`Scripts/mechanics/conquest/flags_held_points.gd`, the `FlagsHeldPoints` node next to `Points` / `Discovery` in `flagoria_main.tscn`) awards `Points.FLAGS_HELD_POINTS` (1) with reason `flags_held` for each placement that has a `team` flag and a peer owner (id > 0). Neutral and mob-owned towers pay nothing. The interval is `FlagsHeldPoints.INTERVAL` (5 s). Awards go through the Points core, so the score HUD picks them up like any other reason. The host awards with peers connected; a client does not (#497). Both peers' totals match because `Points` replicates each award. The background tick has no dedicated drive; the two-player total check is `test_tower_place_two_players`.

## Sub-features

- `flags-held-awards` two host-owned towers pay once each on every tick; three ticks award `2 × 3 × FLAGS_HELD_POINTS`. Handing one tower to the mobs stops that tower's points on further ticks.
- `flags-held-skips-non-players` neutral and mob-owned towers never pay.
- `flags-held-off-in-multiplayer` a connecting client pays nothing; back offline it awards again. The host awards with peers connected (`test_tower_place_two_players`).

## How to get to it (user POV)

- Main menu → Host, own at least one flag tower (the starting castle, or a built/captured one). Every 5 s the top-left score grows by one point per owned tower.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the three tests in `tests/mechanics/conquest/test_flags_held_points.gd` take about 0.5 s together in `tools/verify.sh` (about 0.15–0.2 s each; ~2 s alone with `--only=` for all three, against ~1.5 s for runner start-up). They call `FlagsHeldPoints.tick` by hand, so no test waits on real time.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_flags_held_awards_per_tower`, `-- test_flags_held_skips_non_players`, `-- test_flags_held_off_in_multiplayer` with no `FAIL` after them.
- **Drive (live).** None. Watching the score tick up while holding towers is covered by play, not by an automated drive (5 s per tick is slow for CI evidence).

## Gotchas

- Points from held flags are not saved in world saves; a new game starts at 0 (same as other point sources).
- A client does not award. The host does, and `Points` sends the new totals (#497).
