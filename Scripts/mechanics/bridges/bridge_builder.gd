class_name BridgeBuilder
extends RefCounted
## Plank bridges on the world map: laying a straight run over water and the
## placed pieces. Moved from Scripts/TileMap.gd (#261). The map keeps wrappers
## with the same names and asks has_bridge / piece / piece_or when it draws a chunk.

const _WorldMap := preload("res://Scripts/TileMap.gd")

## Plank bridge cells (build_bridge) -> layer-0 piece. generate_chunk draws
## the piece instead of the generated water; a new map clears them.
var _bridge_cells: Dictionary = {}
var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func has_bridge(cell: Vector2i) -> bool:
	return _bridge_cells.has(cell)


func piece(cell: Vector2i) -> Vector2i:
	## The plank piece at `cell` (has_bridge must be true).
	return _bridge_cells[cell]


func piece_or(cell: Vector2i, default: Vector2i) -> Vector2i:
	## The plank piece at `cell`, or `default` when there is no bridge there.
	return _bridge_cells.get(cell, default)


func clear() -> void:
	_bridge_cells.clear()


func build_bridge(from: Vector2i, to: Vector2i) -> bool:
	## Lay a straight plank bridge on the water cells from `from` to `to`, both
	## included, in one row (H) or one column (V). An end piece shows a land
	## joint when the cell past it is walkable ground, else an unfinished tip.
	## Planks have no collision, so the hero walks on them; they stay when
	## the chunk is drawn again. False, and nothing placed, unless every cell
	## is generated water with no bridge yet.
	if from.x != to.x and from.y != to.y:
		return false
	var first := Vector2i(mini(from.x, to.x), mini(from.y, to.y))
	var length := absi(to.x - from.x) + absi(to.y - from.y) + 1
	var land := func(c: Vector2i) -> bool:
		return not _bridge_cells.has(c) and _map.ground_is_walkable(_map.predict_cell(c)[0])
	var horizontal := from.x != to.x
	if from == to:  # one cell: across the land it touches, H by default
		horizontal = land.call(first + Vector2i.LEFT) or land.call(first + Vector2i.RIGHT) \
				or not (land.call(first + Vector2i.UP) or land.call(first + Vector2i.DOWN))
	var step := Vector2i.RIGHT if horizontal else Vector2i.DOWN
	for i in length:
		var c := first + step * i
		if _bridge_cells.has(c) or _map.predict_cell(c)[0] != TileCatalog.WATER:
			return false
	var pieces := bridge_pieces(length, horizontal, land.call(first - step), land.call(first + step * length))
	for i in length:
		var c := first + step * i
		_bridge_cells[c] = pieces[i]
		_map._predict_cache.erase(c)
		if _map.get_cell_source_id(0, c) != -1:
			_map.set_cell(0, c, TileCatalog.SOURCE_ID, pieces[i])
	return true


static func bridge_pieces(length: int, horizontal: bool, land_before: bool, land_after: bool) -> Array[Vector2i]:
	## The _WATER plank pieces of a straight run of `length` cells, W->E (H) or
	## N->S (V): START/END where land is before/after the run, SINGLE for one
	## cell with land on both sides, TIP_ at an end with no land, H/V between.
	var axis := "H" if horizontal else "V"
	var out: Array[Vector2i] = []
	for i in length:
		var before := i == 0 and land_before
		var after := i == length - 1 and land_after
		var piece := axis
		if before and after:
			piece += "_SINGLE"
		elif before:
			piece += "_START"
		elif after:
			piece += "_END"
		elif i == length - 1:
			piece += "_TIP_E" if horizontal else "_TIP_S"
		elif i == 0:
			piece += "_TIP_W" if horizontal else "_TIP_N"
		out.append(TileCatalog.TILES["BRIDGE_PLANK_%s_WATER" % piece]["atlas"])
	return out
