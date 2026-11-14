# Points scoreboard

Drive: drives/points_scoreboard.gd

Every connected player's point total opens from the score row toggle next to `N pts`. Rows sort highest first and update when totals change or players join or leave.

## Sub-features

- `points-scoreboard-panel` `ScoreboardPanel` (`Scripts/scoreboard_panel.gd`): lists connected peers using synced `Points` totals.
- `points-scoreboard-toggle` `ScoreHud` toggle beside the own-total label.

## How to get to it (user POV)

- Host or Join, tap the three-bar control beside the top-left score, read every player's total.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: about 2 s for `test_points_scoreboard_two_players` and `test_points_scoreboard_late_join`.

- **Run.** `./tools/verify.sh` or `--only=points_scoreboard_two_players,points_scoreboard_late_join`.
- **Proof.** `PASS test_points_scoreboard_two_players` and `PASS test_points_scoreboard_late_join` with no `FAIL` after them.
- **Drive (live).** `bin/launch.sh drives/points_scoreboard.gd --display` joins a second peer, walks the host for discovery points, opens the scoreboard, and writes `phone-scoreboard.png`.

## Gotchas

- Offline play lists only peer 1. Stale totals for disconnected peer ids stay in `Points` but do not appear while they are offline.