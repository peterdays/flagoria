# Tests

`tests/run_tests.gd` is the headless test runner. `tools/verify.sh` runs it with no arguments, which runs every test.

## Adding a test

Write a `func _test_<name>() -> int` in `tests/run_tests.gd` that prints `-- test_<name>` and returns the number of failures. The runner finds it by name; nothing else needs to list it. Tests run in source order, and each must also pass on its own.

Only top-level, non-static functions named `_test_<lowercase_name>` with no parameters are run. A test-like function that breaks one of these rules (parameters, uppercase letters, `static`, indented, or no leading underscore) is skipped and the runner prints `WARNING: skipped <name>: ...` on stderr.

## Running one test

```bash
godot --headless --path . --script res://tests/run_tests.gd -- --only=map_zoom
godot --headless --path . --script res://tests/run_tests.gd -- --only=mob_chase,mob_contact
godot --headless --path . --script res://tests/run_tests.gd -- --list
```

`--only` takes names with or without the `test_` prefix. An unknown name prints the known names and exits `1`. An empty `--only=` prints a usage message and exits `1`. The last lines are `Ran N of M tests.` and `All tests passed.` (or `Tests failed: K`).

Run `godot --headless --path . --import` once first on a fresh checkout. To avoid sharing `user://` with another run, give each run its own `XDG_DATA_HOME` (`tools/verify.sh` does this on every run).

## Netcode stress and the `needs-play-review` label

`tools/stress_netcode.py` runs every multiplayer scenario (a test that opens an ENet peer or starts another Godot process) 20 times, each in a fresh headless process with its own XDG dirs, and prints pass rate and worst wall time per scenario. Logs of failed runs go to `artifacts/out/stress/`. A scenario listed in `KNOWN_FLAKY` (with the issue that tracks it) gets one retry after a failed run and counts as failed only if the retry fails too; the `retried` column shows how often its first attempt failed. Remove the entry when its issue is fixed.

```bash
GODOT=/path/to/godot python3 tools/stress_netcode.py          # 20 runs each
python3 tools/stress_netcode.py -n 3 --only=mob_chase_two_players
python3 tools/stress_netcode.py --list
```

CI runs it (`.github/workflows/play-review.yml`) only for pull requests that carry `needs-play-review`. `.github/workflows/play-review-label.yml` adds that label when a pull request touches gameplay: player, mobs, scenes, HUD and menus, touch input, netcode, map generation parameters and saved worlds (`Scripts/map_gen.gd`, `Scripts/MapGenParams.gd`, `Scripts/map_save.gd`), or the `[input]` section of `project.godot`. The path list is in `tools/play_review_paths.py` (`--self-test` checks it).
