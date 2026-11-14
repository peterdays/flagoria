# flagoria structures: FINAL spec

These 8 structures were picked for final art: archer post, neutral outpost, barracks, respawn camp, trading post, lumber mill, watchtower and sky dock. The castle keep was not picked.

- **Art:** drawn in code on the 16 px grid with palette v1.1 and the #2a2238 outline, lit from the top-left. Materials match the v3 atlas:
  - stone blocks;
  - 3 px boards;
  - thatch;
  - the T3 bastion hip roof (thatch rim, N facet wood_hi, W facet wood, E and S facets wood_dark, gold finial), used on the archer post and the watchtower.
- **Atlas:** `atlas/flagoria_tiles_v4.png` is 448x304, the same size as v3. It is v3 (main as of 825c8d3, which already holds the walls-junctions finals) plus **54 new pieces in cells that were empty in v3**. Every v3 cell is pixel-identical, and a test checks it.
- **Drop-in:**
  1. Point source 0 of `flagoria_tiles_v3.tres` at v4.
  2. Append `tileset_lines.tres.txt`.
  3. Add `tile_catalog_lines.gd.txt` to `Scripts/tile_catalog.gd`.
  4. Read the placement rules from `placement.json` or from this file.
- **Collision:** rectangles are in tile-local pixels with the origin at the cell centre (-8..8), in the same format as the walls-junctions final. A cell listed as "none" has no polygon.
- **Team cells:** only cells that carry team colour have a `_BLUE` and a `_RED` version. Owner 1 (the host) uses `_BLUE` and any other player uses `_RED`, the same rule as `StructurePlacer.OWNER_FLAGS` / `OTHER_OWNER_FLAG`. When the owner changes, swap them like `PROP_FLAG_*`.
- **Costs:** every cost here is a **suggestion** carried over from IDEAS.md. BuildCosts today has plank 1, wall block 2, tower 10.

## Archer post

- **Footprint:** 1x1 tiles.
- **Anchor:** [0, 0] (offset from the top-left cell; for buildings it is the door or front cell, like the gate anchor in `castle.txt`).
- **Cost:** 6 wood (suggestion, IDEAS.md).
- **Placement:** Only on a wall cell whose solved shape is H or V (stone WALL_* or PALISADE_*). Replaces that cell: WALL_H -> ARCHER_POST_STONE_H, WALL_V -> ARCHER_POST_STONE_V, PALISADE_H/V -> ARCHER_POST_PALISADE_H/V. Counts as a wall neighbour of its own kind (stone / palisade) for masks, enclosures, cities and C2 collar caps. A later wall that would turn the cell into a corner, T, cross or end is refused ("archer post") rather than silently removing the post.

| Cell name | Atlas | Offset | Layer | Collision (tile-local) | Team | Replaces |
|-|-|-|-|-|-|-|
| `ARCHER_POST_STONE_H` | (0, 3) | (0,0) | 1 (replaces the wall cell) | (-8,-7)-(8,7); (-7,-8)-(7,7) | - | WALL_H |
| `ARCHER_POST_STONE_V` | (1, 3) | (0,0) | 1 (replaces the wall cell) | (-5,-8)-(5,8); (-7,-7)-(7,7) | - | WALL_V |
| `ARCHER_POST_PALISADE_H` | (2, 3) | (0,0) | 1 (replaces the wall cell) | (-8,-7)-(8,7); (-7,-8)-(7,7) | - | PALISADE_H |
| `ARCHER_POST_PALISADE_V` | (3, 3) | (0,0) | 1 (replaces the wall cell) | (-5,-8)-(5,8); (-7,-7)-(7,7) | - | PALISADE_V |

## Neutral outpost

