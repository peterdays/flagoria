# Saved worlds

Drive: drives/saved_worlds.gd

The main menu Worlds screen lists every world save by name and the time the file was last written. Each row shows a small terrain preview from that save's generation inputs (`Scripts/world_save_preview.gd`), cached under `user://saves/_previews/v2/` (whole-world fit, minimap palette), with a plain placeholder when a preview is missing or broken. Load hosts that world. Host, and New world, start a match that saves into a new file, so an existing save is not replaced. Save writes that match's file again. Delete asks first, then removes the file and its preview. Rename opens an inline name field; confirm calls `MapSave.rename_save` and renames the cached preview too.

## Sub-features

- `worlds-list` `CanvasLayer2/WorldsPanel` (`Scripts/MainMenu.gd`) lists `MapSave.list_saves()`, newest first, as the file name and `YYYY-MM-DD HH:MM`, with a 64×40 terrain thumbnail per row, in a scroll box when the list overflows.
- `worlds-load` Load calls `MapGen.load_map_inputs` for the selected file and hosts it. Later saves of that match replace the same file.
- `worlds-new` Host and New world clear any loaded world and pick a new file name. The file is written on the first Save.
- `worlds-delete` Delete asks "Delete this world?" and Yes calls `MapSave.delete_save`.
- `worlds-rename` Rename shows a name field prefilled with the selected save; Confirm calls `MapSave.rename_save` and refreshes the list with the new name still selected.
- `worlds-legacy` a version 1 file already in `user://saves/` is listed and loads. Opening the list does not rewrite it. A file this build writes is format version 3 (gzip). The list still shows the file's modified time and does not open the file.

## How to get to it (user POV)

- On the main menu, tap Worlds. Tap a row, then Load, New world, Delete, or Rename.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the three headless tests add about 1 s to `tools/verify.sh`. The live drive is about 15 s with `--display`.

- **Run.** `godot --headless --path . --script res://tests/run_tests.gd -- --only=saved_world_round_trip,two_worlds_stay_separate,legacy_save_stays_in_the_list,saved_world_rename_panel,worlds_list_scroll,world_save_preview`, or `./tools/verify.sh`.
- **Drive (live).** `bin/launch.sh drives/saved_worlds.gd --seed 49 --display`. Host and Save one world, return to the menu, start another, cut the nearest plant, Save, and open Worlds. `list` shows both rows. Load the first world (`loaded-a`: the plant is still there) and the second (`loaded-b`: that plant is a stump). For rename: `bin/launch.sh drives/worlds_rename.gd --display`. For scroll overflow: `bin/launch.sh drives/worlds_list_scroll.gd --display` (1280x720 and 2400x1080 shots). For terrain previews at the phone viewport: `bin/launch.sh drives/worlds_list_previews.gd --display` (854×480 window, `worlds-list-phone` with three saves).
- **Proof.** `-- test_saved_world_round_trip` hosts the save that was chosen. `-- test_two_worlds_stay_separate` rewrites one file and leaves the other, then deletes one. `-- test_legacy_save_stays_in_the_list` loads `tests/fixtures/world_save_v1.json` without changing the file. `-- test_saved_world_rename_panel` renames through the panel, rejects a duplicate, and cancel leaves the file. `-- test_worlds_list_scroll` checks overflow scrolling by wheel and touch drag, and row tap selection without hosting, at 1280x720 and 2400x1080. `-- test_world_save_preview` builds a stable preview from params, lists a save with no cache and loads it.

## Gotchas

- Files live under `user://`. A verify run uses its own user dir. Do not assert on a real saves folder.
- A save also keeps that peer's position, health, wood, score and charted ground (see [Player save](./player-save.md)). Two worlds of the same seed still differ where the world itself changed.
