# Tileset credits

| File | Source | Author | License |
| --- | --- | --- | --- |
| `flagoria_tiles_v3.png` | Original pixel art, made in-house for this project (tileset v3.1) | Flagoria project | Repository licence (`LICENSE.md`) |
| `flagoria_tiles_v3.tres` | Godot 4.7 TileSet for the atlas above, made in-house for this project. The repository copy adds one physics layer (collision on WATER, TREE, BUSH and the wall pieces) | Flagoria project | Repository licence (`LICENSE.md`) |

The atlas is 448×304 px, 28×19 cells of 16×16 px. Import it with Nearest filtering and no mipmaps. Cell names are in `Scripts/tile_catalog.gd` and `docs/tiles.md`.

Cell (8, 2), the tree stump (`STUMP`), was drawn later in code in the same palette, also in-house.
Cell (8, 3), the bush stump (`BUSH_STUMP`), and the bush chop frames in `fx/` (`bush_hit.png`, `fx_leaves.png`) were drawn later in the same palette, also in-house.
The tree and pine chop frames in `fx/` (`tree_hit.png`, `pine_hit.png`, `fx_tree.png`, `fx_pine.png`) are drawn in code from the tree tiles and the same palette by `tools/art/gen_tree_chop_frames.py`, also in-house.

Rows 15-18 (wooden palisade walls and plank bridges) were drawn later in code in the same palette, also in-house.

Cells (4, 7) and (5, 7), the neutral and mob flags (`PROP_FLAG_NEUTRAL`, `PROP_FLAG_MOBS`), are placeholders recoloured in code from the blue flag by `tools/art/gen_flag_tiles.py`, also in-house.
