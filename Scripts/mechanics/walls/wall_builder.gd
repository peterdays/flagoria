class_name WallBuilder
extends RefCounted
## Free-form palisade walls on the world map (#276). Cells are stored, solved
## with WallSolver (joining stone structure walls), painted on overlay layer 1,
## and kept when a chunk is drawn again. Collision comes from the PALISADE_*
## tiles. A new map clears them. Play places through ConstructionPlacer.

const _WorldMap := preload("res://Scripts/TileMap.gd")

## Free-form wall cells -> WallSolver entry ({"family": PALISADE, ...}).
var _wall_cells: Dictionary = {}
## Solved TileCatalog atlas at each free-form cell (for redraw).
var _pieces: Dictionary = {}
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


func clear() -> void:
	_wall_cells.clear()
	_pieces.clear()


func erase_cells(cells: Array[Vector2i]) -> bool:
	## Remove free-form walls on `cells`, re-solve neighbours, clear overlay.
	## True when at least one cell was a free-form wall.
	var removed: Array[Vector2i] = []
	for cell in cells:
		if not _wall_cells.has(cell):
			continue
		_wall_cells.erase(cell)
		_pieces.erase(cell)
		_map._predict_cache.erase(cell)
		if _map.get_cell_source_id(1, cell) != -1:
			_map.erase_cell(1, cell)
		removed.append(cell)
	if removed.is_empty():
		return false
	var touch: Array[Vector2i] = []
	for cell in removed:
		for n in ConstructionPlacer._neighbours(cell):
			if _wall_cells.has(n) and n not in touch:
				touch.append(n)
	if not touch.is_empty():
		_resolve(touch)
	return true


func place_cells(cells: Array[Vector2i]) -> bool:
	## Write plain palisade walls on `cells`, re-solve neighbours, paint layer 1.
	## False and nothing written when `cells` is empty or any cell is already a
	## free-form wall (caller must have checked land / occupation).
	if cells.is_empty():
		return false
	for cell in cells:
		if _wall_cells.has(cell):
			return false
	for cell in cells:
		_wall_cells[cell] = {"family": WallSolver.PALISADE}
	_resolve(cells)
	return true


func _resolve(changed: Array[Vector2i]) -> void:
	## Re-solve every free-form wall (structure walls count as neighbours only)
	## and paint free-form cells that may have changed piece.
	var all := {}
	for cell: Vector2i in _wall_cells:
		all[cell] = _wall_cells[cell]
	for cell: Vector2i in _wall_cells:
		for n in ConstructionPlacer._neighbours(cell):
			if all.has(n):
				continue
			var entry := _structure_wall_entry(n)
			if not entry.is_empty():
				all[n] = entry
	var solved := WallSolver.solve(all)
	var touch := {}
	for cell in changed:
		touch[cell] = true
		for n in ConstructionPlacer._neighbours(cell):
			touch[n] = true
	for cell: Vector2i in _wall_cells:
		if not touch.has(cell) and _pieces.has(cell):
			continue
		var name: String = solved.get(cell, "PALISADE_POST")
		var atlas: Vector2i = TileCatalog.TILES[name]["atlas"]
		_pieces[cell] = atlas
		_map._tree_cuts.forget(cell)
		_map._predict_cache.erase(cell)
		if _map.get_cell_source_id(0, cell) == -1:
			continue
		_map.erase_cell(1, cell)
		_map.erase_cell(_WorldMap.GROUND_DECOR_LAYER, cell)
		_map.set_cell(1, cell, TileCatalog.SOURCE_ID, atlas)


func _structure_wall_entry(cell: Vector2i) -> Dictionary:
	## WallSolver entry for a structure-owned wall cell, or {} when none.
	if not _map._structures.has_cell(cell):
		return {}
	var atlas: Vector2i = _map._structures.object_at(cell)
	var name := _atlas_wall_name(atlas)
	if name.is_empty():
		return {}
	var family := WallSolver.PALISADE if name.begins_with("PALISADE_") else WallSolver.STONE
	return {
		"family": family,
		"gate": name.contains("GATE"),
		"open": name.ends_with("_OPEN"),
	}


static func _atlas_wall_name(atlas: Vector2i) -> String:
	for name: String in TileCatalog.TILES:
		if not name.begins_with("WALL_") and not name.begins_with("PALISADE_"):
			continue
		if TileCatalog.TILES[name]["atlas"] == atlas:
			return name
	return ""
