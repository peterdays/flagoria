# Flagoria verification map

Maintained recipes for proving user-facing and CI-facing behavior. Read this index, then the matching feature file.

## Baseline preconditions

- Working directory is the Flagoria repo root (`project.godot` present).
- Godot is the version in `project.godot` (currently **4.7.x**, check with `$GODOT --version`). `GODOT` points at the editor binary; when it is unset, `doctor.sh`, `drive-verify.sh` and `tools/verify.sh` use `godot` on `PATH`.
- Run `./.cursor/skills/verify-flagoria/bin/doctor.sh` and require exit `0`.
- Prefer disposable evidence under `.cursor/skills/verify-flagoria/artifacts/`.
- Never drive a long-lived game instance that was not started for this verification run.

## Driving conventions

- Automated proof goes through `tools/verify.sh` via `bin/drive-verify.sh`.
- Visual proof uses `xvfb-run` and `--rendering-driver opengl3` when a display is required.
- Record skips with the unmet precondition; do not report a skipped path as verified through a different path.
- Every feature file, and every new test or drive added to one, states its expected time cost (for example `~5 s in tools/verify.sh`, `~2 min stress`). Time is weighed, not capped: a costly proof is fine when it is worth it. CI's "Job times" summary per workflow run shows the actual figures against recent main runs.

## Proof and skip reporting

- Keep verify logs and screenshots in `artifacts/`; cleanup must not delete them.
- UI proof for Map Settings includes a PNG with the panel title visible.
- Two-peer flows (dedicated server, mobs, health sync, cuts, points) are scripted headless; menu Host/Join has a two-launch drive; the two-GUI play checklist is still manual. See placeholders below.
- After adding or renaming a test or feature file, run `./.cursor/skills/verify-flagoria/bin/check-map.sh` (no Godot, under 1 s). It fails when a feature file is not indexed here, a cited `test_<name>` does not exist, or a test is cited by no feature file.

## Features

- [Headless verify](./headless-verify.md) — `tools/verify.sh` file budget, load, parse, tests, biome, audio, generator and map render golden checks.
- [Map characterization](./map-characterization.md) — pinned map-output / golden atlas check, `tools/cli.gd` map render and stats.
- [Map Settings panel](./map-settings-panel.md) — map parameters before Host, rows from `@export_range` hints, number pad.
- [Two-player Host/Join](./two-player-host-join.md) — multiplayer boot (headless peers scripted; two-launch menu drive; GUI checklist manual).
- [Dedicated server](./dedicated-server.md) — `-- --server` headless host, `--params` save file, a client joining it.
- [Player health](./player-health.md) — hearts, HUD, regen, death, respawn hold, rejoin, health sync.
- [Combat and aiming](./combat-and-aiming.md) — swing, 30 px reach, mid-swing hitbox, mouse and touch aim, exact-angle swing, cone, cancel; live `combat_hud` drive.
- [Mobs](./mobs.md) — seeded placement, spawn rate, wander, chase, contact damage, sword hits, hidden on ungenerated ground, sounds, sync.
- [Player spawn](./player-spawn.md) — spawn on reachable land, a free spot per player within 64 px, late joiners.
- [Tileset and collision](./tileset-and-collision.md) — tile catalog, water and forest walls.
- [Biomes](./biomes.md) — biome terrain, plants, stones, island and archipelago shaping, biomes on by default, `render_biomes` coverage gate.
- [Map save files](./map-save.md) — versioned world saves (inputs plus cuts), v1 migration, Save from the in-game menu, saved-maps API.
- [Map zoom](./map-zoom.md) — local pinch, wheel and Ctrl +/- zoom.
- [Chopping trees and bushes](./chop-trees-and-bushes.md) — interact-mode chop, tree, pine and bush types, their hit and fall frames, per-type wood and regrow delay, stumps, regrowth (held while a player or mob stands on the stump), wood HUD, type checklist.
- [Chop trees (live drive)](./chop-trees.md) — mode button, tap a tree in reach, two hits, tree hit frames and sounds, stump and wood once.
- [Cut sync (two-player)](./cut-sync.md) — host-decided tree and bush cuts, same stump on every peer, wood to the cutter, late joiners get the exact set.
- [Explored map](./explored-map.md) — minimap panel, cells revealed within 10 cells of the hero.
- [Walls and bridges](./walls-and-bridges.md) — wall solver, plank bridges; live drive verified-unreachable until a build action lands.
- [Audio](./audio.md) — buses, music, combat, UI and mob SFX, footsteps, `audio_check` gate.
- [Main menu](./main-menu.md) — menu theme, Host/Join, volume and mob spawn sliders, letter keyboard.
- [In-game menu and quit prompt](./ingame-menu.md) — menu button, Pause panel (Resume, Save, Main menu), quit confirm.
- [Points](./points.md) — discovery and mob-kill points, host-owned totals, score HUD.
- [Touch controls](./touch-controls.md) — joystick hold, Castle Stone attack button and stick, number pad and letter keyboard (`-` key; `Del` and `-` edit a selected value).
- [Structures (data format)](./structures.md) — `flagoria-structure 1` text files; not placed in game yet.
- [Structure placement](./structure-placement.md) — place a structure file at an anchor cell, refusal reasons, kept on redraw; placed by a host still alone, sent to joining peers; not reachable in game yet.
- [Hero sprites](./hero-sprites.md) — layered hero sheet generator, checked by the generator smoke.
- [App icon](./app-icon.md) — icon generator and wiring, checked by the generator smoke.

## Placeholders (not verified here yet)

- **#45 automated two-player smoke** — partly covered: `test_dedicated_server_join`, `test_two_player_smoke` and the `*_two_players` mob tests start a second headless Godot as a server and join it. The two-launch drives `drives/two_player/two_player_host.gd` and `drives/two_player/two_player_client.gd` click Host and Join (see [Two-player Host/Join](./two-player-host-join.md)). Still missing: running them as a smoke in CI.
- **#48 CLI map renders** — partly covered: `tools/render_biomes.gd` renders a wide biome map (see [Biomes](./biomes.md)), and verify compares the `tools/cli.gd map render --seed 42` text map to `tests/golden/map_render_seed42.txt` (see [Headless verify](./headless-verify.md)). Still missing: golden image (PNG) diffs.