- **Footprint:** 5x4 tiles.
- **Anchor:** [2, 3] (offset from the top-left cell; for buildings it is the door or front cell, like the gate anchor in `castle.txt`).
- **Cost:** world-gen only (suggestion, IDEAS.md).
- **Placement:** guard_post layout (T###T / #...# / #.F.# / ##G##) placed by world gen, one per island. After the wall solver, map each WALL_<shape> to WALL_MOSS_<shape> (all solved shapes of this layout exist). Optionally one N/S straight cell becomes WALL_MOSS_H_BREACH and one W/E straight cell WALL_MOSS_V_DMG_CRACK (seeded). The flag is PROP_FLAG_GREY (team); on capture it swaps to PROP_FLAG_BLUE/RED like any flag tower. Moss stays after capture. STONES on a cell next to the breach.

| Cell name | Atlas | Offset | Layer | Collision (tile-local) | Team | Replaces |
|-|-|-|-|-|-|-|
| `WALL_MOSS_CORNER_OUT_NW` | (4, 3) | - | 1 (as the plain wall piece) | (-5,-7)-(8,7); (-5,-7)-(5,8) | - | WALL_CORNER_OUT_NW |
| `WALL_MOSS_CORNER_OUT_NE` | (5, 3) | - | 1 (as the plain wall piece) | (-8,-7)-(5,7); (-5,-7)-(5,8) | - | WALL_CORNER_OUT_NE |
| `WALL_MOSS_CORNER_OUT_SW` | (6, 3) | - | 1 (as the plain wall piece) | (-5,-7)-(8,7); (-5,-8)-(5,7) | - | WALL_CORNER_OUT_SW |
| `WALL_MOSS_CORNER_OUT_SE` | (10, 3) | - | 1 (as the plain wall piece) | (-8,-7)-(5,7); (-5,-8)-(5,7) | - | WALL_CORNER_OUT_SE |
| `WALL_MOSS_H` | (11, 3) | - | 1 (as the plain wall piece) | (-8,-7)-(8,7) | - | WALL_H |
| `WALL_MOSS_V` | (15, 3) | - | 1 (as the plain wall piece) | (-5,-8)-(5,8) | - | WALL_V |
| `WALL_MOSS_GATE_H` | (25, 3) | - | 1 (as the plain wall piece) | (-8,-7)-(8,7) | - | WALL_GATE_H |
| `WALL_MOSS_GATE_H_OPEN` | (26, 3) | - | 1 (as the plain wall piece) | (-8,-7)-(-6,7); (6,-7)-(8,7) | - | WALL_GATE_H_OPEN |
| `WALL_MOSS_V_DMG_CRACK` | (27, 3) | - | 1 (as the plain wall piece) | (-5,-8)-(5,8) | - | WALL_V_DMG_CRACK |
| `WALL_MOSS_H_BREACH` | (0, 4) | - | 1 (as WALL_H) | (-8,-7)-(-4,7); (4,-7)-(8,7) | - | WALL_H |
| `PROP_FLAG_GREY` | (1, 4) | (2,2) | 1 (team flag cell) | none | - | PROP_FLAG_NEUTRAL |

## Barracks

- **Footprint:** 3x2 tiles.
- **Anchor:** [1, 1] (offset from the top-left cell; for buildings it is the door or front cell, like the gate anchor in `castle.txt`).
- **Cost:** 25 wood (suggestion, IDEAS.md).
- **Placement:** All 6 cells walkable free land (no water, structure, plant, stump, mob or player); the cell below the anchor (door) must be walkable and is kept free. Team cells: column 1 (crest and door banners).

| Cell name | Atlas | Offset | Layer | Collision (tile-local) | Team | Replaces |
|-|-|-|-|-|-|-|
| `BARRACKS_0_0` | (12, 3) | (0,0) | 1 | (-7,-7)-(8,8) | - | - |
| `BARRACKS_1_0_BLUE` | (13, 3) | (1,0) | 1 | (-8,-7)-(8,8) | BLUE | - |
| `BARRACKS_1_0_RED` | (2, 4) | (1,0) | 1 | (-8,-7)-(8,8) | RED | - |
| `BARRACKS_2_0` | (14, 3) | (2,0) | 1 | (-8,-7)-(7,8) | - | - |
| `BARRACKS_0_1` | (12, 4) | (0,1) | 1 | (-7,-8)-(8,8) | - | - |
| `BARRACKS_1_1_BLUE` | (13, 4) | (1,1) | 1 | (-8,-8)-(8,8) | BLUE | - |
| `BARRACKS_1_1_RED` | (3, 4) | (1,1) | 1 | (-8,-8)-(8,8) | RED | - |
| `BARRACKS_2_1` | (14, 4) | (2,1) | 1 | (-8,-8)-(7,8) | - | - |

## Respawn camp

- **Footprint:** 2x2 tiles.
- **Anchor:** [0, 1] (offset from the top-left cell; for buildings it is the door or front cell, like the gate anchor in `castle.txt`).
- **Cost:** 12 wood (suggestion, IDEAS.md).
- **Placement:** All 4 cells walkable free land; the respawn point is the cell below the anchor (in front of the tent door), which must be walkable and is kept free. Tent cells carry team colour.

| Cell name | Atlas | Offset | Layer | Collision (tile-local) | Team | Replaces |
|-|-|-|-|-|-|-|
| `RESPAWN_CAMP_0_0_BLUE` | (21, 3) | (0,0) | 1 | (-2,-8)-(8,8) | BLUE | - |
| `RESPAWN_CAMP_0_0_RED` | (4, 4) | (0,0) | 1 | (-2,-8)-(8,8) | RED | - |
| `RESPAWN_CAMP_1_0_BLUE` | (22, 3) | (1,0) | 1 | (-8,0)-(-3,8) | BLUE | - |
| `RESPAWN_CAMP_1_0_RED` | (6, 4) | (1,0) | 1 | (-8,0)-(-3,8) | RED | - |
| `RESPAWN_CAMP_0_1_BLUE` | (21, 4) | (0,1) | 1 | (-8,-8)-(8,3) | BLUE | - |
| `RESPAWN_CAMP_0_1_RED` | (7, 4) | (0,1) | 1 | (-8,-8)-(8,3) | RED | - |
| `RESPAWN_CAMP_1_1_BLUE` | (22, 4) | (1,1) | 1 | (-8,-8)-(7,7) | BLUE | - |
| `RESPAWN_CAMP_1_1_RED` | (15, 4) | (1,1) | 1 | (-8,-8)-(7,7) | RED | - |

## Trading post

- **Footprint:** 2x2 tiles.
- **Anchor:** [0, 1] (offset from the top-left cell; for buildings it is the door or front cell, like the gate anchor in `castle.txt`).
- **Cost:** world-gen, or 15 wood (suggestion, IDEAS.md).
- **Placement:** All 4 cells walkable free land; the trader NPC stands on the cell below the anchor, facing the counter. Neutral (no team cells).

| Cell name | Atlas | Offset | Layer | Collision (tile-local) | Team | Replaces |
|-|-|-|-|-|-|-|
| `TRADING_POST_0_0` | (23, 3) | (0,0) | 1 | (-8,-7)-(8,8) | - | - |
| `TRADING_POST_1_0` | (24, 3) | (1,0) | 1 | (-8,-7)-(8,8) | - | - |
| `TRADING_POST_0_1` | (23, 4) | (0,1) | 1 | (-7,-8)-(8,7) | - | - |
| `TRADING_POST_1_1` | (24, 4) | (1,1) | 1 | (-8,-8)-(7,7) | - | - |

## Lumber mill

- **Footprint:** 3x2 tiles.
- **Anchor:** [1, 1] (offset from the top-left cell; for buildings it is the door or front cell, like the gate anchor in `castle.txt`).
- **Cost:** 20 wood (suggestion, IDEAS.md).
- **Placement:** All 6 cells walkable free land; cell below the anchor kept free. Neutral colours (no team cells).

| Cell name | Atlas | Offset | Layer | Collision (tile-local) | Team | Replaces |
|-|-|-|-|-|-|-|
| `LUMBER_MILL_0_0` | (18, 3) | (0,0) | 1 | (-7,-7)-(8,8) | - | - |
| `LUMBER_MILL_1_0` | (19, 3) | (1,0) | 1 | (-8,-7)-(8,8) | - | - |
| `LUMBER_MILL_2_0` | (20, 3) | (2,0) | 1 | (-3,4)-(4,8) | - | - |
| `LUMBER_MILL_0_1` | (18, 4) | (0,1) | 1 | (-6,-8)-(8,7) | - | - |
| `LUMBER_MILL_1_1` | (19, 4) | (1,1) | 1 | (-8,-8)-(8,7) | - | - |
| `LUMBER_MILL_2_1` | (20, 4) | (2,1) | 1 | (-8,-8)-(8,6) | - | - |

## Watchtower

- **Footprint:** 1x1 tiles.
- **Anchor:** [0, 0] (offset from the top-left cell; for buildings it is the door or front cell, like the gate anchor in `castle.txt`).
- **Cost:** 8 wood (suggestion, IDEAS.md).
- **Placement:** WATCHTOWER_BASE on a walkable free land cell (collides). WATCHTOWER_TOP_<team> on the cell above, no collision, like TREE_*_TOP; that cell must have nothing on layer 1 (no wall, tree, bush or other structure).

| Cell name | Atlas | Offset | Layer | Collision (tile-local) | Team | Replaces |
|-|-|-|-|-|-|-|
| `WATCHTOWER_TOP_BLUE` | (16, 4) | (0,-1) | 1 (overhang, like TREE_*_TOP) | none | BLUE | - |
| `WATCHTOWER_TOP_RED` | (17, 4) | (0,-1) | 1 (overhang, like TREE_*_TOP) | none | RED | - |
| `WATCHTOWER_BASE` | (25, 4) | (0,0) | 1 | (-6,-8)-(6,7) | - | - |

## Sky dock

- **Footprint:** 2x2 tiles.
- **Anchor:** the ROOT cell (offset from the top-left cell; for buildings it is the door or front cell, like the gate anchor in `castle.txt`).
- **Cost:** 15 wood (suggestion, IDEAS.md).
- **Placement:** Coast-edge only. Pick direction d where the root is a walkable land cell and the cell beyond it in d is water: SKY_DOCK_<d>_ROOT on the root (walkable, no collision), SKY_DOCK_<d>_END on that water cell, SKY_SKIFF_<team> on the water cell beside the end (E of it for N/S docks, S of it for E/W docks); both must be water. The fourth cell of the 2x2 is left as it is. Layer 1, ground stays as generated (coast art shows under the deck). Board/travel by tapping the skiff in interact mode from the root.

| Cell name | Atlas | Offset | Layer | Collision (tile-local) | Team | Replaces |
|-|-|-|-|-|-|-|
| `SKY_DOCK_N_ROOT` | (26, 4) | (0,1) | 1 (deck, walkable on the root) | none | - | - |
| `SKY_DOCK_N_END` | (27, 4) | (0,0) | 1 (deck, walkable on the root) | (-6,-8)-(8,8) | - | - |
| `SKY_DOCK_E_ROOT` | (0, 6) | (0,0) | 1 (deck, walkable on the root) | none | - | - |
| `SKY_DOCK_E_END` | (1, 6) | (1,0) | 1 (deck, walkable on the root) | (-8,-6)-(8,8) | - | - |
| `SKY_DOCK_S_ROOT` | (2, 6) | (0,0) | 1 (deck, walkable on the root) | none | - | - |
| `SKY_DOCK_S_END` | (3, 6) | (0,1) | 1 (deck, walkable on the root) | (-6,-8)-(8,8) | - | - |
| `SKY_DOCK_W_ROOT` | (4, 6) | (1,0) | 1 (deck, walkable on the root) | none | - | - |
| `SKY_DOCK_W_END` | (6, 6) | (0,0) | 1 (deck, walkable on the root) | (-8,-6)-(8,8) | - | - |
| `SKY_SKIFF_BLUE` | (7, 6) | - | 1 (over water) | (-6,-5)-(6,7) | BLUE | - |
| `SKY_SKIFF_RED` | (8, 6) | - | 1 (over water) | (-6,-5)-(6,7) | RED | - |

## Sky dock cell offsets per direction

| Direction | Root (land) | End (water) | Skiff (water) |
|-|-|-|-|
| N | (0, 1) | (0, 0) | (1, 0) |
| S | (0, 0) | (0, 1) | (1, 1) |
| E | (0, 0) | (1, 0) | (1, 1) |
| W | (1, 0) | (0, 0) | (0, 1) |

## Judgement calls

- **Archer posts are baked tiles, not overlays.** Each one replaces its H or V wall cell, and the wall-cap layer stays free for C2 collars. Its connecting edge columns (H) or rows (V) are pixel-identical to the plain wall, which a test checks. Its collision is the wall polygon plus the hut box. It carries no team colour, like walls, because city tint already shows the owner.
- **Moss pieces keep their `WALL_` names** (`WALL_MOSS_*`), so they still count as walls for masks, enclosures and cities.
  - **Silhouette and edges:** each moss piece has exactly the silhouette of its plain piece, and its outer 2 px ring is unchanged.
  - **Breach:** the breach has walkable rubble in the middle and collides only on its two stubs.
  - **Flag:** `PROP_FLAG_GREY` is `PROP_FLAG_BLUE` with the team colours recoloured to stone_hi / stone, so a capture swap does not jump. The existing `PROP_FLAG_NEUTRAL` and `PROP_FLAG_MOBS` use off-palette greys and purple. Switching `OWNER_FLAGS[OWNER_NEUTRAL]` to `PROP_FLAG_GREY` is flagoria's call; I did not touch any v3 cell.
- **Team colour is kept small.** Only these cells need a red copy, 8 pairs in all:
  - the barracks crest and door banners (column 1);
  - the respawn tent (4 cells);
  - the watchtower pennant (its top cell);
  - the skiff hull.
  The trading post and lumber mill are neutral.
- **Sky dock is an L of three tiles on layer 1 over generated ground.** It is a pier root, a pier end and a one-cell skiff; the fourth cell of the 2x2 is left untouched. The ground is not rewritten, so the coast art shows under the root. The end cell and skiff sit on water, which stays unwalkable, and players board by tapping the skiff from the root. All four directions exist (N, E, S, W).
- **Watchtower top is a no-collision overhang**, like `TREE_*_TOP`. It needs a free layer-1 cell above it.
- **x1 polish over the mockups:**
  - pennants now have 2 px poles;
  - the skiff balloon is tied to its hull with 2 px struts instead of 1 px ropes, and the whole skiff fits one cell;
  - the archer post and watchtower use the T3 hip roof, so they read as part of the same tower family;
  - the outpost flag is the in-game flag size.
- **Not covered:** the Flagbearer hero in the previews keeps its own #141b1b palette and is exempt from the palette test, by box. The `PROP_FLAG_GREY` outline follows the existing flag tile, which has the same shadow pixels.

## Files

- **Atlas:** `atlas/flagoria_tiles_v4.png`.
- **Single tiles:** `tiles/*.png`, one per piece.
- **Labelled sheet:** `pieces_x4.png`.
- **Placement data:** `placement.json`, plus `tile_catalog_lines.gd.txt` and `tileset_lines.tres.txt`.
- **Phone previews:** `previews/phone_view_x1.png`, `phone_view_x2.png`, `phone_frame_x1.png` and `phone_frame_x2.png`.
- **Other previews:** `previews/scene_full_x1.png`, `detail_city_x4.png` and `detail_outpost_isle_x4.png`.
- **Build:** `build_structures_final.py`, then `make_spec.py`.
- **Tests:** `tests/test_final.py` (run with pytest).
