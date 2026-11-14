# Architecture map and folder convention

Where each part of the game lives today, how data moves between the parts, and where new code goes. The structure checkpoint (#253) moves code into the target layout one small pull request at a time. This page lists both the current place and the target home, so it stays correct during the moves. Update it in the same pull request that moves or adds a script.

## Entry points

| Entry | What starts there |
|---|---|
| `project.godot` | Main scene `flagoria_main.tscn`, and six autoloads: `MapGen` (`Scripts/map_gen.gd`), `AudioSettings` (`Scripts/audio_settings.gd`), `GameSettings` (`Scripts/game_settings.gd`), `HudLayout` (`Scripts/hud_layout.gd`), `MusicPlayer` (`Scripts/music_player.gd`), `UiSfx` (`Scripts/ui_sfx.gd`). |
| `flagoria_main.tscn` + `flagoria_main.gd` | The game: main menu, HUD, `World/worldMap` (the `TileMap`), `World/Mobs`, `World/Interaction`, `Inventory`, `Points`, `Discovery`. Host, join, the dedicated server (`-- --server`), player spawn and the map-parameter sync. |
| `tests/run_tests.gd` | Headless test runner (`--only`, `--list`). It finds every `tests/**/test_*.gd` file; see `tests/README.md`. |
| `tools/verify.sh` | What CI's verify job runs: import, parse every script, run every test. |
| `tools/cli.gd` | Headless map commands (`map render`, `map stats`, in `tools/map_cli.gd`). |

## Main data flows

- **Map generation.** `Scripts/MapAdminPanel.gd` edits `MapGen.params` (a `MapGenParams`, saved to `user://map_gen_params.cfg`). Host emits `MainMenu.new_server_created`; `flagoria_main.gd` `setup_server` applies the params to `Scripts/TileMap.gd` (`apply_map_params`). Every `chunk_refresh_frames` frames (default 15) `Scripts/TileMap.gd` draws a chunk (default 32 x 32 cells) around the local player (`generate_chunk`): biome (`Scripts/BiomeCatalog.gd`), altitude (island and archipelago shaping in `Scripts/world/terrain_shape.gd`), then ground, plants and stones (plants and stones picked in `Scripts/world/plant_picker.gd`), named through `Scripts/tile_catalog.gd`. `predict_cell` gives the same answer for cells not drawn yet. Each draw emits `ground_changed`.
- **Spawn.** `Scripts/TileMap.gd` `resolve_player_spawn` finds reachable land; `free_spawn_position` keeps players apart. Both forward to `Scripts/world/spawn_finder.gd`. `flagoria_main.gd` places each player there. A host that plays first places its starting castle next to the spawn (`place_start_castle`, forwarding to `Scripts/world/start_castle.gd`), and the land outside the castle gate becomes the spawn.
- **Player and interaction.** `Player/character_body_2d.tscn` (`Scripts/player.gd`) handles movement, sword, camera zoom (`Scripts/map_zoom.gd`) and aim (`Scripts/attack_aim.gd`, styled by `Scripts/aim_cone_style.gd`). The run control (`Scripts/mechanics/run/run_control.gd`) scales that walk while its button is held or latched, or while the run action is down. Health is `Scripts/player_health.gd`. `Scripts/mechanics/interact/interaction.gd` switches combat and interact mode. In interact mode the attack button aims a chop cone (`Scripts/mechanics/interact/chop_stick.gd`) at choppable cells (types from `Scripts/mechanics/interactables/` and `data/interactables/`; adding one: `docs/interactables.md`), and the chop runs through `Scripts/mechanics/trees/chop_action.gd`, calls `Scripts/TileMap.gd` `cut_choppable` (which forwards to `Scripts/mechanics/trees/tree_cuts.gd`) and adds the yield to `Scripts/inventory.gd`, which `Scripts/resource_hud.gd` shows. Stumps regrow through `Scripts/TileMap.gd` `regrow_due` (also in `tree_cuts.gd`).
- **Structures.** `Scripts/TileMap.gd` `place_structure` forwards to `Scripts/mechanics/structures/structure_placer.gd`, which reads `Scripts/mechanics/structures/structure.gd` files. Auto walls and tower rings are solved together with free-form palisades by `Scripts/mechanics/walls/wall_solver.gd` (`WallBuilder.resolve`). In play the starting castle and the buildable wooden tower (#273) use it. `World/TowerCapture` (`Scripts/mechanics/conquest/tower_capture.gd`) treats each placement's team flag as a tower that players and mobs capture by standing next to it, and hands it over with `StructurePlacer.set_owner`. In multiplayer the host advances capture and sends owner and progress (#497). `Scripts/TileMap.gd` `build_bridge` (which forwards to `Scripts/mechanics/bridges/bridge_builder.gd`) is only called from tests so far. What each build costs in wood is `Scripts/mechanics/building/build_costs.gd` (#272), whose `buy` spends through `Scripts/inventory.gd` `spend`. Shared placement is `Scripts/mechanics/building/construction_placer.gd` (#296): `can_place` / `cost` / `place` for each kind (plank, wooden tower and free-form wall block), calling `buy` into `build_bridge`, `place_structure` or `place_wall_cells`. The build tools are `Scripts/mechanics/building/build_placement.gd` (#225 / #273 / #276): round Plank / Tower / Wall buttons in a column under Buildings (#480), Cut when none is selected, H/V snap, tower footprint preview, wall tip chain, green/red preview; `Interaction` wires it. Free-form walls live in `Scripts/mechanics/walls/wall_builder.gd` (#276). `World/Cities` (`Scripts/mechanics/conquest/cities.gd`) flood-fills from each flag through wall barriers to make a city (tint + minimap; capture transfers ownership). In multiplayer the host runs that fill and sends the list (#498). `World/LandScore` (`Scripts/mechanics/conquest/land_score.gd`) counts interior cells inside each owner's flag range and the host sets that count on `Points` (#279). A tap on a flag draws the range ring.
- **Mobs.** The server runs `Scripts/mob_spawner.gd` `spawn_for_world` (types and sheets from `Scripts/mob_catalog.gd`). Each mob runs `Scripts/mob.gd` on the server, and the other peers receive its state through the `MultiplayerSynchronizer` in `Mobs/mob.tscn`. Kills and discoveries pay out through `Scripts/points.gd` and `Scripts/discovery_points.gd`, and `Scripts/score_hud.gd` shows them.
- **Netcode.** ENet on UDP 9786 in `flagoria_main.gd`. The server owns the map params, mobs, health and points. A joining peer gets the full params, the host's tree and bush cuts and its placed structures through the `receive_map_params` RPC (cuts past the first 500 follow in `receive_join_cuts`, #354) and builds the same map locally. A tower or free-form wall placed after the join is a request to the host (`StructureRequests`, #497, #498), which writes it and sends it to every peer. A joining peer's starting castle is placed by the host outside the shared spawn and sent the same way (#278). Capture progress and cities ride with that join. A late joiner also receives the solved auto junction cells. Players spawn through the `MultiplayerSpawner` under `World`. A cut during play is asked of the host (`Interaction.request_cut`, limited per peer by `CutRateLimit`, #355), which decides it and sends the stump to every peer (`apply_cut`) and the wood to the cutter; the host also decides regrowth and sends the plants that regrew in each tick to every peer in one message (`apply_regrow_cells`, #298, #353). The multiplayer tests are stress-run by `tools/stress_netcode.py`.
- **UI and menus.** `Scripts/MainMenu.gd` (main menu, Host/Join, volumes, mob rate) opens `map_admin_panel.tscn`. `number_pad.tscn` gives touch keys for number fields. In play: `ingame_menu.tscn`, `quit_prompt.tscn`, `Scripts/hearts_hud.gd`, `Scripts/hud_tool_row.gd` (top-right Buildings, Map and Mode arc, #480), `Scripts/hud_layout.gd` (per-device touch control layout in `user://`, #492), `Scripts/minimap_panel.gd` (draws `Scripts/explored_map.gd`; starts closed; header collapse and maximize), `Scripts/parchment_map.gd` (the full parchment sheet) and `Scripts/map_wood_button.gd` (those wood controls). The theme is `art/ui/main_menu_theme.tres`.
- **Saves.** `Scripts/map_save.gd` reads and writes versioned saves in `user://saves/` (gzip of one JSON document; older plain JSON still loads), written by the in-game menu's Save through `MapGen.save_world`. Each match has its own file: the main menu lists them and loads one, and Save replaces that file. `Scripts/world_save.gd` is one save in memory: the generation inputs plus the world's changes. The dedicated server loads one with `--params`. See `docs/world-saves.md`.
- **Audio.** Buses are in `default_bus_layout.tres` and volumes in `Scripts/audio_settings.gd`. Music comes from `Scripts/music_player.gd` and UI sounds from `Scripts/ui_sfx.gd`. Per-instance sounds come from `Scripts/combat_sfx.gd`, `Scripts/footsteps.gd` and `Scripts/mob_sfx.gd`, with files in `art/audio/` (made by `tools/audio/`). See `docs/audio.md`.

## Folders today

| Folder | Holds |
|---|---|
| `Scripts/` | Game scripts, mostly flat. `Scripts/mechanics/interactables/` is the first mechanic folder. |
| root (`flagoria_main.gd`, `*.tscn`, `TouchScreenButton.gd`) | Main scene and top-level UI scenes. |
| `Player/`, `Mobs/` | Player, sword and mob scenes. |
| `data/` | Resource files a mechanic loads (`data/interactables/tree.tres`, `pine.tres`, `bush.tres`). |
| `art/` | Tiles, sprites, sounds, theme and their credits. |
| `assets/ui/hud/` | HUD button icons for Buildings, Map, Run and the two mode states. Imported without mipmaps; the buttons draw them nearest-neighbour. |
| `structures/` | Hand-drawn structure text files (`structures/guard_post.txt`, `structures/castle.txt`) in the format `Scripts/mechanics/structures/structure.gd` parses. |
| `addons/virtual_joystick/` | Vendored touch joystick. |
| `addons/server_shutdown/` | Linux SIGTERM helper for `-- --server` only. |
| `Dockerfile`, `docker-compose.yml`, `docker/` | Non-root dedicated-server image. The game is not rebuilt there beyond Godot's import. |
| `tests/` | Runner (`tests/run_tests.gd`, plus its own self-checks), area test files (`tests/<area>/test_*.gd`), shared helpers (`tests/helpers/test_helpers.gd`), probes started as separate processes, `tests/fixtures/`, `tests/golden/`. |
| `tools/` | Verify, CLI, renders, asset generators, CI helpers (`tools/pr_hygiene.py`, `tools/private_server_doc.py`, `tools/file_budget.py`, `tools/play_review_paths.py`, `tools/verify_drive_picks.py`, `tools/stress_netcode.py`, `tools/stress_scenario_lint.py`, `tools/ci_job_times.py`, `tools/issue_triage.py`, `tools/required_checks.py`), and local git hooks (`tools/commit_identity_hook.py`, `tools/staged_import_hook.py`). |
| `.github/workflows/` | verify, pr-hygiene, play-review-label, play-review, pr-debug-apk, android-apk, job-times, issue-triage. |
| `.cursor/skills/verify-flagoria/` | Launch, doctor and drive scripts, and one feature file per feature under `.cursor/skills/verify-flagoria/features/`. |
| `docs/` | Feature and process notes, e.g. `docs/interactables.md` (checklist for a new choppable type). |

## Target layout (#253)

- `Scripts/world/`: map generation helpers (terrain shape, plant picking, spawn search, starting castle).
- `Scripts/mechanics/<mechanic>/`: one folder per mechanic: `trees/`, `bridges/`, `walls/`, `structures/`, `interact/`, `interactables/`, later `building/` and `conquest/`.
- `tests/<area>/test_*.gd`: tests per area (`world/`, `saves/`, `mobs/`, `combat/`, `player/`, `points/`, `ui/`, `audio/`, `net/`) or per mechanic (`tests/mechanics/<mechanic>/`), with shared helpers in `tests/helpers/test_helpers.gd`. The runner finds these files (#255). `tests/run_tests.gd` keeps only its own self-checks.

## Rules

- A mechanic owns its logic, data and tests: scripts in `Scripts/mechanics/<mechanic>/`, resources in `data/<mechanic>/`, tests in `tests/mechanics/<mechanic>/`.
- File size budget: a script under `Scripts/` or `flagoria_main.gd` stays within 500 lines and a test file within 1,500. `tools/verify.sh` runs `tools/file_budget.py`, and only files listed in `tools/file_budget_allow.txt`, each with a reason and a cap, may be larger.
- Shared catalogues stay where they are: `Scripts/tile_catalog.gd` (a data table, allowed to stay large), `Scripts/BiomeCatalog.gd`, `Scripts/mob_catalog.gd`, `Scripts/MapGenParams.gd`.
- Autoloads stay in `Scripts/` unless a pull request moves one on purpose and updates `project.godot`.
- Moving a script: `git mv` the `.gd` and its `.gd.uid` together, so the uid stays next to the script. Scenes here load scripts by `path=` without a `uid=`, so the same pull request also updates every `res://` path to the script: scenes, `preload`/`load` calls, tests, and the path lists in `tools/play_review_paths.py`. `test_tile_catalog` scans `Scripts/` and its subfolders.
- No behaviour change in a move pull request. Keep thin wrappers with the old names until callers move.
- Each new test or verify step states its time cost in the pull request ("Time cost" line). CI reports each job's time per run (#294).
- Netcode stress scenarios are deterministic and the stress job stops at the first failed run. The rule is [Writing netcode stress scenarios](../AGENTS.md#writing-netcode-stress-scenarios). `tools/verify.sh` runs `tools/stress_scenario_lint.py`.
- Every new player-facing mechanic (a new choppable, a tower, a wall type, a city rule) adds its feature file, `.cursor/skills/verify-flagoria/features/<feature>.md`, and its index line in `features/README.md` in the same pull request. When a player can reach the feature in a running game, the same pull request also adds a drive under `.cursor/skills/verify-flagoria/drives/`. A change that is not player-facing says so on the pull request template's feature-file line (#291).
- Before each checkpoint in #253's gate, a verification maintenance pass runs over `.cursor/skills/verify-flagoria/`. The pass covers index hygiene (every feature file is in the index, and every index line points at a file that exists), one source read per feature file (its paths, names and steps still match the code), and one live drive per reachable feature. Its outcome goes in a short comment on #253: clean, changed (with the PR link), or blocked (with the reason). The pass edits only the skill directory; any product bug it finds gets its own issue.

## Every script and its home

"Stays" means no move is planned in #253.

| Script | Owns | Target home |
|---|---|---|
| `flagoria_main.gd` | Host, join, dedicated server, spawn placement, params sync | stays |
| `TouchScreenButton.gd` | On-screen attack button look and place | stays |
| `Scripts/TileMap.gd` | Chunk drawing, plants; wrappers for terrain shape, cuts and regrowth, bridges, spawn search | stays for chunk drawing. Moved: terrain shape is in `Scripts/world/terrain_shape.gd` and spawn search in `Scripts/world/spawn_finder.gd` (#260); `Scripts/TileMap.gd` keeps wrappers with the old names. Tree and bush cuts and regrowth are in `Scripts/mechanics/trees/tree_cuts.gd` and bridges in `Scripts/mechanics/bridges/bridge_builder.gd` (#261), also behind same-name wrappers. Plant and stone picking is in `Scripts/world/plant_picker.gd`, behind the `plant_tile` and `structure_tile` wrappers. |
| `Scripts/mechanics/interact/interaction.gd` | Combat/interact mode, selection, reach, gating; wrappers for the chop | moved from `Scripts/interaction.gd` (#262) |
| `Scripts/mechanics/trees/chop_action.gd` | One chop: timing, hits, effects, sounds, hero pose | split from `Scripts/interaction.gd` (#262); `Interaction` keeps wrappers with the old names |
| `Scripts/mechanics/walls/wall_solver.gd` | Wall piece and collar list per cell from neighbours, including tower rings | moved from `Scripts/wall_solver.gd` (#261) |
| `Scripts/mechanics/structures/structure.gd` | Parse hand-drawn structures | moved from `Scripts/structure.gd` (#261) |
| `Scripts/mechanics/structures/structure_placer.gd` | Check and place a parsed structure on the map, keep placements across redraws | new (#270) |
| `Scripts/mechanics/building/build_costs.gd` | Wood cost and refund per buildable; buy: check wood, spend, place | new (#272) |
| `Scripts/mechanics/building/build_placement.gd` | Buildings column of round Plank/Tower/Wall buttons, snapped plank/wall and tower footprint preview via ConstructionPlacer | stays (#225 / #273 / #276, #480) |
| `Scripts/mechanics/building/build_placement_rotate.gd` | Round rotate control beside footprint placement preview | new (#493) |
| `Scripts/mechanics/building/footprint_orientation.gd` | Rotated facing marker on preview and placed footprint tools | new (#493) |
| `Scripts/mechanics/building/structure_requests.gd` | Host-request pipeline for towers, free-form walls, and a joining peer's starting castle | new (#497, #498, #278) |
| `Scripts/mechanics/building_blocks/building_block_piece.gd` | One WFC modular piece: TileCatalog tile and cardinal edge sockets | new (#23) |
| `Scripts/mechanics/building_blocks/building_block_catalog.gd` | Piece set, socket compatibility and adjacency table for WFC | new (#23) |
| `Scripts/mechanics/building_blocks/wfc_solver.gd` | Pure GDScript WFC: collapse, propagate, seeded restarts (#24) | new (#24) |
| `Scripts/mechanics/walls/wall_builder.gd` | Free-form palisade cells, shared solve with structure walls and towers, piece and collar paint, kept on redraw | new (#276) |
| `Scripts/world/plant_picker.gd` | Plant or stones for one walkable cell from altitude, moisture, chance and biome | moved from `Scripts/TileMap.gd` (#370 put that file over its 500-line budget); `Scripts/TileMap.gd` keeps `plant_tile` and `structure_tile` wrappers |
| `Scripts/world/object_removals.gd` | Picked flowers and destroyed stones on the map; `world.object_changes` entries with `removed` | new (#198) |
| `Scripts/world/start_castle.gd` | Find the spot for a player's starting castle next to the spawn and place it, including a joining peer's castle outside the shared spawn | new (#271, #278) |
| `Scripts/mechanics/conquest/tower_capture.gd` | Flag towers change hands: who stands by each flag, capture progress, the progress bars | new (#274) |
| `Scripts/mechanics/conquest/cities.gd` | Closed wall loop around a flag tower → city; boundary tint; minimap walls; host decides in multiplayer | new (#277, #498) |
| `Scripts/mechanics/conquest/land_score.gd` | Interior city cells inside an owned flag's range; host sets the Points total; range ring on a tapped flag | new (#279) |
| `Scripts/mechanics/interactables/interactable_type.gd` | One choppable type (resource) | already home |
| `Scripts/mechanics/interactables/interactable_catalog.gd` | Every choppable type, tile lookup | already home |
| `Scripts/tile_catalog.gd` | Tile names to atlas coords | stays (shared data table) |
| `Scripts/BiomeCatalog.gd` | Biome ids and per-biome tables | stays (shared catalogue) |
| `Scripts/MapGenParams.gd` | Map generation parameters resource | stays (shared) |
| `Scripts/map_gen.gd` | Autoload: active params, save/load hooks | stays (autoload) |
| `Scripts/map_save.gd` | Versioned save files (gzip of JSON) | stays |
| `Scripts/world_save_preview.gd` | Cached terrain thumbnails for the saved-worlds list | stays |
| `Scripts/world_save.gd` | One saved world in memory | stays |
| `Scripts/player_save.gd` | Player section of a world save: position, health, wood, score, charted ground | new (#197) |
| `Scripts/player.gd` | Player movement, sword, animation | stays |
| `Scripts/mechanics/run/run_control.gd` | Run button: hold or tap to walk faster | new (#449) |
| `Scripts/player_health.gd` | Health, regen, death, respawn (server owned) | stays |
| `Scripts/attack_aim.gd` | Attack aim by mouse or drag | stays |
| `Scripts/aim_cone_style.gd` | Aim cone look (resource) | stays |
| `Scripts/map_zoom.gd` | Camera pinch, wheel and key zoom | stays |
| `Scripts/inventory.gd` | Gathered resources: add and spend | stays |
| `Scripts/mob.gd` | One mob's behaviour and sync | stays |
| `Scripts/mob_spawner.gd` | Server mob placement | stays |
| `Scripts/mob_catalog.gd` | Mob types and sheet layout | stays (shared catalogue) |
| `Scripts/points.gd` | Point totals (server owned) | stays |
| `Scripts/discovery_points.gd` | First-visit discovery points | stays |
| `Scripts/explored_map.gd` | Explored cells per chunk | stays |
| `Scripts/minimap_panel.gd` | In-play explored map panel; starts closed and sits left of the arc (#450, #480) | stays |
| `Scripts/round_hud_style.gd` | Circle style, selected ring and tap target for the HUD buttons | stays (#450, #480) |
| `Scripts/hud_tool_row.gd` | Places the top-right arc, keeps the minimap left of it, and puts Run beside attack | stays (#450, #480) |
| `Scripts/map_wood_button.gd` | Wood header button shared by the panel and the parchment | stays |
| `Scripts/parchment_map.gd` | Full-screen parchment of explored ground | stays |
| `Scripts/hearts_hud.gd` | Hearts row | stays |
| `Scripts/score_hud.gd` | Point total label | stays |
| `Scripts/scoreboard_toggle.gd` | Scoreboard open button beside the counter (#509) | stays |
| `Scripts/scoreboard_panel.gd` | All players' totals, highest first (#509) | stays |
| `Scripts/resource_hud.gd` | Wood count | stays |
| `Scripts/MainMenu.gd` | Main menu | stays |
| `Scripts/MapAdminPanel.gd` | Map Settings panel | stays |
| `Scripts/number_pad.gd` | Touch keys for number fields | stays |
| `Scripts/ingame_menu.gd` | In-game menu, Save, Customize HUD | stays |
| `Scripts/hud_layout.gd` | Per-device touch HUD positions in user settings | stays (#492) |
| `Scripts/hud_layout_edit.gd` | Customize HUD edit overlay | stays (#492) |
| `Scripts/hud_layout_visual.gd` | HUD control visual rects for edit overlap | stays (#492) |
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
| Its verify recipe | `.cursor/skills/verify-flagoria/features/<feature>.md`, plus its line in `features/README.md` (#291) |
| Its live drive, when a player can reach it | `.cursor/skills/verify-flagoria/drives/<feature>.gd` (#291) |
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
