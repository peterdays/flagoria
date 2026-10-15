# Tile inventory

This page lists every Solaria tile the game uses today and a proposed CC0 replacement from the Ninja Adventure pack. It is the input for the tileset swap tracked in #97.

All tiles are 16×16 px. Atlas coordinates are `(column, row)` in 16 px cells. "Size" is the tile's `size_in_atlas` in cells.

## Where Solaria is referenced

| File | Use |
|---|---|
| `flagoria_main.tscn` | `TileSet` with one `TileSetAtlasSource` (source id `0`) over `art/Sprites/Solaria Demo Pack Update 03/16x16/Tilesets/Solaria Demo Update 01.png` (448×240 px, 28×15 cells). Holds the collision polygons used below. |
| `tilemap_dynamic.tscn` | A copy of the same `TileSet`. No scene or script loads this file. |
| `Scripts/TileMap.gd` | Places tiles with `set_cell(layer, cell, 0, Vector2i(x, y))` in `set_tile_type_z0`, `get_random_ground_vec` and `set_tile_type_z1`. |
| `Player/character_body_2d.tscn` | Player sprite sheet `art/Sprites/Solaria Demo Pack Update 03/16x16/Sprites/Hero 01.png` (`hframes = 8`, `vframes = 16`). |
| `tests/run_tests.gd` | Pinned characterization data and the flower layer test compare against the raw coordinates below. |

`Scripts/MapGenParams.gd` mentions the flower coordinate in a comment only.

## Map tiles (source 0)

| Name | Purpose | Layer | Solaria coords | Size | Collision | Proposed Ninja Adventure replacement |
|---|---|---|---|---|---|---|
| WATER | Sea, `alt <= water_max_alt` | 0 | (5, 6) | 1×1 | Full square (blocks movement) | `Backgrounds/Tilesets/TilesetWater.png` (1, 1), plain water centre |
| SAND | Beach, between water and land | 0 | (5, 4) | 1×1 | None | `Backgrounds/Tilesets/TilesetFloor.png` (1, 1), plain sand centre |
| SWAMP | Low land with `moist < 0` | 0 | (14, 7) | 1×1 | None | `Backgrounds/Tilesets/TilesetFloor.png` (12, 15), dark mud centre |
| SWAMP_SPECIAL | Swamp below `swamp_special_alt` with `chance < 0` | 0 | (27, 7) | 1×1 | None | Gap, see below |
| GRASS_A | Land, `chance < ground_chance_a` | 0 | (5, 0) | 1×1 | None | `Backgrounds/Tilesets/TilesetFloor.png` (1, 12) |
| GRASS_B | Land, `chance < ground_chance_b` | 0 | (5, 1) | 1×1 | None | `Backgrounds/Tilesets/TilesetFloor.png` (2, 12) |
| GRASS_C | Land, `chance < ground_chance_c` | 0 | (6, 0) | 1×1 | None | `Backgrounds/Tilesets/TilesetFloor.png` (3, 12) |
| GRASS_D | Land, otherwise | 0 | (6, 1) | 1×1 | None | `Backgrounds/Tilesets/TilesetFloorDetail.png`, a grass tuft over grass (needs a second layer or a baked tile) |
| BUSH | Bush on moist land in the bush altitude band | 1 | (7, 3) | 1×2 | Polygon at the base | `Backgrounds/Tilesets/TilesetNature.png` (1, 10), 1×1 bush. Size changes from 1×2 to 1×1 |
| TREE | Tree on moist land above `tree_min_alt` | 1 | (7, 0) | 3×3 | Polygon at the trunk | `Backgrounds/Tilesets/TilesetNature.png` (6, 8), 2×2 round tree. Size changes from 3×3 to 2×2 |
| FLOWER | Walkable flower in the flower altitude band | 2 (`GROUND_DECOR_LAYER`) | (9, 3) | 1×1 | None | `Backgrounds/Tilesets/TilesetNature.png` (3, 11), red flower. (0, 11) and (6, 11) are other variants |

Coordinates for the Ninja Adventure column were read off the sheets by eye. Confirm each one against a rendered map before the swap lands.

## Sprites

| Name | Purpose | Solaria file | Proposed Ninja Adventure replacement |
|---|---|---|---|
| Player | Hero sprite sheet, 8×16 frames | `Sprites/Hero 01.png` | `Actor/Characters/...` sheets. The frame layout differs, so the player animations need remapping. Out of scope for the tile swap. |

## Useful extras in Ninja Adventure

- Tree stump (4, 8) and log (5, 8) in `TilesetNature.png`, for tree chopping (#93).
- Snow, blossom and autumn tree variants in `TilesetNature.png`, for biomes.

## Gaps

- **SWAMP_SPECIAL (27, 7):** the Solaria cell is an edge piece rather than a fill tile. Ninja Adventure has no direct match. Either reuse the mud fill or pick a darker mud variant from `TilesetFloor.png`.
- **Four grass variants:** Ninja Adventure has fewer plain grass fills than Solaria. GRASS_D likely needs a detail overlay or must reuse another fill. The ground variation will look different.
- **Shorelines:** today water, sand and grass meet with hard square edges. Ninja Adventure ships autotile edge pieces in `TilesetWater.png` and `TilesetFloor.png`. Using them needs a terrain set, which is separate work (#101).
- **Multi-cell sizes:** BUSH (1×2 to 1×1) and TREE (3×3 to 2×2) change footprint. Collision polygons must be redrawn, and the pinned map test will need new expected values when the art changes.
- **`TilesetFloor.png` height:** the sheet is 417 px tall, not a multiple of 16. The atlas source needs a 26-row region so the last partial row is ignored.
- **Player sprite:** no drop-in replacement with the same frame layout.
- **Style:** Ninja Adventure uses a different palette. A recolour pass may be needed for a consistent look.
