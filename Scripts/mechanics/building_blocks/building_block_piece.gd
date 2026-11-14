class_name BuildingBlockPiece
extends Resource
## One modular building-block cell for WFC (#23–#24): a display tile name and
## the socket label on each cardinal edge (N, E, S, W).

@export var id := ""
## TileCatalog.TILES key for the piece art, or empty for void/empty cells.
@export var tile_name := ""
## Socket labels per side: N, E, S, W. Values come from BuildingBlockCatalog.
@export var sockets: Dictionary = {}


func socket(side: String) -> String:
	return str(sockets.get(side, ""))