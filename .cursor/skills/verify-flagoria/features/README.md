# Flagoria verification map

Maintained recipes for proving user-facing and CI-facing behavior. Read this index only to pick the matching feature file, then open that file and stay on the paths, tests, and `Drive:` it names. Do not treat this index as a reason to open every feature.

## Baseline preconditions

- Working directory is the Flagoria repo root (`project.godot` present).
- Godot is the version in `project.godot` (currently **4.7.x**, check with `$GODOT --version`). `GODOT` points at the editor binary; when it is unset, `doctor.sh`, `drive-verify.sh` and `tools/verify.sh` use `godot` on `PATH`. If doctor reports Godot missing, run `./tools/ensure_godot.sh` once, then doctor again. Never download Godot with ad-hoc shells mid-task.
- Run `./.cursor/skills/verify-flagoria/bin/doctor.sh` and require exit `0`.
- Agent tasks use `brief.template.md` and `python3 tools/agent_budget.py` (`check-brief` / `check-receipt`). PR bodies keep `Verify: once` and `Drive: …` lines.
- Prefer disposable evidence under `.cursor/skills/verify-flagoria/artifacts/`.
- Never drive a long-lived game instance that was not started for this verification run.

## Driving conventions

- Every feature file starts with a `Drive:` line right under its title: `Drive: drives/<name>.gd` when an automated drive covers it, or `Drive: not player-facing` otherwise. Drives call `snapshot("<screen>")` for each promised screen.
- Automated proof goes through `tools/verify.sh` via `bin/drive-verify.sh`.
- Visual proof uses `xvfb-run` and `--rendering-driver opengl3` when a display is required.
- Record skips with the unmet precondition; do not report a skipped path as verified through a different path.
- Every feature file, and every new test or drive added to one, states its expected time cost (for example `~5 s in tools/verify.sh`, `~2 min stress`). Time is weighed, not capped: a costly proof is fine when it is worth it. CI's "Job times" summary per workflow run shows the actual figures against recent main runs.

## Proof and skip reporting

- Keep verify logs and screenshots in `artifacts/`; cleanup must not delete them.
- UI proof for Map Settings includes a PNG with the panel title visible.
- Two-peer flows (dedicated server, mobs, health sync, cuts, points) are scripted headless; menu Host/Join has a two-launch drive; the two-GUI play checklist is still manual. See placeholders below.
- After adding or renaming a test or feature file, run `./.cursor/skills/verify-flagoria/bin/check-map.sh` (no Godot, under 1 s). It fails when a feature file is not indexed here, a cited `test_<name>` does not exist, a test is cited by no feature file, or a feature file lacks a `Drive:` line (`Drive: drives/<name>.gd` pointing at an existing drive that calls `snapshot("…")`, or `Drive: not player-facing`). On a gameplay pull request, `check-map.sh --gameplay --changed-files <paths>` also fails when a changed or added feature file lacks that line. Time cost: under 1 s.

## Features

