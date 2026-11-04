class_name TreeSprouts
extends RefCounted
## Trees that sprout on free cells (#361). Where the area around a player
## holds fewer trees of a biome than BiomeCatalog.TREE_SHARE asks for, and
## fewer than the map generates there, a tree grows on a free cell of that
## biome. A stump still counts as its tree, since it regrows (TreeCuts), so
## only trees gone for good (a structure built on their stumps) are made up
## for, and an untouched area never gets more trees than it generates.
## The host decides (due); a client adds the host's sprouts (add, through
## Interaction.apply_sprout_cells). Saves and joining peers get them in the
## cut list (TreeCuts.to_changes, "sprout" entries).

const _WorldMap := preload("res://Scripts/TileMap.gd")

## Seconds of play between two sprout passes on the host. Each pass, each
## missing tree sprouts with chance PASS_SECONDS / regrow delay, so a
## missing tree takes about one regrow delay to come back, like a stump.
const PASS_SECONDS := 5.0
const TREES: Array[Vector2i] = [TileCatalog.TREE, TileCatalog.TREE_BUSHY, TileCatalog.PINE]
## Side of the area around each player that a pass counts, in chunks: the
## player's chunk and its neighbours. One chunk is smaller than a forest
## patch, so a thinned biome would refill only where it was sparse.
const AREA_CHUNKS := 3

## Sprouted cell -> its tree atlas (sprout_tile).
var _sprouts: Dictionary = {}
var _next_pass := 0.0
var _rng := RandomNumberGenerator.new()
var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func has(cell: Vector2i) -> bool:
	return _sprouts.has(cell)


func tile_or(cell: Vector2i, fallback: Vector2i) -> Vector2i:
	## The sprouted tree on `cell`, or `fallback` (what the map puts there).
	return _sprouts.get(cell, fallback)


func size() -> int:
	return _sprouts.size()


func clear() -> void:
	_sprouts.clear()
	_next_pass = 0.0


func erase(cell: Vector2i) -> void:
	## Drop the sprout on `cell` (a structure now covers it), undrawn.
	_sprouts.erase(cell)


func sprout_tile(cell: Vector2i) -> Vector2i:
	## The tree the map would grow on `cell` at the highest items chance:
	## TREE, TREE_BUSHY or PINE, or NO_PLANT when it grows no tree there.
	var b := _map.biome_at(cell)
	var tile := _map.plant_tile(_map.cell_altitude(cell, b), _map.moisture.get_noise_2d(cell.x, cell.y), 1.0, b)
	return tile if tile in TREES else _WorldMap.NO_PLANT


func can_sprout(cell: Vector2i, under_mobs: Dictionary) -> Vector2i:
	## The tree that may sprout on `cell` now, or NO_PLANT: the ground is
	## walkable (not water) and not a beach with biomes on, there is no
	## structure, bridge, plant, stump, stones, mob or player on it, and the
	## map grows a tree there (sprout_tile).
	var p := _map.predict_cell(cell)
	if not _map.ground_is_walkable(p[0]) or (_map.biome_frequency > 0.0 and p[0] == TileCatalog.SAND):
		return _WorldMap.NO_PLANT
	if _map._structures.has_cell(cell) or _map._bridges.has_bridge(cell) or p[1] != _WorldMap.NO_PLANT:
		return _WorldMap.NO_PLANT
	if under_mobs.has(cell) or _map.player_on_cell(cell):
		return _WorldMap.NO_PLANT
	return sprout_tile(cell)


func add(cell: Vector2i) -> bool:
	## Sprout sprout_tile(cell) on `cell`, drawn or not. A client applies the
	## host's sprouts this way, without the host's checks. False when the
	## cell has a sprout already or the map grows no tree there.
	var tile := sprout_tile(cell)
	if tile == _WorldMap.NO_PLANT or _sprouts.has(cell):
		return false
	_sprouts[cell] = tile
	_map._predict_cache.erase(cell)
	if _map.get_cell_source_id(0, cell) != -1 and not _map._tree_cuts.has_cut(cell):
		_map.set_cell(1, cell, TileCatalog.SOURCE_ID, tile)
	return true


func deficits(window: Rect2i) -> Dictionary:
	## Biome id -> trees missing in `window`: the smaller of TREE_SHARE of its
	## land cells (rounded down) and the trees the map generates there
	## (counting cells under structures), less the trees, sprouts and tree
	## stumps it holds. Only biomes missing at least one are listed.
	var land := {}
	var grown := {}
	var now := {}
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var cell := Vector2i(x, y)
			var p := _map.predict_cell(cell)
			if p[0] == TileCatalog.WATER or _map._bridges.has_bridge(cell):
				continue
			var b := _map.biome_at(cell)
			land[b] = land.get(b, 0) + 1
			var stump := _map._tree_cuts.has_cut(cell) and _map._tree_cuts.cut_type(cell).id != "bush"
			if p[1] in TREES or stump:
				now[b] = now.get(b, 0) + 1
			if _generated_tree(cell, b, p, stump):
				grown[b] = grown.get(b, 0) + 1
	var out := {}
	for b in land:
		var missing: int = mini(floori(BiomeCatalog.tree_share(b) * land[b]), grown.get(b, 0)) - now.get(b, 0)
		if missing > 0:
			out[b] = missing
	return out


