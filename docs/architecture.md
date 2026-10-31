# Architecture map and folder convention

Where each part of the game lives today, how data moves between the parts, and where new code goes. The structure checkpoint (#253) moves code into the target layout one small pull request at a time. This page lists both the current place and the target home, so it stays correct during the moves. Update it in the same pull request that moves or adds a script.

## Entry points

| Entry | What starts there |
|---|---|
| `project.godot` | Main scene `flagoria_main.tscn`, and five autoloads: `MapGen` (`Scripts/map_gen.gd`), `AudioSettings` (`Scripts/audio_settings.gd`), `GameSettings` (`Scripts/game_settings.gd`), `MusicPlayer` (`Scripts/music_player.gd`), `UiSfx` (`Scripts/ui_sfx.gd`). |
| `flagoria_main.tscn` + `flagoria_main.gd` | The game: main menu, HUD, `World/worldMap` (the `TileMap`), `World/Mobs`, `World/Interaction`, `Inventory`, `Points`, `Discovery`. Host, join, the dedicated server (`-- --server`), player spawn and the map-parameter sync. |
| `tests/run_tests.gd` | Headless test runner (`--only`, `--list`). It finds every `tests/**/test_*.gd` file; see `tests/README.md`. |
| `tools/verify.sh` | What CI's verify job runs: import, parse every script, run every test. |
| `tools/cli.gd` | Headless map commands (`map render`, `map stats`, in `tools/map_cli.gd`). |

## Main data flows

- **Map generation.** `Scripts/MapAdminPanel.gd` edits `MapGen.params` (a `MapGenParams`, saved to `user://map_gen_params.cfg`). Host emits `MainMenu.new_server_created`; `flagoria_main.gd` `setup_server` applies the params to `Scripts/TileMap.gd` (`apply_map_params`). Every `chunk_refresh_frames` frames (default 15) `Scripts/TileMap.gd` draws a chunk (default 32 x 32 cells) around the local player (`generate_chunk`): biome (`Scripts/BiomeCatalog.gd`), altitude (island and archipelago shaping in `Scripts/world/terrain_shape.gd`), then ground, plants and stones, named through `Scripts/tile_catalog.gd`. `predict_cell` gives the same answer for cells not drawn yet. Each draw emits `ground_changed`.
- **Spawn.** `Scripts/TileMap.gd` `resolve_player_spawn` finds reachable land; `free_spawn_position` keeps players apart. Both forward to `Scripts/world/spawn_finder.gd`. `flagoria_main.gd` places each player there.
- **Player and interaction.** `Player/character_body_2d.tscn` (`Scripts/player.gd`) handles movement, sword, camera zoom (`Scripts/map_zoom.gd`) and aim (`Scripts/attack_aim.gd`, styled by `Scripts/aim_cone_style.gd`). Health is `Scripts/player_health.gd`. `Scripts/interaction.gd` switches combat and interact mode. In interact mode it selects choppable cells (types from `Scripts/mechanics/interactables/` and `data/interactables/`), runs the chop, calls `Scripts/TileMap.gd` `cut_choppable` and adds the yield to `Scripts/inventory.gd`, which `Scripts/resource_hud.gd` shows. Interact mode is single-player only, and stumps regrow through `Scripts/TileMap.gd` `regrow_due`.
- **Not wired into play yet.** `Scripts/wall_solver.gd`, `Scripts/structure.gd` and `Scripts/TileMap.gd` `build_bridge` are only called from tests so far.
- **Mobs.** The server runs `Scripts/mob_spawner.gd` `spawn_for_world` (types and sheets from `Scripts/mob_catalog.gd`). Each mob runs `Scripts/mob.gd` on the server, and the other peers receive its state through the `MultiplayerSynchronizer` in `Mobs/mob.tscn`. Kills and discoveries pay out through `Scripts/points.gd` and `Scripts/discovery_points.gd`, and `Scripts/score_hud.gd` shows them.
- **Netcode.** ENet on UDP 9786 in `flagoria_main.gd`. The server owns the map params, mobs, health and points. A joining peer gets the full params through the `receive_map_params` RPC and builds the same map locally. Players spawn through the `MultiplayerSpawner` under `World`. Cuts are not synced (#223), so interact mode turns off while multiplayer is active. The multiplayer tests are stress-run by `tools/stress_netcode.py`.
- **UI and menus.** `Scripts/MainMenu.gd` (main menu, Host/Join, volumes, mob rate) opens `map_admin_panel.tscn`. `number_pad.tscn` gives touch keys for number fields. In play: `ingame_menu.tscn`, `quit_prompt.tscn`, `Scripts/hearts_hud.gd`, `Scripts/minimap_panel.gd` (draws `Scripts/explored_map.gd`). The theme is `art/ui/main_menu_theme.tres`.
- **Saves.** `Scripts/map_save.gd` reads and writes versioned JSON in `user://saves/`, written by the in-game menu's Save through `MapGen.save_world`. `Scripts/world_save.gd` is one save in memory: the generation inputs plus the world's changes. The dedicated server loads one with `--params`. See `docs/world-saves.md`.
- **Audio.** Buses are in `default_bus_layout.tres` and volumes in `Scripts/audio_settings.gd`. Music comes from `Scripts/music_player.gd` and UI sounds from `Scripts/ui_sfx.gd`. Per-instance sounds come from `Scripts/combat_sfx.gd`, `Scripts/footsteps.gd` and `Scripts/mob_sfx.gd`, with files in `art/audio/` (made by `tools/audio/`). See `docs/audio.md`.

## Folders today

| Folder | Holds |
|---|---|
| `Scripts/` | Game scripts, mostly flat. `Scripts/mechanics/interactables/` is the first mechanic folder. |
| root (`flagoria_main.gd`, `*.tscn`, `TouchScreenButton.gd`) | Main scene and top-level UI scenes. |
| `Player/`, `Mobs/` | Player, sword and mob scenes. |
| `data/` | Resource files a mechanic loads (`data/interactables/tree.tres`, `data/interactables/bush.tres`). |
| `art/` | Tiles, sprites, sounds, theme and their credits. |
| `structures/` | Hand-drawn structure text files (`structures/guard_post.txt`) in the format `Scripts/structure.gd` parses. |
| `addons/virtual_joystick/` | Vendored touch joystick. |
| `tests/` | Runner (`tests/run_tests.gd`, plus its own self-checks), area test files (`tests/<area>/test_*.gd`), shared helpers (`tests/helpers/test_helpers.gd`), probes started as separate processes, `tests/fixtures/`, `tests/golden/`. |
| `tools/` | Verify, CLI, renders, asset generators, CI helpers (`tools/pr_hygiene.py`, `tools/play_review_paths.py`, `tools/stress_netcode.py`, `tools/ci_job_times.py`). |
| `.github/workflows/` | verify, pr-hygiene, play-review-label, play-review, pr-debug-apk, android-apk, job-times. |
| `.cursor/skills/verify-flagoria/` | Launch, doctor and drive scripts, and one feature file per feature under `.cursor/skills/verify-flagoria/features/`. |
| `docs/` | Feature and process notes. |

## Target layout (#253)

- `Scripts/world/`: map generation helpers (terrain shape, spawn search).
- `Scripts/mechanics/<mechanic>/`: one folder per mechanic: `trees/`, `bridges/`, `walls/`, `structures/`, `interact/`, `interactables/`, later `building/` and `conquest/`.
- `tests/<area>/test_*.gd`: tests per area (`world/`, `saves/`, `mobs/`, `combat/`, `player/`, `points/`, `ui/`, `audio/`, `net/`) or per mechanic (`tests/mechanics/<mechanic>/`), with shared helpers in `tests/helpers/test_helpers.gd`. The runner finds these files (#255). `tests/run_tests.gd` keeps only its own self-checks.

## Rules

- A mechanic owns its logic, data and tests: scripts in `Scripts/mechanics/<mechanic>/`, resources in `data/<mechanic>/`, tests in `tests/mechanics/<mechanic>/`.
- Shared catalogues stay where they are: `Scripts/tile_catalog.gd` (a data table, allowed to stay large), `Scripts/BiomeCatalog.gd`, `Scripts/mob_catalog.gd`, `Scripts/MapGenParams.gd`.
- Autoloads stay in `Scripts/` unless a pull request moves one on purpose and updates `project.godot`.
- Moving a script: `git mv` the `.gd` and its `.gd.uid` together, so the uid stays next to the script. Scenes here load scripts by `path=` without a `uid=`, so the same pull request also updates every `res://` path to the script: scenes, `preload`/`load` calls, tests, and the path lists in `tools/play_review_paths.py`. `test_tile_catalog` scans `Scripts/` and its subfolders.
- No behaviour change in a move pull request. Keep thin wrappers with the old names until callers move.
- Each new test or verify step states its time cost in the pull request ("Time cost" line). CI reports each job's time per run (#294).

## Every script and its home

"Stays" means no move is planned in #253.

| Script | Owns | Target home |
|---|---|---|
| `flagoria_main.gd` | Host, join, dedicated server, spawn placement, params sync | stays |
| `TouchScreenButton.gd` | On-screen attack button look and place | stays |
| `Scripts/TileMap.gd` | Chunk drawing, terrain shape, plants, cuts and regrowth, bridges, spawn search | stays for chunk drawing. Moved: terrain shape is in `Scripts/world/terrain_shape.gd` and spawn search in `Scripts/world/spawn_finder.gd` (#260); `Scripts/TileMap.gd` keeps wrappers with the old names. Tree cuts go to `Scripts/mechanics/trees/tree_cuts.gd` and bridges to `Scripts/mechanics/bridges/bridge_builder.gd` (#261). |
| `Scripts/interaction.gd` | Combat/interact mode, selection, reach, gating, chop | `Scripts/mechanics/interact/interaction.gd`; chop to `Scripts/mechanics/trees/chop_action.gd` (#262) |
| `Scripts/wall_solver.gd` | Wall piece per cell from neighbours | `Scripts/mechanics/walls/wall_solver.gd` (#261) |
| `Scripts/structure.gd` | Parse and place hand-drawn structures | `Scripts/mechanics/structures/structure.gd` (#261) |
| `Scripts/mechanics/interactables/interactable_type.gd` | One choppable type (resource) | already home |
| `Scripts/mechanics/interactables/interactable_catalog.gd` | Every choppable type, tile lookup | already home |
| `Scripts/tile_catalog.gd` | Tile names to atlas coords | stays (shared data table) |
| `Scripts/BiomeCatalog.gd` | Biome ids and per-biome tables | stays (shared catalogue) |
| `Scripts/MapGenParams.gd` | Map generation parameters resource | stays (shared) |
| `Scripts/map_gen.gd` | Autoload: active params, save/load hooks | stays (autoload) |
| `Scripts/world_seeder.gd` | Legacy seed bag, no callers | stays |
| `Scripts/map_save.gd` | Versioned JSON save files | stays |
| `Scripts/world_save.gd` | One saved world in memory | stays |
| `Scripts/player.gd` | Player movement, sword, animation | stays |
| `Scripts/player_health.gd` | Health, regen, death, respawn (server owned) | stays |
| `Scripts/attack_aim.gd` | Attack aim by mouse or drag | stays |
| `Scripts/aim_cone_style.gd` | Aim cone look (resource) | stays |
| `Scripts/map_zoom.gd` | Camera pinch, wheel and key zoom | stays |
| `Scripts/inventory.gd` | Gathered resources | stays |
| `Scripts/mob.gd` | One mob's behaviour and sync | stays |
| `Scripts/mob_spawner.gd` | Server mob placement | stays |
| `Scripts/mob_catalog.gd` | Mob types and sheet layout | stays (shared catalogue) |
| `Scripts/points.gd` | Point totals (server owned) | stays |
| `Scripts/discovery_points.gd` | First-visit discovery points | stays |
| `Scripts/explored_map.gd` | Explored cells per chunk | stays |
| `Scripts/minimap_panel.gd` | In-play explored map panel | stays |
| `Scripts/hearts_hud.gd` | Hearts row | stays |
| `Scripts/score_hud.gd` | Point total label | stays |
| `Scripts/resource_hud.gd` | Wood count | stays |
| `Scripts/MainMenu.gd` | Main menu | stays |
| `Scripts/MapAdminPanel.gd` | Map Settings panel | stays |
| `Scripts/number_pad.gd` | Touch keys for number fields | stays |
| `Scripts/ingame_menu.gd` | In-game menu, Save | stays |
| `Scripts/quit_prompt.gd` | Quit prompt | stays |
| `Scripts/game_settings.gd` | Autoload: mob spawn rate | stays (autoload) |
| `Scripts/audio_settings.gd` | Autoload: bus volumes | stays (autoload) |
| `Scripts/music_player.gd` | Autoload: music | stays (autoload) |
| `Scripts/ui_sfx.gd` | Autoload: UI sounds | stays (autoload) |
| `Scripts/combat_sfx.gd` | Player combat and health sounds | stays |
| `Scripts/footsteps.gd` | Terrain footsteps | stays |
| `Scripts/mob_sfx.gd` | Mob sounds | stays |

## Where does X go

| New thing | Goes in |
|---|---|
| A new mechanic (logic) | `Scripts/mechanics/<mechanic>/` |
| Its resources (`.tres`) | `data/<mechanic>/` |
| Its tests | `tests/mechanics/<mechanic>/test_<topic>.gd` |
| Its verify recipe | `.cursor/skills/verify-flagoria/features/<feature>.md` (#291) |
| Map generation helper | `Scripts/world/` |
| A new tile name | `Scripts/tile_catalog.gd` |
| A new biome table entry | `Scripts/BiomeCatalog.gd` |
| A new map parameter | `Scripts/MapGenParams.gd` |
| A new mob type | `Scripts/mob_catalog.gd` |
| Test helper shared by several files | `tests/helpers/test_helpers.gd` |
| Dev or CI tool | `tools/` (asset generators under `tools/audio/`, `tools/hero/`, `tools/icon/`) |
| CI workflow | `.github/workflows/` |
| Art and sound | `art/`, with credits next to the files (for example `art/audio/CREDITS.md`) |
| Feature or process notes | `docs/` |
