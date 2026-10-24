# Headless verify

Headless verify opens the Godot 4.7 project, parses every GDScript file, runs the headless test entry point, and then runs the biome, audio and generator checks, so CI and local agents share one gate.

## Sub-features

- `verify-import-load` imports/opens the project headless via the editor.
- `verify-parse` parses each `.gd` with `--check-only`.
- `verify-tests` runs `res://tests/run_tests.gd` and requires `All tests passed.`
- `verify-biomes` runs `res://tools/render_biomes.gd -- --seed=42 --size=4096 --step=16 --out=res://artifacts/out/verify_biomes` and requires `BIOME_COVERAGE_OK`. It fails when a biome covers 0 % of the area or its land grows no trees or bushes.
- `verify-audio` runs `res://tools/audio_check.gd` with `--audio-driver Dummy` and requires `AUDIO_CHECK_OK`. It drives the player scene through a timeline and fails when an expected sound is not heard, a step is silent or too loud, or the mix clips. On failure, see `artifacts/out/audio_check.png`.
- `verify-generators` runs `res://tools/generator_smoke.gd` and requires `GENERATOR_SMOKE_OK`. It checks the committed hero sheet, app icon and main menu theme. When `python3` with Pillow is available, verify first regenerates the hero sheet with `tools/hero/make_hero.py` into the run's temp dir and passes it as `--hero-sheet=`, which must match the committed sheet pixel for pixel; otherwise it prints `Hero regeneration: skipped` and checks only the committed art.

Each step's log is a temp file inside the run's own temp dir, which is removed on exit, including after Ctrl-C (exit 130) or SIGTERM (exit 143).

## How to get to it (user POV)

- Run `./tools/verify.sh` from the repo root (CI runs the same script).
- Or run the skill helper `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`.

## Driving it with verify-flagoria helpers

Preconditions:

- `doctor.sh` exits `0`.
- `GODOT` is Godot 4.7.x. When `GODOT` is unset, `tools/verify.sh` and `doctor.sh` both use `godot` on `PATH`.

- **Run verify.** Execute `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`. Exit code `0`. Log contains `Project load: ok`, `Script parse: ok`, `Tests: ok`, `Biome coverage: ok`, `Audio check: ok`, `Generator smoke: ok`, and `Verification passed.`
- **Confirm tests.** The same log contains `All tests passed.` from `tests/run_tests.gd`.
- **Proof.** Keep `.cursor/skills/verify-flagoria/artifacts/verify.log` (written by the helper).

## Gotchas

- `--editor --quit` may print RID-leak `ERROR` lines on shutdown; `tools/verify.sh` treats those as non-fatal.
- A newer-than-4.7 Godot may migrate the project. Doctor rejects any major.minor other than the one in `project.godot` `config/features`.
- Autoload names are invisible to `--check-only` on a single script; production code should use `/root/...` node paths where that matters.
