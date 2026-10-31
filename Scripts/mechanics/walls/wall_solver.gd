class_name WallSolver
extends RefCounted
## Picks the wall piece for each wall cell from its neighbours (#36). Stone
## (WALL_*) and wooden palisade (PALISADE_*) cells share one solver and
## connect to each other, but each cell keeps its own family. The result is
## TileCatalog names for the overlay layer. Pure: no TileMap access.

const STONE := "WALL"
const PALISADE := "PALISADE"

## Neighbour steps in mask bit order: N 1, E 2, S 4, W 8.
const STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const MASK_TABLE := {
	0: "POST", 1: "END_S", 2: "END_W", 4: "END_N", 8: "END_E", 5: "V", 10: "H",
	6: "CORNER_OUT_NW", 12: "CORNER_OUT_NE", 3: "CORNER_OUT_SW", 9: "CORNER_OUT_SE",
	14: "T_N", 13: "T_E", 11: "T_S", 7: "T_W", 15: "CROSS",
}
## Corner quadrant -> the diagonal reached by stepping along both of its arms.
const BEND_STEP := {
	"NW": Vector2i(1, 1), "NE": Vector2i(-1, 1), "SW": Vector2i(1, -1), "SE": Vector2i(-1, -1),
}


static func solve(walls: Dictionary) -> Dictionary:
	## walls: cell (Vector2i) -> {"family": STONE or PALISADE, "gate": bool,
	## "open": bool, "damage": "" / "CRACK" / "CHUNK"}; missing keys mean a
	## closed, undamaged stone wall. Returns cell -> TileCatalog name.
	## - Gates count as wall neighbours. A gate with N and S neighbours is
	##   GATE_V, otherwise GATE_H; "open" adds _OPEN.
	## - Inside corners: a CORNER_OUT_q turns into CORNER_IN_q when the cell
	##   along both of its arms is outside every enclosure and the cell on the
	##   other side of the bend is enclosed. A corner that encloses nothing
	##   stays OUT.
	## - A palisade H with a stone neighbour E or W becomes H_JOIN_E or
	##   H_JOIN_W (E first); V becomes V_JOIN_N or V_JOIN_S (N first).
	## - Damage applies to plain H and V only.
	## A piece with no art in its family (stone GATE_V_OPEN, any V_DMG_CHUNK)
	## falls back to the closed or undamaged piece.
	var outside := _outside(walls)
	var out := {}
	for cell: Vector2i in walls:
		var w: Dictionary = walls[cell]
		var family: String = w.get("family", STONE)
		var mask := 0
		for i in STEPS.size():
			if walls.has(cell + STEPS[i]):
				mask |= 1 << i
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
			if family == PALISADE:
				piece = _join(walls, cell, piece)
			var damage: String = w.get("damage", "")
			if damage != "" and (piece == "H" or piece == "V") \
					and TileCatalog.TILES.has("%s_%s_DMG_%s" % [family, piece, damage]):
				piece += "_DMG_" + damage
		out[cell] = family + "_" + piece
	return out


static func _join(walls: Dictionary, cell: Vector2i, piece: String) -> String:
	var sides := {"H": [["E", Vector2i(1, 0)], ["W", Vector2i(-1, 0)]],
		"V": [["N", Vector2i(0, -1)], ["S", Vector2i(0, 1)]]}
	for side in sides.get(piece, []):
		var at: Vector2i = cell + side[1]
		if walls.has(at) and walls[at].get("family", STONE) == STONE:
			return "%s_JOIN_%s" % [piece, side[0]]
	return piece


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
