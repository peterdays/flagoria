# Map save files

A world's generation inputs (params and seeds) can be saved to and loaded from versioned JSON files in `user://saves/`.

## Sub-features

- `save-round-trip` `MapGen.save_map_inputs` / `load_map_inputs` (`Scripts/map_gen.gd`, format in `Scripts/map_save.gd`).
- `save-from-menu` the in-game menu's Save button (`Scripts/ingame_menu.gd`), `test_ingame_menu_save`.
- `save-reject` unknown versions, malformed files and unresolved seeds give clear errors.

## How to get to it (user POV)

- During a match: Menu (top right), then Save. The panel shows "Saved: MM-DD HH:MM".
- Otherwise through the `MapGen` autoload API.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_map_save_round_trip`, `-- test_map_save_rejects_bad_files` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- Files live under `user://`; with verify.sh's per-run user dirs they vanish after the run. Do not assert on a developer's real `user://saves/`.
