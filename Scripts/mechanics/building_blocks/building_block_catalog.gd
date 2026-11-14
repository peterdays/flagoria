class_name BuildingBlockCatalog
extends RefCounted
## Every WFC building-block piece, socket compatibility, and adjacency tables
## (#23). The solver in #24 reads piece ids, per-side sockets, and
## `adjacency_table()`.

const PIECES: Array[BuildingBlockPiece] = [
	preload("res://data/building_blocks/empty.tres"),
	preload("res://data/building_blocks/floor.tres"),
	preload("res://data/building_blocks/wall_straight.tres"),
	preload("res://data/building_blocks/wall_corner.tres"),
	preload("res://data/building_blocks/door.tres"),
	preload("res://data/building_blocks/window.tres"),
	preload("res://data/building_blocks/roof_edge.tres"),
	preload("res://data/building_blocks/roof_fill.tres"),
]

const SIDES: PackedStringArray = ["N", "E", "S", "W"]
const OPPOSITE := {"N": "S", "E": "W", "S": "N", "W": "E"}

## Allowed neighbours across an edge: both labels must list each other.
const SOCKET_COMPAT: Dictionary = {
	"void": ["void", "eave", "wall", "door", "window"],
	"floor": ["floor", "wall", "door", "window"],
	"wall": ["floor", "wall", "door", "window", "void"],
	"door": ["floor", "wall", "void"],
	"window": ["floor", "wall", "void"],
	"roof": ["roof", "eave"],
	"eave": ["void", "roof", "eave"],
}


static func all() -> Array[BuildingBlockPiece]:
	return PIECES.duplicate()


static func by_id(piece_id: String) -> BuildingBlockPiece:
	for piece: BuildingBlockPiece in PIECES:
		if piece.id == piece_id:
			return piece
	return null


static func socket_compatible(a: String, b: String) -> bool:
	if not SOCKET_COMPAT.has(a) or not SOCKET_COMPAT.has(b):
		return false
	return b in SOCKET_COMPAT[a] and a in SOCKET_COMPAT[b]


static func edge_compatible(
		piece_a: BuildingBlockPiece, side_a: String, piece_b: BuildingBlockPiece) -> bool:
	var opp: String = OPPOSITE[side_a]
	return socket_compatible(piece_a.socket(side_a), piece_b.socket(opp))


## piece_id -> side -> { other_piece_id: true } when the two cells may touch.
static func adjacency_table() -> Dictionary:
	var table := {}
	for pa: BuildingBlockPiece in PIECES:
		table[pa.id] = {}
		for side: String in SIDES:
			var fits := {}
			for pb: BuildingBlockPiece in PIECES:
				if edge_compatible(pa, side, pb):
					fits[pb.id] = true
			table[pa.id][side] = fits
	return table