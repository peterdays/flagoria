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
	if type == null:
		return null
	_cut_cells[cell] = [_map.play_time, type.leaves_atlas(), type]
	_map._predict_cache.erase(cell)
	_map.erase_cell(1, cell)
	_map.set_cell(_map.GROUND_DECOR_LAYER, cell, TileCatalog.SOURCE_ID, type.leaves_atlas())
	return type


func regrow_due() -> int:
	## Stumps cut at least their regrow delay ago turn back into the tree
	## or bush the map generates there; a stump under a player waits until the cell
	## is free. Single-player only (cuts are not synced, #223): nothing
	## regrows while multiplayer is active. Returns how many plants regrew.
	if Interaction.multiplayer_on(_map.multiplayer):
		return 0
	var grown := 0
	for cell in _cut_cells.keys():
		var delay: float = regrow_delay if regrow_delay >= 0.0 else _cut_cells[cell][2].regrow_delay
		if delay == 0.0 or _map.play_time - _cut_cells[cell][0] < delay or _map.player_on_cell(cell):
			continue
		_cut_cells.erase(cell)
		_map._predict_cache.erase(cell)
		if _map.get_cell_source_id(0, cell) == -1:
			continue  # not drawn yet: generate_chunk draws the tree
		_map.erase_cell(_map.GROUND_DECOR_LAYER, cell)
		var b := _map.biome_at(cell)
		_map.set_tile_type_z1(cell, _map.cell_altitude(cell, b), _map.moisture.get_noise_2d(cell.x, cell.y),
				_map.temperature.get_noise_2d(cell.x, cell.y), _map.items_chance.get_noise_2d(cell.x, cell.y), b)
		grown += 1
	return grown
