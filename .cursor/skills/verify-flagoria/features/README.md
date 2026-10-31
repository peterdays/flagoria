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
- Two-peer flows (dedicated server, mobs, health sync) are scripted headless; a full two-GUI Host/Join is still manual — see placeholders below.

## Features

- [Headless verify](./headless-verify.md) — `tools/verify.sh` load, parse, and tests.
- [Map characterization](./map-characterization.md) — pinned map-output / golden atlas check.
- [Map Settings panel](./map-settings-panel.md) — in-game admin parameters before Host.
- [Two-player Host/Join](./two-player-host-join.md) — multiplayer boot (headless peers scripted; GUI checklist manual).
- [Dedicated server](./dedicated-server.md) — `-- --server` headless host and a client joining it.
- [Player health](./player-health.md) — hearts, HUD, regen, death, respawn, health sync.
- [Sword combat](./sword-combat.md) — PvP swing, mid-swing hitbox.
- [Mobs](./mobs.md) — seeded placement, wander, chase, contact damage, sword hits, sync.
- [Player spawn](./player-spawn.md) — spawn on reachable land.
- [Tileset and collision](./tileset-and-collision.md) — tile catalog, water and forest walls.
- [Biomes](./biomes.md) — biome terrain, plants, structures, `render_biomes` coverage gate.
- [Map save files](./map-save.md) — versioned save/load of map inputs.
- [Map zoom](./map-zoom.md) — local pinch, wheel and Ctrl +/- zoom.
- [Audio](./audio.md) — buses, music, combat SFX, footsteps, `audio_check` gate.
- [Main menu](./main-menu.md) — menu theme, Host/Join, volume sliders.
- [Hero sprites](./hero-sprites.md) — layered hero sheet generator (manual check).
- [App icon](./app-icon.md) — icon generator and wiring (manual check).

## Placeholders (not verified here yet)

- **#45 automated two-player smoke** — partly covered: `test_dedicated_server_join` and the `*_two_players` mob tests start a second headless Godot as a server and join it. Still missing: a scripted Host/Join through the menu between two GUI instances.
- **#48 CLI map renders** — partly covered: `tools/render_biomes.gd` renders a wide biome map to `artifacts/out/biomes` (see [Biomes](./biomes.md)). Still missing: a general map render for golden image diffs.
