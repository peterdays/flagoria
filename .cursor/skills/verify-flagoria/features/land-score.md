# Land score

Drive: drives/land_score.gd

A player's conquest score is the number of interior city cells inside one of their flag towers' range (#279). `LandScore` (`Scripts/mechanics/conquest/land_score.gd`, the `World/LandScore` node) measures a Euclidean disk of `range_cells` (default 5) around each flag cell. A cell counts once when it is inside a city that player owns and inside that disk. Cells in the city but outside every such disk do not count. The host sets the count through `Points.set_land` (reason `land`), so the score HUD and the scoreboard show it with every other award. Losing the city, or handing the tower away, removes those points. While `LandScore.enabled` is true (the default) the flags-held timer does not pay; turn it off and `FlagsHeldPoints.tick` is the fallback.

A starting castle's flag is at most 2 cells from any courtyard cell, so the default 5 covers that courtyard. A wider city needs another tower. Tapping a flag cell selects that tower and draws the disk.

## Sub-features

- `land-score-range` one tower scores only the interior cells inside its disk; a second tower raises the total; opening the wall removes the city and the points. The scoreboard row matches `Points`.
- `land-score-ring` a tap on the castle flag selects that tower and draws a ring of radius `range_cells` tiles.
- `land-score-client` a client does not award. The host does, and both peers plus a late joiner share the totals. Neutralizing the host castle drops that total on all three.

## How to get to it (user POV)

1. Host. The starting castle courtyard scores at once. The top-left total and the scoreboard both show that count.
2. Tap the castle flag. A ring marks the land that flag covers.
3. Wall in a larger city. Cells outside every flag's ring do not add to the score until another flag tower covers them. Open a gap, or lose the flag, and those points go away.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_land_score_range` and `test_land_score_client_skips` together about 1 s in `tools/verify.sh` (~0.5 s each). `test_land_score_two_players` about 6 s alone; the stress job runs it at the job's tier. The drive is about 15 s under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=land_score_range,land_score_client_skips,land_score_two_players`, or the full `tools/verify.sh`.
- **Drive (live).** `bin/launch.sh drives/land_score.gd --display` (under xvfb, `--seed 11`). Steps `castle`, `ring`: `start_game()`, wait until the castle scores, `snapshot("castle")`, tap the castle flag, `snapshot("ring")`.
- **Proof.** Headers `-- test_land_score_range`, `-- test_land_score_client_skips`, `-- test_land_score_two_players` with no `FAIL` after them. Drive snapshots `01-castle` and `02-ring` under `--display`.

## Gotchas

- Radius 5 is the balance default. A castle courtyard is fully inside it. Set `LandScore.range_cells` to change the disk. The ring uses the same number.
- Flags-held is the fallback when `LandScore.enabled` is false. The live timer does not run while land score is on.
- A save stores earned points without the live land count. Loading applies the land again from the cities on the map.
- Only the host changes the total. A tap selects a tower on that screen alone.
