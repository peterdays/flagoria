# Biomes

The world is split into biomes (oceanic, temperate, continental, dense archipelago; ids in `Scripts/BiomeCatalog.gd`) that change island density, terrain, plants and structures.

## Sub-features

- `biome-map` per-biome island density (`Scripts/BiomeCatalog.gd`).
- `biome-terrain` beaches, swamps and flowers per biome.
- `biome-plants` tree and bush density per biome.
- `biome-structures` stones on oceanic and continental land.
- `biome-render` wide render with coverage % per biome (`tools/render_biomes.gd`, see `docs/biomes.md`).

## How to get to it (user POV)

- Map Settings: raise the biome frequency above 0, then Host and explore.
- Headless: `godot --headless --path . --script res://tools/render_biomes.gd -- --seed=42` writes PNGs under `artifacts/out/`.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_biomes`, `-- test_biome_terrain`, `-- test_biome_plants`, `-- test_biome_structures`, `-- test_biome_seed_panel_round_trip` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- verify.sh runs a seed-42 render and requires `BIOME_COVERAGE_OK` (every biome present and growing plants).
- For visual review, render seeds 11, 42 and 99 wide and report each biome's coverage %.
