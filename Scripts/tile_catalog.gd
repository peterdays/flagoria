class_name TileCatalog
extends RefCounted
## Semantic names for the map tiles, mapped to TileSet source id and atlas
## coords. Map code uses these names instead of raw atlas positions, so a
## tileset swap changes only this file and the TileSet. See docs/tiles.md.

const SOURCE_ID := 0

const WATER := Vector2i(5, 6)
const SAND := Vector2i(5, 4)
const SWAMP := Vector2i(14, 7)
const SWAMP_SPECIAL := Vector2i(27, 7)
const GRASS_A := Vector2i(5, 0)
const GRASS_B := Vector2i(5, 1)
const GRASS_C := Vector2i(6, 0)
const GRASS_D := Vector2i(6, 1)
const BUSH := Vector2i(7, 3)
const TREE := Vector2i(7, 0)
const FLOWER := Vector2i(9, 3)

## Name -> {source_id, atlas}. Every constant above appears here.
const TILES := {
	"WATER": {"source_id": SOURCE_ID, "atlas": WATER},
	"SAND": {"source_id": SOURCE_ID, "atlas": SAND},
	"SWAMP": {"source_id": SOURCE_ID, "atlas": SWAMP},
	"SWAMP_SPECIAL": {"source_id": SOURCE_ID, "atlas": SWAMP_SPECIAL},
	"GRASS_A": {"source_id": SOURCE_ID, "atlas": GRASS_A},
	"GRASS_B": {"source_id": SOURCE_ID, "atlas": GRASS_B},
	"GRASS_C": {"source_id": SOURCE_ID, "atlas": GRASS_C},
	"GRASS_D": {"source_id": SOURCE_ID, "atlas": GRASS_D},
	"BUSH": {"source_id": SOURCE_ID, "atlas": BUSH},
	"TREE": {"source_id": SOURCE_ID, "atlas": TREE},
	"FLOWER": {"source_id": SOURCE_ID, "atlas": FLOWER},
}
