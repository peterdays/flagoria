# Tests

`tests/run_tests.gd` is the headless test runner. `tools/verify.sh` runs it with no arguments, which runs every test.

## Adding a test

Write a `func _test_<name>() -> int` in `tests/run_tests.gd` that prints `-- test_<name>` and returns the number of failures. The runner finds it by name; nothing else needs to list it. Tests run in source order, and each must also pass on its own.

## Running one test

```bash
godot --headless --path . --script res://tests/run_tests.gd -- --only=map_zoom
godot --headless --path . --script res://tests/run_tests.gd -- --only=mob_chase,mob_contact
godot --headless --path . --script res://tests/run_tests.gd -- --list
```

`--only` takes names with or without the `test_` prefix. An unknown name prints the known names and exits `1`. The last lines are `Ran N of M tests.` and `All tests passed.` (or `Tests failed: K`).

Run `godot --headless --path . --import` once first on a fresh checkout. To avoid sharing `user://` with another run, give each run its own `XDG_DATA_HOME` (`tools/verify.sh` does this once #155 lands).
