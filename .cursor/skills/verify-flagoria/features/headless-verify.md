# Headless verify

Headless verify opens the Godot 4.1 project, parses every GDScript file, and runs the headless test entry point so CI and local agents share one gate.

## Sub-features

- `verify-import-load` imports/opens the project headless via the editor.
- `verify-parse` parses each `.gd` with `--check-only`.
- `verify-tests` runs `res://tests/run_tests.gd` and requires `All tests passed.`

## How to get to it (user POV)

- Run `./tools/verify.sh` from the repo root (CI runs the same script).
- Or run the skill helper `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`.

## Driving it with verify-flagoria helpers

Preconditions:

- `doctor.sh` exits `0`.
- `GODOT` is Godot 4.1.x.

- **Run verify.** Execute `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`. Exit code `0`. Log contains `Project load: ok`, `Script parse: ok`, `Tests: ok`, and `Verification passed.`
- **Confirm tests.** The same log contains `All tests passed.` from `tests/run_tests.gd`.
- **Proof.** Keep `.cursor/skills/verify-flagoria/artifacts/verify.log` (written by the helper).

## Gotchas

- `--editor --quit` may print RID-leak `ERROR` lines on shutdown; `tools/verify.sh` treats those as non-fatal.
- A newer-than-4.1 Godot may migrate the project; doctor must reject it.
- Autoload names are invisible to `--check-only` on a single script; production code should use `/root/...` node paths where that matters.
