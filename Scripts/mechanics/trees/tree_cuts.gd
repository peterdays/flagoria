class_name TreeCuts
extends RefCounted
## Tree and bush cuts on the world map: the cut cells, regrowth and what each
## cut leaves. Moved from Scripts/TileMap.gd (#261). The map keeps wrappers
## with the same names and asks has_cut / leftover when it draws a chunk.

const _WorldMap := preload("res://Scripts/TileMap.gd")

# Cells whose tree or bush was cut (Vector2i -> [play_time at the cut, atlas
# of what it left, the InteractableType cut]). Drawing the chunk again puts that STUMP or BUSH_STUMP
# there instead of the plant, until it regrows (regrow_due). Cleared when the
# params change.
var _cut_cells: Dictionary = {}
## Seconds of play after a cut before any stump turns back into its plant,
## overriding each type's regrow_delay (0 = never); negative, the default,
## uses the type's.
var regrow_delay: float = -1.0
var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func has_cut(cell: Vector2i) -> bool:
	return _cut_cells.has(cell)


func leftover(cell: Vector2i) -> Vector2i:
	## The STUMP or BUSH_STUMP atlas a cut left at `cell` (has_cut must be true).
	return _cut_cells[cell][1]


func is_empty() -> bool:
	return _cut_cells.is_empty()


func clear() -> void:
	_cut_cells.clear()


func to_changes() -> Dictionary[String, Dictionary]:
	## The cuts as world save entries (world.object_changes,
	## docs/world-saves.md): chunk -> {cell: {"cut": the type's save_key,
	## "age": seconds of play since the cut}}. The age, not the cut's
	## play_time, so a loaded cut keeps its place in the regrowth wait.
	var out: Dictionary[String, Dictionary] = {}
	for cell: Vector2i in _cut_cells:
		var type: InteractableType = _cut_cells[cell][2]
		var chunk := WorldSave.chunk_key(cell)
		if not out.has(chunk):
			out[chunk] = {}
		out[chunk][WorldSave.cell_key(cell)] = {"cut": type.save_key, "age": _map.play_time - _cut_cells[cell][0]}
	return out


func restore(changes: Dictionary) -> int:
	## Adds the cuts in world save entries written by to_changes. Call it
	## after apply_map_params, best before the chunks are drawn: drawing then
	## puts the stumps in (a cell drawn already is swapped like a cut). Entries that are not cuts are left to their own
	## readers. A cut is dropped when its type is unknown or the map no
	## longer grows that type on its cell. Returns how many cuts were added.
	var added := 0
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			if not entry is Dictionary or not entry.has("cut"):
				continue
			var cell = WorldSave.parse_cell(str(key))
			var type := InteractableCatalog.by_save_key(str(entry["cut"]))
			if cell == null or type == null or grown(cell) != type:
				continue
			_add(cell, type, _map.play_time - maxf(0.0, float(entry.get("age", 0.0))))
			added += 1
	return added


func replace(changes: Dictionary) -> int:
	## Make the cuts exactly the ones in `changes` (to_changes entries), as
	## restore checks them: a cut not listed grows back, a listed one is
	## added once. A joining peer applies the host's list this way, so it ends
	## with the host's set whatever it held before. Returns how many it holds.
	var listed := {}
	for chunk in changes:
		for key in changes[chunk]:
			listed[WorldSave.parse_cell(str(key))] = true
	for cell in _cut_cells.keys():
		if not listed.has(cell):
			_grow_back(cell)
	restore(changes)
	return _cut_cells.size()


func grown(cell: Vector2i) -> InteractableType:
	## The choppable type the map grows on `cell`, drawn or not, or null when
	## it grows none there or it is cut.
	if _cut_cells.has(cell):
		return null
	return InteractableCatalog.type_at(_map.predict_cell(cell)[1])


func cut_grown(cell: Vector2i) -> InteractableType:
	## Cut what grown(cell) finds, drawn or not: the host decides cuts next to
	## any player, not only in the chunks around its own. Returns the type
	## cut, or null.
	var type := grown(cell)
	if type != null:
		_add(cell, type, _map.play_time)
	return type


func _add(cell: Vector2i, type: InteractableType, cut_at: float) -> void:
	_cut_cells[cell] = [cut_at, type.leaves_atlas(), type]
	_map._predict_cache.erase(cell)
	if _map.get_cell_source_id(1, cell) != -1:  # drawn already: swap it like a chop
		_map.erase_cell(1, cell)
		_map.set_cell(_map.GROUND_DECOR_LAYER, cell, TileCatalog.SOURCE_ID, type.leaves_atlas())


func choppable(cell: Vector2i) -> InteractableType:
	## The choppable type (tree, bush) on `cell`'s foliage layer, or null.
	if _map.get_cell_source_id(1, cell) == -1:
		return null
	return InteractableCatalog.type_at(_map.get_cell_atlas_coords(1, cell))


func has_tree(cell: Vector2i) -> bool:
	var type := choppable(cell)
	return type != null and (type.id == "tree" or type.id == "pine")


func cut_choppable(cell: Vector2i) -> InteractableType:
	## Replace the tree or bush at `cell` with what its type leaves (a
	## walkable STUMP or BUSH_STUMP): the cell keeps it when its chunk is
	## drawn again, until regrow_due grows the plant back. Returns the type
	## that was cut, or null when there is nothing to cut.
	var type := choppable(cell)
	if type != null:
		_add(cell, type, _map.play_time)
	return type


func regrow_due() -> int:
	## Stumps cut at least their regrow delay ago turn back into the tree
	## or bush the map generates there; a stump under a player waits until the cell
	## is free. Regrowth is not synced (#298): nothing regrows while
	## multiplayer is active. Returns how many plants regrew.
	if Interaction.multiplayer_on(_map.multiplayer):
		return 0
	var regrown := 0
	for cell in _cut_cells.keys():
		var delay: float = regrow_delay if regrow_delay >= 0.0 else _cut_cells[cell][2].regrow_delay
		if delay == 0.0 or _map.play_time - _cut_cells[cell][0] < delay or _map.player_on_cell(cell):
			continue
		regrown += int(_grow_back(cell))
	return regrown


func _grow_back(cell: Vector2i) -> bool:
	## Drop the cut on `cell`; true when its plant was drawn back in.
	_cut_cells.erase(cell)
	_map._predict_cache.erase(cell)
	if _map.get_cell_source_id(0, cell) == -1:
		return false  # not drawn yet: generate_chunk draws the plant
	_map.erase_cell(_map.GROUND_DECOR_LAYER, cell)
	var b := _map.biome_at(cell)
	_map.set_tile_type_z1(cell, _map.cell_altitude(cell, b), _map.moisture.get_noise_2d(cell.x, cell.y),
			_map.temperature.get_noise_2d(cell.x, cell.y), _map.items_chance.get_noise_2d(cell.x, cell.y), b)
	return true
