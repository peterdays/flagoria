# Biome renders

Biome regions are large: at `biome_frequency = 0.003` one region spans a few
hundred tiles. A 256-tile render usually sits inside one biome and says
nothing about the biome mix. `tools/render_biomes.gd` renders a wide area
instead and checks that every biome appears.

## Usage

```sh
godot --headless --path . --script res://tools/render_biomes.gd -- --seed=42
```

Options (all optional):

| Option   | Default                      | Meaning                                     |
|----------|------------------------------|---------------------------------------------|
| `--seed` | `42`                         | Base seed; other seeds derive from it       |
| `--freq` | `0.003`                      | `biome_frequency`; must be above 0          |
| `--size` | `4096`                       | Side of the square area, in tiles           |
| `--step` | `8`                          | Tiles per pixel                             |
| `--out`  | `res://artifacts/out/biomes` | Output prefix (`artifacts/` is git-ignored) |

`MapGenParams.biome_frequency` defaults to 0 (biomes off), so the tool
uses 0.003 unless `--freq` is given.

## Output

- `<out>_seed_<seed>.png`: biome map on the left, terrain in the middle
  (water, sand, swamp, grass, hills), plants next to it (trees dark green,
  bushes amber, flowers pink, stones slate grey, bare land light grey), legend swatches at the
  far right in the order OCEANIC, TEMPERATE, CONTINENTAL, ARCHIPELAGO_DENSE.
  Below them, one 256-tile close-up per biome at 1 tile per pixel, in the same
  order, centred where that biome has the most land, with plants drawn over
  the terrain; cells of other biomes are dimmed. At
  the wide panel's 8 tiles per pixel islands are only a few pixels across, so
  the close-ups are where per-biome terrain is visible.
- `<out>_seed_<seed>_legend.txt`: seed, settings, colors, coverage, each
  biome's land mix (share of its land samples that are sand, swamp, grass)
  and plant mix (share of its land samples with a tree, bush, flower or
  stones), plus
  each biome's tree + bush count on its wide land samples and on its
  close-up land cells.
- stdout: the same legend.

The tool exits 1 and prints `FAIL: biomes with 0% coverage` when any biome
is missing from the area. Widen `--size` or raise `--freq` in that case.
It also exits 1 and prints `FAIL: biomes with land but no trees or bushes`
when a biome's land grows no trees or bushes in either the wide samples or
its full-resolution close-up (for example, an emptied `BiomeCatalog.PLANTS`
row). The close-up is counted because sparse biomes can have only a handful
of plants on the wide grid.
`tools/verify.sh` runs it on one seed, so a change that removes a biome, or
leaves one bare, fails verification.

## Per-biome terrain

With biomes on, `BiomeCatalog.TERRAIN` changes the ground mix per biome
(TEMPERATE is the identity row, i.e. the terrain with biomes off):

| Biome             | Beach (`sand_band`) | Swamp below moisture | Flowers (`flower_chance`) |
|-------------------|---------------------|----------------------|---------------------------|
| OCEANIC           | +0.08 (wide cays)   | -0.25 (rare)         | +0.3 (sparse)             |
| TEMPERATE         | 0                   | 0                    | 0                         |
| CONTINENTAL       | -0.02 (narrow)      | -0.25 (dry, grassy)  | -0.2 (meadows)            |
| ARCHIPELAGO_DENSE | +0.04 (broad)       | +0.2 (wet, swampy)   | 0                         |

`sand_band` is added to `sand_max_alt` and `swamp_special_alt`;
`flower_chance` is added to `flower_min_chance`. With biomes on, sand tiles
get no bushes or flowers, because wider beaches reach into those bands.
With `biome_frequency = 0` none of this applies and the map is unchanged.

## Per-biome plants

With biomes on, `BiomeCatalog.PLANTS` changes tree and bush density per
biome (TEMPERATE is the identity row). Values are added to `tree_min_chance`
and `bush_min_chance`, so higher means fewer plants:

| Biome             | Trees (`tree_chance`) | Bushes (`bush_chance`) |
|-------------------|-----------------------|------------------------|
| OCEANIC           | +0.3 (almost bare)    | +0.2 (sparse)          |
| TEMPERATE         | 0                     | 0                      |
| CONTINENTAL       | -0.25 (forests)       | 0                      |
| ARCHIPELAGO_DENSE | +0.15 (few trees)     | -0.25 (scrub)          |

`TileMap.plant_tile` picks the bush, tree or flower for a cell; generation
and the render tool share it. With `biome_frequency = 0` none of this
applies and the plants are unchanged.

## Per-biome structures

With biomes on, `BiomeCatalog.STRUCTURES` scatters walkable stones
(`TileCatalog.STONES`) on `GROUND_DECOR_LAYER`, like flowers. A walkable land
cell gets stones when it has no plant (beaches included, since they get no
plants with biomes on) and its items chance is above the biome's
`stone_chance`. Values above 1 mean no stones:

| Biome             | Stones (`stone_chance`) | Share of land (seeds 11, 42, 99) |
|-------------------|-------------------------|----------------------------------|
| OCEANIC           | 0.3 (rocky cays)        | about 8-10 %                     |
| TEMPERATE         | 2.0 (none)              | 0 %                              |
| CONTINENTAL       | 0.35 (dry, stony)       | about 3 %                        |
| ARCHIPELAGO_DENSE | 2.0 (none)              | 0 %                              |

TEMPERATE has none, so with biomes on it still matches the map with biomes
off. `TileMap.structure_tile` picks the stones; generation and the render
tool share it. With `biome_frequency = 0` there are no stones and the map
is unchanged.

## Biome PR renders

A PR that changes biomes attaches this render for at least three seeds,
with the coverage lines, so every biome is visible. Close-up renders of a
small area can come in addition, never instead.
