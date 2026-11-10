# Map save files

Drive: drives/structure_save.gd

A world save holds a world's generation inputs (params and seeds) plus what was done to it since, and is saved to and loaded from versioned files in `user://saves/`. The current file is gzip of one compact JSON document, with a game version and created/updated times in the header. Version 1 and 2 files are plain JSON and still load. Terrain is never stored; the generator rebuilds it. The format is in `docs/world-saves.md`.

## Sub-features

- `save-round-trip` `MapGen.save_world` / `save_map_inputs` / `load_map_inputs` (`Scripts/map_gen.gd`; file I/O in `Scripts/map_save.gd`, contents in `Scripts/world_save.gd`). Change sections `tile_edits`, `object_changes`, `structures` and the opaque `player` object each round-trip on their own. Changes are sparse and keyed by 32-cell save chunk. The file is gzip. A second save of the same file keeps `created`.
- `save-cuts` cut trees and bushes go in `world.object_changes` with the type's `save_key` and the cut's age, come back as stumps before any chunk is drawn, and a client joining a loaded save gets the same stumps (see [Cut sync](./cut-sync.md)).
- `save-bridges` placed plank bridges go in `world.tile_edits` as one entry per plank cell naming its `BRIDGE_PLANK_*_WATER` piece (#226), come back before any chunk is drawn or any player spawns, and are walkable once drawn. Untouched cells regenerate from the seed; an old save with no `tile_edits` loads with no bridges.
- `save-structures` placed structures (castle, towers) with their owner and placement order, and free-form palisade walls, go in `world.structures` (#42, `Scripts/mechanics/structures/structure_saves.gd`) and come back before any chunk is drawn, flags in the owner's colour; cities rebuild from them. A loaded save with the host's castle keeps it as the spawn and places no second castle; an old save with no structures gets a fresh starting castle. Tower capture progress is not saved. Host alone: multiplayer structure sync is #278.
- `save-from-menu` the in-game menu's Save button (`Scripts/ingame_menu.gd`) names the save after the date and time (`YYYY-MM-DD HH-MM-SS`, ` 2` and so on when taken) and shows "Saved: MM-DD HH:MM".
- `save-migrate` a version 1 map save (inputs only) and a version 2 save load with empty change sections; every format version has a fixture in `tests/fixtures/`. Version 1 and 2 fixtures stay plain JSON. The version 3 fixture is gzip. Loading does not rewrite the file. The next save writes version 3 and keeps `created`.
- `save-reject` newer or unknown versions, another format, a bad clock or game version, a gzip that will not decompress, malformed files or change sections, and a seed left at 0 give clear errors and write no file.
- `save-size` a fresh world stays within 1024 compressed bytes, and 300 chunk-keyed plank edits stay within 8192. The test prints both measured sizes.
- `save-replace` a new save is written to `name.json.tmp`, read back, then renamed over `name.json`. A partial temp file or bytes that do not read back leave the previous save loadable, and the worlds list skips `.tmp` files.
- `save-list` `MapSave` lists saves newest first with name and date, renames and deletes them, and refuses a name outside the saves folder. The main menu Worlds screen shows that list and can load or delete; rename stays on the API (#40). See [Saved worlds](./saved-worlds.md).

## How to get to it (user POV)

- During a match: Menu (top right), then Save. The panel shows "Saved: MM-DD HH:MM".
- Otherwise through the `MapGen` autoload API.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the save tests together ~2.5 s alone with `--only=`; the section round-trip, the size budget and the failed-write check add well under 0.2 s in `tools/verify.sh`; `-- test_bridge_save_round_trip` ~2.8 s alone with `--only=` (about 0.2 s over the runner's own start-up, so about 0.2 s in `tools/verify.sh`); `-- test_structure_save_round_trip` ~2.4 s alone with `--only=` (about 0.2 s over the runner's start-up); `-- test_cut_save_late_join` starts a host and a client process.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_map_save_round_trip`, `-- test_map_save_rejects_bad_files`, `-- test_map_save_needs_every_seed`, `-- test_saved_maps_list_rename_delete`, `-- test_world_save_round_trip`, `-- test_world_save_section_round_trips`, `-- test_world_save_size_budget`, `-- test_world_save_version_check`, `-- test_world_save_migrates_v1`, `-- test_world_save_keeps_previous_on_failed_write`, `-- test_cut_save_round_trip`, `-- test_cut_save_in_game`, `-- test_cut_save_late_join`, `-- test_bridge_save_round_trip`, `-- test_structure_save_round_trip`, `-- test_ingame_menu_save` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`
- **Drive (live).** `bin/launch.sh drives/structure_save.gd --seed 11 --display` puts a mob-held wooden tower and a palisade ring by the start castle, saves with Save, leaves with Main menu, loads the save and hosts again. Shots `before_save` and `loaded` show the same castle, purple-flag tower and walls, one castle only. The tower and walls are placed through the map API, and this drive loads through `MapGen.load_map_inputs`. The Worlds list is [Saved worlds](./saved-worlds.md).
- **Drive (live).** `bin/launch.sh drives/chop_trees.gd --seed 49` chops a tree, saves through the in-game menu and checks `MapGen.map_saved` fired (see [Chop trees (live drive)](./chop-trees.md)).

## Gotchas

- Files live under `user://`; with verify.sh's per-run user dirs they vanish after the run. Do not assert on a developer's real `user://saves/`.