func _generated_tree(cell: Vector2i, b: int, p: Array, stump: bool) -> bool:
	## True when the generated map (no cuts, sprouts or structures) has a
	## tree on `cell`.
	if _sprouts.has(cell):
		return false
	if not _map._structures.has_cell(cell):
		return stump or (p[1] in TREES and not _map._tree_cuts.has_cut(cell))
	var ground := _map.ground_tile(_map.cell_altitude(cell, b), _map.moisture.get_noise_2d(cell.x, cell.y),
			_map.items_chance.get_noise_2d(cell.x, cell.y), b)
	if not _map.ground_is_walkable(ground) or (_map.biome_frequency > 0.0 and ground == TileCatalog.SAND):
		return false
	return _map.plant_tile(_map.cell_altitude(cell, b), _map.moisture.get_noise_2d(cell.x, cell.y),
			_map.items_chance.get_noise_2d(cell.x, cell.y), b) in TREES


func candidates(window: Rect2i) -> Dictionary:
	## Biome id -> the cells in `window` where a tree may sprout now
	## (can_sprout), in row order. The cells under mobs are gathered once.
	var under_mobs := _map.mob_cells()
	var out := {}
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var cell := Vector2i(x, y)
			if can_sprout(cell, under_mobs) != _WorldMap.NO_PLANT:
				var b := _map.biome_at(cell)
				if not out.has(b):
					out[b] = []
				out[b].append(cell)
	return out


func sprout_pass(window: Rect2i, chance: float) -> Array[Vector2i]:
	## For each tree `window` is missing (deficits), sprout one on a random
	## free cell of that biome (candidates) with probability `chance`.
	## Returns the cells that sprouted.
	var out: Array[Vector2i] = []
	var missing := deficits(window)
	if missing.is_empty():
		return out
	var free := candidates(window)
	for b in missing:
		var cells: Array = free.get(b, [])
		for i in missing[b]:
			if cells.is_empty():
				break
			if _rng.randf() >= chance:
				continue
			var cell: Vector2i = cells.pop_at(_rng.randi_range(0, cells.size() - 1))
			if add(cell):
				out.append(cell)
	return out


func due() -> Array[Vector2i]:
	## Host (or alone): every PASS_SECONDS of play, one sprout_pass on the
	## AREA_CHUNKS area around each player, with chance PASS_SECONDS over the tree
	## regrow delay (the map's regrow_delay when set; 0 = never). Emits the
	## map's trees_sprouted with the cells. A client never sprouts on its own.
	var out: Array[Vector2i] = []
	if Interaction.multiplayer_on(_map.multiplayer) and not _map.multiplayer.is_server():
		return out
	if _map.play_time < _next_pass:
		return out
	_next_pass = _map.play_time + PASS_SECONDS
	var delay: float = _map.regrow_delay if _map.regrow_delay >= 0.0 else InteractableCatalog.by_id("tree").regrow_delay
	if delay <= 0.0:
		return out
	var size_v := Vector2i(_map.chunk_width, _map.chunk_height) * AREA_CHUNKS
	for node in _map.get_parent().get_children():
		if node is CharacterBody2D and str(node.name).is_valid_int():
			var at := _map.local_to_map(_map.to_local(node.global_position))
			out.append_array(sprout_pass(Rect2i(at - size_v / 2, size_v), minf(1.0, PASS_SECONDS / delay)))
	if not out.is_empty():
		_map.trees_sprouted.emit(out)
	return out


func to_changes(out: Dictionary) -> void:
	## Add the sprouts to `out` (TreeCuts.to_changes entries): each sprouted
	## cell's entry gets "sprout", the save_key of its tree's type.
	for cell: Vector2i in _sprouts:
		var chunk := WorldSave.chunk_key(cell)
		if not out.has(chunk):
			out[chunk] = {}
		var key := WorldSave.cell_key(cell)
		if not out[chunk].has(key):
			out[chunk][key] = {}
		out[chunk][key]["sprout"] = InteractableCatalog.type_at(_sprouts[cell]).save_key


func restore(changes: Dictionary) -> int:
	## Add the sprouts in to_changes entries ("sprout"). A sprout is dropped
	## when the map no longer grows that type of tree on its cell. Returns
	## how many were added.
	var added := 0
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			var cell = WorldSave.parse_cell(str(key))
			if not entry is Dictionary or not entry.has("sprout") or cell == null:
				continue
			var tile := sprout_tile(cell)
			if tile != _WorldMap.NO_PLANT and InteractableCatalog.type_at(tile).save_key == str(entry["sprout"]) and add(cell):
				added += 1
	return added


func replace(changes: Dictionary) -> Array[Vector2i]:
	## Make the sprouts exactly the ones in `changes`: restore them, and drop
	## each one not listed. Returns the dropped cells, for TreeCuts to drop
	## their cuts and draw them again.
	var listed := {}
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			if entry is Dictionary and entry.has("sprout"):
				listed[WorldSave.parse_cell(str(key))] = true
	var dropped: Array[Vector2i] = []
	for cell: Vector2i in _sprouts.keys():
		if not listed.has(cell):
			_sprouts.erase(cell)
			dropped.append(cell)
	restore(changes)
	return dropped
