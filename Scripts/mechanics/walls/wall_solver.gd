class_name WallSolver
extends RefCounted
## Picks the wall piece for each wall cell from its neighbours (#36, #414).
## Stone (WALL_*), wooden palisade (PALISADE_*) and tower ring (TOWER_STONE_*)
## cells share one solver. Each cell keeps its own family. A palisade that
## touches stone gets collar caps instead of a baked join piece. Pure: no
## TileMap access.

const STONE := "WALL"
const PALISADE := "PALISADE"
const TOWER := "TOWER"

## Neighbour steps in mask bit order: N 1, E 2, S 4, W 8.
const STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const SIDE := ["N", "E", "S", "W"]
const MASK_TABLE := {
	0: "POST", 1: "END_S", 2: "END_W", 4: "END_N", 8: "END_E", 5: "V", 10: "H",
	6: "CORNER_OUT_NW", 12: "CORNER_OUT_NE", 3: "CORNER_OUT_SW", 9: "CORNER_OUT_SE",
	14: "T_N", 13: "T_E", 11: "T_S", 7: "T_W", 15: "CROSS",
}
## Corner quadrant -> the diagonal reached by stepping along both of its arms.
const BEND_STEP := {
	"NW": Vector2i(1, 1), "NE": Vector2i(-1, 1), "SW": Vector2i(1, -1), "SE": Vector2i(-1, -1),
}
## Offset inside the 3x3 tower -> ring name. The centre (1, 1) is the flag.
const RING_AT := {
	Vector2i(0, 0): "NW", Vector2i(1, 0): "N", Vector2i(2, 0): "NE",
	Vector2i(0, 1): "W", Vector2i(2, 1): "E",
	Vector2i(0, 2): "SW", Vector2i(1, 2): "S", Vector2i(2, 2): "SE",
}
## Outer sides of a ring cell, already in N, E, S, W order (SE is E then S).
const RING_ARMS := {
	"NW": "NW", "N": "N", "NE": "NE", "W": "W", "E": "E", "SW": "SW", "S": "S", "SE": "ES",
}


static func ring_at(offset: Vector2i) -> String:
	return RING_AT.get(offset, "")


static func solve(walls: Dictionary) -> Dictionary:
	## cell -> {"family", "gate", "open", "damage", "ring"}. Missing keys: closed
	## undamaged stone. Returns TileCatalog names. Every entry is a neighbour.
	## Gate N+S is GATE_V, else GATE_H. CORNER_OUT flips to CORNER_IN in a notch.
	## Damage applies to plain H and V only.
	var outside := _outside(walls)
	var out := {}
	for cell: Vector2i in walls:
		var w: Dictionary = walls[cell]
		var family: String = w.get("family", STONE)
		var mask := 0
		for i in STEPS.size():
			if walls.has(cell + STEPS[i]):
				mask |= 1 << i
		if family == TOWER:
			out[cell] = _tower_piece(str(w.get("ring", "")), mask)
			continue
		var piece: String
		if w.get("gate", false):
			piece = "GATE_V" if mask & 5 == 5 else "GATE_H"
			if w.get("open", false) and TileCatalog.TILES.has("%s_%s_OPEN" % [family, piece]):
				piece += "_OPEN"
		else:
			piece = MASK_TABLE[mask]
			if piece.begins_with("CORNER_OUT_"):
				var q := piece.right(2)
				if outside.has(cell + BEND_STEP[q]) and not outside.has(cell - BEND_STEP[q]):
					piece = "CORNER_IN_" + q
			var damage: String = w.get("damage", "")
			if damage != "" and (piece == "H" or piece == "V") \
					and TileCatalog.TILES.has("%s_%s_DMG_%s" % [family, piece, damage]):
				piece += "_DMG_" + damage
		out[cell] = family + "_" + piece
	return out


static func caps(walls: Dictionary) -> Dictionary:
	## Palisade cell -> every CAP_COLLAR_* on a stone side, N then E then S then W.
	## Drawing uses the first two. A third or fourth has no approved layer or baked tile.
	var out := {}
	for cell: Vector2i in walls:
		var w: Dictionary = walls[cell]
		if w.get("family", STONE) != PALISADE:
			continue
		var list: Array[String] = []
		for i in STEPS.size():
			var at: Vector2i = cell + STEPS[i]
			if walls.has(at) and _is_stone(walls[at]):
				list.append("CAP_COLLAR_" + SIDE[i])
		if not list.is_empty():
			out[cell] = list
	return out


static func _is_stone(w: Dictionary) -> bool:
	var family: String = w.get("family", STONE)
	return family == STONE or family == TOWER


static func _tower_piece(ring: String, mask: int) -> String:
	var arms := ""
	var possible: String = RING_ARMS.get(ring, "")
	for i in possible.length():
		var bit := "NESW".find(possible[i])
		if bit >= 0 and (mask & (1 << bit)) != 0:
			arms += possible[i]
	return "TOWER_STONE_%s_%s" % [ring, "X" if arms.is_empty() else arms]


static func _outside(walls: Dictionary) -> Dictionary:
	## Non-wall cells reachable from the edge of the walls' bounding box grown
	## by one cell. Everything else in the box is enclosed.
	var outside := {}
	if walls.is_empty():
		return outside
	var first: Vector2i = walls.keys()[0]
	var lo := first
	var hi := first
	for cell: Vector2i in walls:
		lo = lo.min(cell)
		hi = hi.max(cell)
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var todo: Array[Vector2i] = [lo]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		if outside.has(p) or walls.has(p) or p.x < lo.x or p.y < lo.y or p.x > hi.x or p.y > hi.y:
			continue
		outside[p] = true
		for s in STEPS:
			todo.append(p + s)
	return outside
