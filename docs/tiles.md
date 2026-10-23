# Tiles

The map uses the in-house Flagoria tileset v3.1 (Solaria replacement, #97 / #100). All tiles are 16×16 px. Atlas coordinates are `(column, row)` in 16 px cells.

- Atlas: `art/flagoria/flagoria_tiles_v3.png`, 448×240 px, 28×15 cells.
- TileSet: `art/flagoria/flagoria_tiles_v3.tres`, one `TileSetAtlasSource` (source id `0`) with 179 named cells, one physics layer, and terrain set `0` (Match Corners and Sides) with terrain `0` "Island".
- Names: `Scripts/tile_catalog.gd` (`TileCatalog`) is the only place that maps names to source id and atlas coords. Credits: `art/flagoria/CREDITS.md`.

## Where tiles are referenced

| File | Use |
|---|---|
| `flagoria_main.tscn` | `World/worldMap` uses `art/flagoria/flagoria_tiles_v3.tres` as its `tile_set`. |
| `tilemap_dynamic.tscn` | Uses the same TileSet. No scene or script loads this file. Its embedded script places tiles through `TileCatalog`. |
| `Scripts/TileMap.gd` | Places tiles in `set_tile_type_z0`, `get_random_ground_vec` and `set_tile_type_z1` by name, e.g. `set_cell(layer, cell, TileCatalog.SOURCE_ID, TileCatalog.WATER)`. |
| `Scripts/footsteps.gd` | Maps the cell under the player to a footstep surface through `TileCatalog.TILES`. |
| `tools/audio_check.gd`, `tools/render_biomes.gd` | Use `TileCatalog` names. |
| `tests/run_tests.gd` | Pinned characterization data and a few fixtures compare against the raw coordinates of the map fill tiles below, on purpose: a cell move must fail them. |

## Map fill tiles (placed by the generator)

The first 11 names kept their cells when the Solaria atlas was replaced. STONES (added with the per-biome structures) moved from the empty Solaria cell (6, 2) to the small-rocks cell (0, 7), which is also `ROCK_FLOAT_S`.

| Name | Purpose | Layer | Cell | Size | Collision |
|---|---|---|---|---|---|
| WATER | Sea, `alt <= water_max_alt` | 0 | (5, 6) | 1×1 | Full square (blocks movement) |
| SAND | Beach, between water and land | 0 | (5, 4) | 1×1 | None |
| SWAMP | Low land with `moist < 0` | 0 | (14, 7) | 1×1 | None |
| SWAMP_SPECIAL | Swamp below `swamp_special_alt` with `chance < 0` | 0 | (27, 7) | 1×1 | None |
| GRASS_A | Land, `chance < ground_chance_a` | 0 | (5, 0) | 1×1 | None |
| GRASS_B | Land, `chance < ground_chance_b` | 0 | (5, 1) | 1×1 | None |
| GRASS_C | Land, `chance < ground_chance_c` | 0 | (6, 0) | 1×1 | None |
| GRASS_D | Land, otherwise | 0 | (6, 1) | 1×1 | None |
| BUSH | Bush on moist land in the bush altitude band | 1 | (7, 3) | 1×1 | 12×11 polygon over the whole bush |
| TREE | Tree on moist land above `tree_min_alt` | 1 | (7, 0) | 1×1 | 14×11 polygon over the lower canopy and trunk |
| FLOWER | Walkable flower in the flower altitude band | 2 (`GROUND_DECOR_LAYER`) | (9, 3) | 1×1 | None |
| STONES | Walkable stones on bare land and beaches in some biomes (`BiomeCatalog.STRUCTURES`, biomes on only) | 2 (`GROUND_DECOR_LAYER`) | (0, 7) | 1×1 | None |

With Solaria, TREE was 3×3 cells and BUSH 1×2. Both are now 1×1, so they draw smaller and their collision polygons were redrawn. The TREE and BUSH polygons are wide and tall enough that adjacent plants leave no gap the player (8×10 box) fits through. On the 16 px grid, trees leave 2 px side to side and 5 px top to bottom, and bushes leave 4 px and 5 px. So a row, column or block of trees or bushes is a wall (`test_forest_walls` sweeps half-pixel lanes). One free cell between two plants is still passable.

## Island terrain

`ISLAND_BLOB_<mask>` pieces for the "Island" terrain. The mask is the sum of the land neighbours: N 1, NE 2, E 4, SE 8, S 16, SW 32, W 64, NW 128. A corner bit counts only when both of its sides are land. Islands are flat top-down, with no cliffs or undersides. Paint with `set_cells_terrain_connect(cells, TileCatalog.ISLAND_TERRAIN_SET, TileCatalog.ISLAND_TERRAIN)`. The base piece has probability 1.0. Its `_W1`-`_W3` variants have 0.4 (0.25 on the one-tile necks, masks 17 and 68). Mask 255 also accepts GRASS_A-D. "Same outline" lists the older edge tile that matches a piece.

| Mask | Open sides | Base piece | Variants | Same outline |
|---|---|---|---|---|
| 0 | NESW | ISLAND_BLOB_000 (16, 8) | - | - |
| 1 | ESW | ISLAND_BLOB_001 (17, 8) | - | - |
| 4 | NSW | ISLAND_BLOB_004 (18, 8) | - | - |
| 5 | SW | ISLAND_BLOB_005 (19, 8) | - | - |
| 7 | SW | ISLAND_BLOB_007 (20, 8) | - | GRASS_CORNER_OUT_SW |
| 16 | NEW | ISLAND_BLOB_016 (21, 8) | - | - |
| 17 | EW | ISLAND_BLOB_017 (22, 8) | W1 (4, 8), W2 (5, 8), W3 (6, 8) | - |
| 20 | NW | ISLAND_BLOB_020 (23, 8) | - | - |
| 21 | W | ISLAND_BLOB_021 (16, 9) | W1 (7, 8), W2 (8, 8), W3 (9, 8) | - |
| 23 | W | ISLAND_BLOB_023 (17, 9) | W1 (10, 8), W2 (11, 8), W3 (12, 8) | - |
| 28 | NW | ISLAND_BLOB_028 (18, 9) | - | GRASS_CORNER_OUT_NW |
| 29 | W | ISLAND_BLOB_029 (19, 9) | W1 (4, 9), W2 (5, 9), W3 (6, 9) | - |
| 31 | W | ISLAND_BLOB_031 (20, 9) | W1 (7, 9), W2 (8, 9), W3 (9, 9) | GRASS_EDGE_W |
| 64 | NES | ISLAND_BLOB_064 (21, 9) | - | - |
| 65 | ES | ISLAND_BLOB_065 (22, 9) | - | - |
| 68 | NS | ISLAND_BLOB_068 (23, 9) | W1 (10, 9), W2 (11, 9), W3 (12, 9) | - |
| 69 | S | ISLAND_BLOB_069 (16, 10) | W1 (4, 10), W2 (5, 10), W3 (6, 10) | - |
| 71 | S | ISLAND_BLOB_071 (17, 10) | W1 (7, 10), W2 (8, 10), W3 (9, 10) | - |
| 80 | NE | ISLAND_BLOB_080 (18, 10) | - | - |
| 81 | E | ISLAND_BLOB_081 (19, 10) | W1 (10, 10), W2 (11, 10), W3 (12, 10) | - |
| 84 | N | ISLAND_BLOB_084 (20, 10) | W1 (4, 11), W2 (5, 11), W3 (6, 11) | - |
| 85 | - | ISLAND_BLOB_085 (21, 10) | - | - |
| 87 | - | ISLAND_BLOB_087 (22, 10) | - | - |
| 92 | N | ISLAND_BLOB_092 (23, 10) | W1 (7, 11), W2 (8, 11), W3 (9, 11) | - |
| 93 | - | ISLAND_BLOB_093 (16, 11) | - | - |
| 95 | - | ISLAND_BLOB_095 (17, 11) | - | - |
| 112 | NE | ISLAND_BLOB_112 (18, 11) | - | GRASS_CORNER_OUT_NE |
| 113 | E | ISLAND_BLOB_113 (19, 11) | W1 (10, 11), W2 (11, 11), W3 (12, 11) | - |
| 116 | N | ISLAND_BLOB_116 (20, 11) | W1 (4, 12), W2 (5, 12), W3 (6, 12) | - |
| 117 | - | ISLAND_BLOB_117 (21, 11) | - | - |
| 119 | - | ISLAND_BLOB_119 (22, 11) | - | - |
| 124 | N | ISLAND_BLOB_124 (23, 11) | W1 (7, 12), W2 (8, 12), W3 (9, 12) | GRASS_EDGE_N |
| 125 | - | ISLAND_BLOB_125 (16, 12) | - | - |
| 127 | - | ISLAND_BLOB_127 (17, 12) | - | GRASS_CORNER_IN_NW |
| 193 | ES | ISLAND_BLOB_193 (18, 12) | - | GRASS_CORNER_OUT_SE |
| 197 | S | ISLAND_BLOB_197 (19, 12) | W1 (10, 12), W2 (11, 12), W3 (12, 12) | - |
| 199 | S | ISLAND_BLOB_199 (20, 12) | W1 (4, 13), W2 (5, 13), W3 (6, 13) | GRASS_EDGE_S |
| 209 | E | ISLAND_BLOB_209 (21, 12) | W1 (7, 13), W2 (8, 13), W3 (9, 13) | - |
| 213 | - | ISLAND_BLOB_213 (22, 12) | - | - |
| 215 | - | ISLAND_BLOB_215 (23, 12) | - | - |
| 221 | - | ISLAND_BLOB_221 (16, 13) | - | - |
| 223 | - | ISLAND_BLOB_223 (17, 13) | - | GRASS_CORNER_IN_SW |
| 241 | E | ISLAND_BLOB_241 (18, 13) | W1 (10, 13), W2 (11, 13), W3 (12, 13) | GRASS_EDGE_E |
| 245 | - | ISLAND_BLOB_245 (19, 13) | - | - |
| 247 | - | ISLAND_BLOB_247 (20, 13) | - | GRASS_CORNER_IN_SE |
| 253 | - | ISLAND_BLOB_253 (21, 13) | - | GRASS_CORNER_IN_NE |
| 255 | - | ISLAND_BLOB_255 (22, 13) | - | - |

## Island edges

Older single edge tiles, kept for hand-placed maps.

| Name | Cell |
|---|---|
| GRASS_EDGE_N | (0, 0) |
| GRASS_EDGE_E | (1, 0) |
| GRASS_EDGE_S | (2, 0) |
| GRASS_EDGE_W | (3, 0) |
| GRASS_CORNER_OUT_NE | (0, 1) |
| GRASS_CORNER_OUT_SE | (1, 1) |
| GRASS_CORNER_OUT_SW | (2, 1) |
| GRASS_CORNER_OUT_NW | (3, 1) |
| GRASS_CORNER_IN_NE | (0, 2) |
| GRASS_CORNER_IN_SE | (1, 2) |
| GRASS_CORNER_IN_SW | (2, 2) |
| GRASS_CORNER_IN_NW | (3, 2) |

## Trees

`_TOP`/`_BOTTOM` are the two cells of a 1×2 tree. `TREE_BIG_OAK_*` is a 2×2 tree. None of these have collision yet; the generator places only TREE.

| Name | Cell |
|---|---|
| TREE_PINE_TOP | (8, 0) |
| TREE_BIRCH_TOP | (9, 0) |
| TREE_APPLE_TOP | (10, 0) |
| TREE_AUTUMN_TOP | (11, 0) |
| TREE_OAK_TALL_TOP | (12, 0) |
| TREE_BIG_OAK_TL | (13, 0) |
| TREE_BIG_OAK_TR | (14, 0) |
| TREE_BUSHY | (7, 1) |
| TREE_PINE_BOTTOM | (8, 1) |
| TREE_BIRCH_BOTTOM | (9, 1) |
| TREE_APPLE_BOTTOM | (10, 1) |
| TREE_AUTUMN_BOTTOM | (11, 1) |
| TREE_OAK_TALL_BOTTOM | (12, 1) |
| TREE_BIG_OAK_BL | (13, 1) |
| TREE_BIG_OAK_BR | (14, 1) |
| TREE_PINE_SMALL | (7, 2) |

## Props, rocks and clouds

`CLOUD_M_0-1` (2×1) and `CLOUD_L_0-5` (3×2) are row-major parts of multi-cell clouds.

| Name | Cell |
|---|---|
| ROCK_FLOAT_S | (0, 7) |
| ROCK_FLOAT_M | (1, 7) |
| PROP_FLAG_BLUE | (2, 7) |
| PROP_FLAG_RED | (3, 7) |
| CLOUD_S | (0, 8) |
| CLOUD_M_0 | (1, 8) |
| CLOUD_M_1 | (2, 8) |
| CLOUD_L_0 | (0, 9) |
| CLOUD_L_1 | (1, 9) |
| CLOUD_L_2 | (2, 9) |
| CLOUD_L_3 | (0, 10) |
| CLOUD_L_4 | (1, 10) |
| CLOUD_L_5 | (2, 10) |

## Walls

Overlay tiles with a transparent background, placed on top of grass. `END_x`: the open end points to x. `T_x`: the stem points away from x. `CORNER_OUT_*` has its battlements on the outside of the bend, `CORNER_IN_*` on the inside.

| Name | Cell |
|---|---|
| WALL_POST | (16, 0) |
| WALL_END_N | (17, 0) |
| WALL_END_E | (18, 0) |
| WALL_END_S | (19, 0) |
| WALL_END_W | (20, 0) |
| WALL_H | (21, 0) |
| WALL_V | (22, 0) |
| WALL_CORNER_OUT_NW | (23, 0) |
| WALL_CORNER_OUT_NE | (16, 1) |
| WALL_CORNER_OUT_SW | (17, 1) |
| WALL_CORNER_OUT_SE | (18, 1) |
| WALL_CORNER_IN_NW | (19, 1) |
| WALL_CORNER_IN_NE | (20, 1) |
| WALL_CORNER_IN_SW | (21, 1) |
| WALL_CORNER_IN_SE | (22, 1) |
| WALL_T_N | (23, 1) |
| WALL_T_E | (16, 2) |
| WALL_T_S | (17, 2) |
| WALL_T_W | (18, 2) |
| WALL_CROSS | (19, 2) |
| WALL_GATE_H | (20, 2) |
| WALL_GATE_H_OPEN | (21, 2) |
| WALL_GATE_V | (22, 2) |
| WALL_H_DMG_CRACK | (23, 2) |
| WALL_H_DMG_CHUNK | (16, 3) |
| WALL_V_DMG_CRACK | (17, 3) |
