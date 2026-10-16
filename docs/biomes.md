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

- `<out>_seed_<seed>.png`: biome map on the left, terrain on the right
  (water, sand, grass, hills), legend swatches at the far right in the
  order OCEANIC, TEMPERATE, CONTINENTAL, ARCHIPELAGO_DENSE.
- `<out>_seed_<seed>_legend.txt`: seed, settings, colors, and coverage.
- stdout: the same legend with each biome's coverage %.

The tool exits 1 and prints `FAIL: biomes with 0% coverage` when any biome
is missing from the area. Widen `--size` or raise `--freq` in that case.
`tools/verify.sh` runs it on one seed, so a change that removes a biome
fails verification.

## Biome PR renders

A PR that changes biomes attaches this render for at least three seeds,
with the coverage lines, so every biome is visible. Close-up renders of a
small area can come in addition, never instead.
