# Biomes

Drive: not player-facing

The world is split into biomes (oceanic, temperate, continental, dense archipelago; ids in `Scripts/BiomeCatalog.gd`) that change island density, terrain, plants and structures.

## Sub-features

- `biome-map` per-biome island density (`Scripts/BiomeCatalog.gd`).
- `biome-terrain` beaches, swamps and flowers per biome.
- `biome-plants` tree and bush density per biome, including swamp scrub (bushes on dense-archipelago swamp; a save from before it loads with none).
- `biome-structures` stones on oceanic and continental land.
- `world-shape` Map Settings shaping params (`tests/world/test_island_shape.gd`): `island_radius` raises the origin and sinks cells past 1.5 radii; `archipelago_spacing` raises a jittered centre per grid square and sinks the sea between; `archipelago_island_count` (with or without `archipelago_world_extent`) keeps N seed-stable squares, always the spawn square. 0 leaves altitude alone.
- `biome-default-on` a new world has biomes on; a save written before biomes existed (no `biome_frequency`) loads with them off and regenerates unchanged (#178).
- `biome-mix` Map Settings `biome_edge` (default 0.2) sets the noise cut-offs between biomes, so each covers about a fifth to a quarter of the world; `-- test_new_world_biomes_on` fails if any biome covers under 10 % of a 4096-tile area. A save written before `biome_edge` loads with 0.5, the old cut-off.
- `biome-render` wide render with coverage % per biome (`tools/render_biomes.gd`, see `docs/biomes.md`).

## How to get to it (user POV)

- Host a new world and explore; Map Settings sets the biome frequency (0 turns biomes off) and the island shape params.
- Headless: `godot --headless --path . --script res://tools/render_biomes.gd -- --seed=42` writes PNGs under `artifacts/out/`.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the island shape tests and `-- test_new_world_biomes_on` ~1.9 s alone with `--only=`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_biomes`, `-- test_biome_terrain`, `-- test_biome_plants`, `-- test_biome_structures`, `-- test_biome_seed_panel_round_trip`, `-- test_new_world_biomes_on`, `-- test_island_falloff`, `-- test_archipelago`, `-- test_archipelago_count`, `-- test_archipelago_count_land_masses` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- verify.sh runs a seed-42 render and requires `BIOME_COVERAGE_OK` (every biome present and growing plants).
- For visual review, render seeds 11, 42 and 99 wide and report each biome's coverage %.
