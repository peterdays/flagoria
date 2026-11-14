class_name ObjectRemovals
extends RefCounted
## Picked-up flowers and destroyed stones on the world map (#198). The map
## keeps wrappers with the same names; TreeCuts.restore skips these entries.

const _WorldMap := preload("res://Scripts/TileMap.gd")


var _removed: Dictionary = {}
var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func has_removed(cell: Vector2i) -> bool:
	return _removed.has(cell)


func clear() -> void:
	_removed.clear()


func is_empty() -> bool:
	return _removed.is_empty()


func decor_at(cell: Vector2i) -> Vector2i:
	## FLOWER, STONES or NO_PLANT on `cell`: the drawn ground decor when the
	## chunk is there, else what predict_cell would place on the decor layer.
	if _map.get_cell_source_id(0, cell) != -1:
		var decor := _map.get_cell_atlas_coords(_WorldMap.GROUND_DECOR_LAYER, cell)
		if decor == TileCatalog.FLOWER or decor == TileCatalog.STONES:
			return decor
		if _map.get_cell_source_id(1, cell) != -1:
			return _map.NO_PLANT
	var top: Vector2i = _map.predict_cell(cell)[1]
	if top == TileCatalog.FLOWER or top == TileCatalog.STONES:
		return top
	return _map.NO_PLANT


func pick(cell: Vector2i) -> bool:
	## Pick the flower on `cell`. False when it holds none or is already gone.
	if decor_at(cell) != TileCatalog.FLOWER:
		return false
	_mark_removed(cell)
	return true


func destroy(cell: Vector2i) -> bool:
	## Destroy the stones on `cell`. False when it holds none or is already gone.
	if decor_at(cell) != TileCatalog.STONES:
		return false
	_mark_removed(cell)
	return true


func remove_any(cell: Vector2i) -> bool:
	## Remove whatever flower or stones are on `cell`.
	var decor := decor_at(cell)
	if decor == _map.NO_PLANT:
		return false
	_mark_removed(cell)
	return true


func _mark_removed(cell: Vector2i) -> void:
	_removed[cell] = true
	_map._predict_cache.erase(cell)
	_map.tree_sprouts().touch(cell)
	if _map.get_cell_source_id(0, cell) != -1:
		_map.erase_cell(1, cell)
		_map.erase_cell(_WorldMap.GROUND_DECOR_LAYER, cell)


func _would_remove(cell: Vector2i) -> bool:
	## True when the map still grows a removable decor on `cell` (a stale save
	## entry is dropped when this is false).
	if _map.has_bridge(cell) or _map.has_wall(cell) or _map.has_cut(cell) or _map.choppable(cell) != null:
		return false
	var top: Vector2i = _map.predict_cell(cell)[1]
	return top == TileCatalog.FLOWER or top == TileCatalog.STONES


func to_changes() -> Dictionary[String, Dictionary]:
	## world.object_changes entries (docs/world-saves.md): chunk -> {cell:
	## {"removed": true}}.
	var out: Dictionary[String, Dictionary] = {}
	for cell: Vector2i in _removed:
		var chunk := WorldSave.chunk_key(cell)
		if not out.has(chunk):
			out[chunk] = {}
		out[chunk][WorldSave.cell_key(cell)] = {"removed": true}
	return out


func merge_into(out: Dictionary) -> void:
	## Add these removals to `out` (TreeCuts.to_changes). A cut on a cell wins.
	var mine := to_changes()
	for chunk in mine:
		if not out.has(chunk):
			out[chunk] = {}
		for key in mine[chunk]:
			var existing = out[chunk].get(key)
			if existing is Dictionary and existing.has("cut"):
				continue
			out[chunk][key] = mine[chunk][key]


func restore(changes: Dictionary) -> int:
	## Add the removals in world save entries. Skips cuts and other shapes.
	## Drops a removal when the map no longer grows decor there. Returns how
	## many were added.
	var added := 0
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			if not entry is Dictionary or not entry.get("removed", false):
				continue
			var cell = WorldSave.parse_cell(str(key))
			if cell == null or _removed.has(cell) or not _would_remove(cell):
				continue
			_removed[cell] = true
			_map._predict_cache.erase(cell)
			_map.tree_sprouts().touch(cell)
			if _map.get_cell_source_id(0, cell) != -1:
				_map.erase_cell(1, cell)
				_map.erase_cell(_WorldMap.GROUND_DECOR_LAYER, cell)
			added += 1
	return added


func replace(changes: Dictionary) -> int:
	## Make the removals exactly the ones listed, as restore checks them.
	var listed := {}
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			if entry is Dictionary and entry.get("removed", false):
				listed[WorldSave.parse_cell(str(key))] = true
	for cell in _removed.keys():
		if not listed.has(cell):
			_removed.erase(cell)
			_redraw(cell)
	return restore(changes)


func _redraw(cell: Vector2i) -> void:
	## Put generated decor back on a drawn cell whose removal was dropped.
	_map._predict_cache.erase(cell)
	if _map.get_cell_source_id(0, cell) == -1:
		return
	_map.erase_cell(1, cell)
	_map.erase_cell(_WorldMap.GROUND_DECOR_LAYER, cell)
	var moist := _map.moisture.get_noise_2d(cell.x, cell.y)
	var temp := _map.temperature.get_noise_2d(cell.x, cell.y)
	var chance := _map.items_chance.get_noise_2d(cell.x, cell.y)
	var b := _map.biome_at(cell)
	var alt := _map.cell_altitude(cell, b)
	_map.set_tile_type_z1(cell, alt, moist, temp, chance, b)


func object_changes_with(cuts: TreeCuts) -> Dictionary[String, Dictionary]:
	var out := cuts.to_changes()
	merge_into(out)
	return out


func restore_with(cuts: TreeCuts, changes: Dictionary) -> int:
	return cuts.restore(changes) + restore(changes)


func replace_with(cuts: TreeCuts, changes: Dictionary) -> int:
	return cuts.replace(changes) + replace(changes)


func cells_in_arc(origin: Vector2, direction: float, reach: float, arc: float, pick_stones: bool) -> Array[Vector2i]:
	## Walkable cells whose centre lies in the aim arc; stones only when
	## `pick_stones`, flowers when not.
	var out: Array[Vector2i] = []
	var half := arc * 0.5
	var cell_px: float = float(_map.tile_set.tile_size.x) * _map.global_scale.x
	var radius := int(ceil(reach / cell_px)) + 1
	var centre := _map.local_to_map(_map.to_local(origin))
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell := centre + Vector2i(dx, dy)
			var offset := _map.to_global(_map.map_to_local(cell)) - origin
			if offset.length() > reach or offset.length() <= 0.001:
				continue
			if absf(angle_difference(direction, offset.angle())) > half:
				continue
			if pick_stones:
				if destroy(cell):
					out.append(cell)
			elif pick(cell):
				out.append(cell)
	return out