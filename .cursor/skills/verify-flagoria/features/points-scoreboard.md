# Points scoreboard

Drive: drives/points_scoreboard.gd

Every connected player's point total opens from the score row toggle next to `N pts`. Rows sort highest first and update when totals change or players join or leave.

## Sub-features

- `points-scoreboard-panel` `ScoreboardPanel` (`Scripts/scoreboard_panel.gd`): lists connected peers using synced `Points` totals.
- `points-scoreboard-toggle` round `ScoreboardToggle` (`Scripts/scoreboard_toggle.gd`) beside the own-total label; layout id `scores` in Customize HUD (#492).

## How to get to it (user POV)

- Host or Join, tap the round scores icon beside the top-left `N pts`, read every player's total (colour swatch, `You` or `Player N` / display name).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: about 2.5 s for the three `test_points_scoreboard_*` cases; the four-client drive about 25 s.

- **Run.** `./tools/verify.sh` or `--only=points_scoreboard_two_players,points_scoreboard_late_join,points_scoreboard_four_players`.
- **Proof.** `PASS test_points_scoreboard_two_players`, `PASS test_points_scoreboard_late_join`, and `PASS test_points_scoreboard_four_players` with no `FAIL` after them.
- **Drive (live).** `bin/launch.sh drives/points_scoreboard.gd --display` joins three peers (four players), walks the host for discovery points, opens the scoreboard, and writes `phone-scoreboard.png`.

## Gotchas

- Offline play lists only peer 1. Stale totals for disconnected peer ids stay in `Points` but do not appear while they are offline.