- [Headless verify](./headless-verify.md) — `tools/verify.sh` file budget, load, parse, tests, biome, audio, generator and map render golden checks.
- [Map characterization](./map-characterization.md) — pinned map-output / golden atlas check, `tools/cli.gd` map render and stats.
- [Map Settings panel](./map-settings-panel.md) — map parameters before Host, rows from `@export_range` hints, number pad, five action buttons in two pairs plus Host (#217), Random specs (#335).
- [Two-player Host/Join](./two-player-host-join.md) — multiplayer boot (headless peers scripted; two-launch menu drive; GUI checklist manual).
- [Join failure returns to the main menu](./join-fail.md) — failed Join shows `Could not join …` on the main menu; host quit reloads to the menu (#348).
- [Join an address with an optional port](./join-port.md) — hostname or IPv4, optional `:port`, default UDP 9786; bad addresses rejected on the menu (#434).
- [Dedicated server](./dedicated-server.md) — `-- --server` headless host, `--params` generation params only, SIGTERM quit, a client joining it, optional Docker image.
- [Dedicated cut-and-hit round](./dedicated-play-round.md) — two Join clients on a dedicated host with no player `1`: one plant cut, one mob killed (#436). Not the listen Host/Join pair.
- [Player health](./player-health.md) — hearts, HUD, regen, death, respawn hold, rejoin, health sync.
- [Combat and aiming](./combat-and-aiming.md) — swing, 30 px reach, mid-swing hitbox, mouse and touch aim, exact-angle swing, cone, cancel, wall line-of-sight; live `combat_hud` drive.
- [Mobs](./mobs.md) — seeded placement, spawn rate, wander, chase, contact damage, sword hits, hidden on ungenerated ground, sounds, sync.
- [Player spawn](./player-spawn.md) — spawn on reachable land, a free spot per player within 64 px, late joiners.
- [Hero in front of walls](./hero-wall-draw.md) — the hero draws over a wall until about two thirds of the body is on the wall.
- [Tileset and collision](./tileset-and-collision.md) — tile catalog, water and forest walls.
- [Biomes](./biomes.md) — biome terrain, plants, stones, island and archipelago shaping, biomes on by default, `render_biomes` coverage gate.
- [Map save files](./map-save.md) — versioned world saves (inputs plus cuts and plank bridges), v1 migration, Save from the in-game menu, saved-maps API.
- [Map zoom](./map-zoom.md) — local pinch, wheel and Ctrl +/- zoom.
- [Chopping trees and bushes](./chop-trees-and-bushes.md) — interact-mode chop, tree, pine and bush types, their hit and fall frames, per-type wood and regrow delay, stumps, regrowth (held while a player or mob stands on the stump, one mob-cell set per pass), wood HUD, type checklist.
- [Chop trees (live drive)](./chop-trees.md) — mode button, tap a tree in reach, two hits, tree hit frames and sounds, stump and wood once.
- [Cut sync (two-player)](./cut-sync.md) — host-decided tree and bush cuts, same stump on every peer, wood to the cutter, late joiners get the exact set, sent in parts of at most 500 cuts.
- [Regrowth sync messages](./regrow-sync.md) — one `apply_regrow_cells` per regrowth tick, applied only when the host (peer 1) sent it.
- [Tree sprouts](./tree-sprouts.md) — trees sprout on free cells where a biome is below its target tree share, host-decided, one `apply_sprout_cells` per pass, kept in saves and join lists.
- [Dead player cuts nothing](./dead-player-cut.md) — interact-mode taps and drags ignored while the hero is dead, host refuses `request_cut` from a dead peer.
- [Cut request limit](./cut-rate-limit.md) — host-side per-peer bucket on `request_cut` (162 at once, 162.5 a second), drops a flood with no reply, never limits a real drag or walk.
- [Explored map](./explored-map.md) — wood minimap (collapse, reopen, maximize) and the parchment full map; cells revealed within 10 cells of the hero.
- [Build costs](./build-costs.md) — wood per plank (1), wall block (2), tower (10), starting castle (0), half back on removal, `Inventory.spend`, `BuildCosts.buy` refuses with too little wood or while multiplayer is on; live path is the build picker.
- [Construction placement](./construction-placement.md) — shared `can_place` / `cost` / `place` for buildables; plank, wooden tower and wall block (through `BuildCosts.buy`); live path is the build picker.
- [Build placement](./build-placement.md)
- [Build sync](./build-sync.md) — plank bridges decided by the host and synced to every peer; late joiner gets the list (#297). — interact-mode Cut/Plank/Tower/Wall picker, H/V-snapped plank and wall drag, tower footprint preview, green/red preview and wood cost; places through ConstructionPlacer (#225 / #273 / #276).
- [Build tower](./build-tower.md) — wooden palisade tower for 10 wood, land only, builder-owned flag, host-alone (#273).
- [Free-form walls](./free-form-walls.md) — connected palisade chain via Wall tip, 2 wood per block, host-alone (#276).
- [Wall and tower junctions](./wall-junctions.md) — mask pieces, collar overlays on stone, tower ring with the team flag, far corner flips when a loop closes.
- [Walls and bridges](./walls-and-bridges.md) — wall solver, plank bridges (live via build picker); free-form walls via [Free-form walls](./free-form-walls.md).
- [Bridge joins](./bridge-joins.md) — adjoining plank placements share plain interior planks; rope and tips stay on shores and open ends (#416).
- [Audio](./audio.md) — buses, music, combat, UI and mob SFX, footsteps, `audio_check` gate.
- [Main menu](./main-menu.md) — menu theme, Host/Join, volume and mob spawn sliders, letter keyboard.
- [Saved worlds](./saved-worlds.md) — main-menu list of every save, load, a new world in its own file, delete with a confirm.
- [In-game menu and quit prompt](./ingame-menu.md) — menu button, Pause panel (Resume, Save, Main menu), quit confirm.
- [Interact mode](./interact-mode.md) — mode button; Space still swings the sword in interact (chop) mode; aimed attacks stay combat-only (#351).
- [Points](./points.md) — discovery and mob-kill points, host-owned totals, score HUD.
- [Touch controls](./touch-controls.md) — joystick hold, Castle Stone attack button and stick, number pad and letter keyboard (`-` key; `Del` and `-` edit a selected value).
- [Structures (data format)](./structures.md) — `flagoria-structure 1` text files.
- [Structure placement](./structure-placement.md) — place a structure file at an anchor cell, refusal reasons, kept on redraw, a placed stump does not regrow; placed by a host still alone, sent to joining peers.
- [Starting castle](./start-castle.md) — each player's castle next to the spawn, player starts outside the gate; placed by the host while alone, sent to joining peers.
- [Cities](./cities.md) — closed wall loop around a flag tower makes a city; tint + minimap; capture transfers; host alone (#277).
- [Tower capture](./tower-capture.md) — flag towers taken by a lone other side or mobs standing by the flag for 5 s, defenders pause, empty drains, contested freezes; host alone only.
- [Flags held points](./flags-held-points.md) — 1 point per owned flag tower every 5 s (`flags_held`); host alone (#275).
- [Hero sprites](./hero-sprites.md) — layered hero sheet generator, checked by the generator smoke.
- [App icon](./app-icon.md) — icon generator and wiring, checked by the generator smoke.

## Placeholders (not verified here yet)

- **#45 automated two-player smoke** — partly covered: `test_dedicated_server_join`, `test_two_player_smoke` and the `*_two_players` mob tests start a second headless Godot as a server and join it. The two-launch drives `drives/two_player/two_player_host.gd` and `drives/two_player/two_player_client.gd` click Host and Join (see [Two-player Host/Join](./two-player-host-join.md)). Still missing: running them as a smoke in CI.
- **#48 CLI map renders** — partly covered: `tools/render_biomes.gd` renders a wide biome map (see [Biomes](./biomes.md)), and verify compares the `tools/cli.gd map render --seed 42` text map to `tests/golden/map_render_seed42.txt` (see [Headless verify](./headless-verify.md)). Still missing: golden image (PNG) diffs.
