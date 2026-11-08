class_name WallBuilder
extends RefCounted
## Free-form palisades solved with structure walls and tower rings (#276, #414).
## Pieces on layer 1. Each stone side draws its own CAP_COLLAR_* on the next
## cap layer, in N, E, S, W order. Caps add no collision.

const _WorldMap := preload("res://Scripts/TileMap.gd")

const CAP_LAYER := 3
const CAP_LAYER_2 := 4
const CAP_LAYER_3 := 5
const CAP_LAYER_4 := 6
const CAP_LAYERS: Array[int] = [3, 4, 5, 6]

## Free-form wall cells -> WallSolver entry ({"family": PALISADE, ...}).
var _wall_cells: Dictionary = {}
## Solved TileCatalog atlas at each free-form cell (for redraw).
var _pieces: Dictionary = {}
## Free-form cell -> full CAP_COLLAR_* list (N, E, S, W order).
var _caps: Dictionary = {}
var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func has_wall(cell: Vector2i) -> bool:
	return _wall_cells.has(cell)


func piece(cell: Vector2i) -> Vector2i:
	## Atlas at `cell` (has_wall must be true).
	return _pieces[cell]


func piece_or(cell: Vector2i, default: Vector2i) -> Vector2i:
	return _pieces.get(cell, default)


func cap_names(cell: Vector2i) -> Array:
	## Collar names on this free-form cell, or empty.
	return (_caps.get(cell, []) as Array).duplicate()


func clear() -> void:
	_wall_cells.clear()
	_pieces.clear()
	_caps.clear()


func erase_cells(cells: Array[Vector2i]) -> bool:
	## Remove free-form walls on `cells` and re-solve the whole junction set.
	## True when at least one cell was a free-form wall.
	var removed := false
	for cell in cells:
		if not _wall_cells.has(cell):
			continue
		_wall_cells.erase(cell)
		_pieces.erase(cell)
		_caps.erase(cell)
		_map._predict_cache.erase(cell)
		_erase_tiles(cell)
		removed = true
	if removed:
		resolve()
	return removed


func place_cells(cells: Array[Vector2i]) -> bool:
	## Write plain palisade walls on `cells` and re-solve. False and nothing
	## written when `cells` is empty or any cell is already a free-form wall.
	if cells.is_empty():
		return false
	for cell in cells:
		if _wall_cells.has(cell):
			return false
	for cell in cells:
		_wall_cells[cell] = {"family": WallSolver.PALISADE}
	resolve()
	return true


func paint_cell(cell: Vector2i) -> void:
	## Redraw one free-form wall after a chunk draw. has_wall must be true.
	_map.set_cell(1, cell, TileCatalog.SOURCE_ID, _pieces[cell])
	_paint_caps(cell)


func resolve() -> void:
	## Solve free-form walls, auto structure walls and tower rings as one set.
	## Repaint every cell whose piece or cap list changed, including a corner
	## that flips when a loop closes far from the edited cell.
	var all := _union()
	var solved := WallSolver.solve(all)
	var capmap := WallSolver.caps(all)
	for cell: Vector2i in _wall_cells:
		var name: String = solved.get(cell, "PALISADE_POST")
		var atlas: Vector2i = TileCatalog.TILES[name]["atlas"]
		var caps: Array = capmap.get(cell, [])
		var changed: bool = not _pieces.has(cell) or _pieces[cell] != atlas or not _same(caps, _caps.get(cell, []))
		_pieces[cell] = atlas
		if caps.is_empty():
			_caps.erase(cell)
		else:
			_caps[cell] = caps.duplicate()
		if changed:
			_paint_free(cell)
	for cell: Vector2i in _map._structures.auto_cells():
		if solved.has(cell):
			_map._structures.apply_solved(cell, solved[cell])


func _union() -> Dictionary:
	var all := {}
	var autos: Dictionary = _map._structures.auto_cells()
	for cell: Vector2i in autos:
		all[cell] = autos[cell]
	for cell: Vector2i in _wall_cells:
		all[cell] = _wall_cells[cell]
	return all


func _paint_free(cell: Vector2i) -> void:
	_map.forget_cut(cell)
	_map._predict_cache.erase(cell)
	if _map.get_cell_source_id(0, cell) == -1:
		return
	_map.erase_cell(1, cell)
	_map.erase_cell(_WorldMap.GROUND_DECOR_LAYER, cell)
	_map.set_cell(1, cell, TileCatalog.SOURCE_ID, _pieces[cell])
	_paint_caps(cell)


func _paint_caps(cell: Vector2i) -> void:
	## One existing collar tile per stone side. Unused layers are cleared.
	var caps: Array = _caps.get(cell, [])
	for i in CAP_LAYERS.size():
		var layer: int = CAP_LAYERS[i]
		if i < caps.size():
			_map.set_cell(layer, cell, TileCatalog.SOURCE_ID, TileCatalog.TILES[caps[i]]["atlas"])
		elif _map.get_cell_source_id(layer, cell) != -1:
			_map.erase_cell(layer, cell)


func _erase_tiles(cell: Vector2i) -> void:
	if _map.get_cell_source_id(1, cell) != -1:
		_map.erase_cell(1, cell)
	for layer in CAP_LAYERS:
		if _map.get_cell_source_id(layer, cell) != -1:
			_map.erase_cell(layer, cell)


static func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


static func _atlas_wall_name(atlas: Vector2i) -> String:
	## WALL_*, PALISADE_* or TOWER_STONE_* name at `atlas`, or "".
	for name: String in TileCatalog.TILES:
		if not name.begins_with("WALL_") and not name.begins_with("PALISADE_") \
				and not name.begins_with("TOWER_STONE_"):
			continue
		if TileCatalog.TILES[name]["atlas"] == atlas:
			return name
	return ""
