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

`MapGenParams.biome_frequency` defaults to 0.003, so new worlds have
biomes. The tool uses the same 0.003 unless `--freq` is given. Setting
Biome frequency to 0 in Map Settings turns biomes off. Map saves written
before biomes existed have no `biome_frequency` and load with biomes off,
so they regenerate unchanged.

## Output

- `<out>_seed_<seed>.png`: biome map on the left, terrain in the middle
  (water, sand, swamp, grass, hills), plants next to it (trees dark green,
  pines cyan, bushes amber, flowers pink, stones slate grey, bare land light grey), legend swatches at the
  far right in the order OCEANIC, TEMPERATE, CONTINENTAL, ARCHIPELAGO_DENSE.
  Below them, one 256-tile close-up per biome at 1 tile per pixel, in the same
  order, centred where that biome has the most land, with plants drawn over
  the terrain; cells of other biomes are dimmed. At
  the wide panel's 8 tiles per pixel islands are only a few pixels across, so
  the close-ups are where per-biome terrain is visible.
- `<out>_seed_<seed>_legend.txt`: seed, settings, colors, coverage, each
  biome's land mix (share of its land samples that are sand, swamp, grass)
  and plant mix (share of its land samples with a tree, pine, bush, flower
  or stones), plus
  each biome's tree + pine + bush count on its wide land samples and on its
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

### Pines

With biomes on, `TileMap.plant_tile` also grows small pines
(`TileCatalog.PINE`, blocking like trees) on dry high ground: altitude above
`pine_min_alt`, moisture at or below 0 and above `pine_min_moist`. Broadleaf
trees need moisture above 0, so pines fill land that was bare before. The
moisture floor never goes below the biome's swamp threshold, so pines never
grow on swamp. A cell gets a pine when its plant chance is above
`pine_min_chance` plus the biome's `pine_chance`:

| Biome             | Pines (`pine_chance`) | Share of land (seeds 11, 42, 99) |
|-------------------|-----------------------|----------------------------------|
| OCEANIC           | +0.3 (a few)          | about 0-0.1 %                    |
| TEMPERATE         | 2.0 (none)            | 0 %                              |
| CONTINENTAL       | -0.25 (conifer stands)| about 10 %                       |
| ARCHIPELAGO_DENSE | 2.0 (none)            | 0 %                              |

TEMPERATE and ARCHIPELAGO_DENSE dry land is swamp, so they get none, and
TEMPERATE with biomes on still matches the map with biomes off. Saves from
before pines load with `pine_min_chance = 2.0` (no pines), so they regenerate
unchanged.

### Bushy trees

With biomes on, a cell that would grow a broadleaf tree grows the bushy
variant (`TileCatalog.TREE_BUSHY`, same collision as TREE, chopped as the
tree type for 3 wood) when its moisture is above `bushy_tree_min_moist`
(Map Settings, default 0.3) plus the biome's `bushy_moist`. Oaks keep the
moderately moist land and bushy trees take the wettest tree land:

| Biome             | `bushy_moist`        | Share of land (seeds 11, 42, 99) |
|-------------------|----------------------|----------------------------------|
| OCEANIC           | 0.0                  | 0 % (its land grows almost no trees) |
| TEMPERATE         | 2.0 (none)           | 0 %                              |
| CONTINENTAL       | +0.15 (wettest only) | about 1.0-1.2 %                  |
| ARCHIPELAGO_DENSE | -0.2 (most trees)    | about 0.2-0.9 %                  |

TEMPERATE with biomes on still matches the map with biomes off. Saves from
before bushy trees load with `bushy_tree_min_moist = 2.0` (none), so they
regenerate unchanged.

## Per-biome structures

With biomes on, `BiomeCatalog.STRUCTURES` scatters walkable stones
(`TileCatalog.STONES`) on `GROUND_DECOR_LAYER`, like flowers. A walkable land
cell gets stones when it has no plant (pines win over stones; beaches included, since they get no
plants with biomes on) and its items chance is above the biome's
`stone_chance`. Values above 1 mean no stones:

| Biome             | Stones (`stone_chance`) | Share of land (seeds 11, 42, 99) |
|-------------------|-------------------------|----------------------------------|
| OCEANIC           | 0.3 (rocky cays)        | about 7.6-10 %                   |
| TEMPERATE         | 2.0 (none)              | 0 %                              |
| CONTINENTAL       | 0.35 (dry, stony)       | about 1.6-1.7 %                  |
| ARCHIPELAGO_DENSE | 2.0 (none)              | 0 %                              |

TEMPERATE has none, so with biomes on it still matches the map with biomes
off. `TileMap.structure_tile` picks the stones; generation and the render
tool share it. With `biome_frequency = 0` there are no stones and the map
is unchanged.

## Biome PR renders

A PR that changes biomes attaches this render for at least three seeds,
with the coverage lines, so every biome is visible. Close-up renders of a
small area can come in addition, never instead.
