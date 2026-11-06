class_name BridgeBuilder
extends RefCounted
## Plank bridges on the world map: laying a straight run over water and the
## placed pieces. Moved from Scripts/TileMap.gd (#261). The map keeps wrappers
## with the same names and asks has_bridge / piece / piece_or when it draws a chunk.
## Host sync (#297): to_sync / replace_from_host carry the placed cells to a
## joining peer with the map params; live placements go through Interaction.
## World saves (#226): to_changes / from_changes turn that same list into
## world.tile_edits entries and back (docs/world-saves.md).

const _WorldMap := preload("res://Scripts/TileMap.gd")

## Plank bridge cells (build_bridge) -> layer-0 piece. generate_chunk draws
## the piece instead of the generated water; a new map clears them.
var _bridge_cells: Dictionary = {}
var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func has_bridge(cell: Vector2i) -> bool:
	return _bridge_cells.has(cell)


func set_cell(cell: Vector2i, atlas: Vector2i) -> void:
	## Record a piece at `cell` with no adjacency checks (TileMap.set_bridge_cell).
	_bridge_cells[cell] = atlas


func piece(cell: Vector2i) -> Vector2i:
	## The plank piece at `cell` (has_bridge must be true).
	return _bridge_cells[cell]


func piece_or(cell: Vector2i, default: Vector2i) -> Vector2i:
	## The plank piece at `cell`, or `default` when there is no bridge there.
	return _bridge_cells.get(cell, default)


func clear() -> void:
	_bridge_cells.clear()


func to_sync() -> Array:
	## Placed bridge cells as [x, y, atlas_x, atlas_y], sorted by cell, for the
	## host to send a joining peer with the map (#297).
	var cells: Array = _bridge_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	var out := []
	for cell: Vector2i in cells:
		var atlas: Vector2i = _bridge_cells[cell]
		out.append([cell.x, cell.y, atlas.x, atlas.y])
	return out


func replace_from_host(list: Array) -> int:
	## Client: make the bridges exactly the host's `list` (to_sync). Call it
	## right after the params are applied, before the chunks are drawn again.
	## The host already checked each cell. Returns how many bridge cells it holds.
	clear()
	for entry in list:
		if not entry is Array or entry.size() != 4:
			continue
		if not (entry[0] is int and entry[1] is int and entry[2] is int and entry[3] is int):
			continue
		var cell := Vector2i(entry[0], entry[1])
		var atlas := Vector2i(entry[2], entry[3])
		_bridge_cells[cell] = atlas
		_map.tree_sprouts().touch(cell)
		_map._predict_cache.erase(cell)
		if _map.get_cell_source_id(0, cell) != -1:
			_map.set_cell(0, cell, TileCatalog.SOURCE_ID, atlas)
	return _bridge_cells.size()


static func to_changes(list: Array) -> Dictionary[String, Dictionary]:
	## A to_sync list as world save entries (world.tile_edits, #226): chunk ->
	## {cell: {"tile": the plank piece's TileCatalog name}}. Names, not atlas
	## coords, so a save outlives a tileset rearrangement.
	var names := _plank_names()
	var out: Dictionary[String, Dictionary] = {}
	for entry in list:
		var cell := Vector2i(entry[0], entry[1])
		var chunk := WorldSave.chunk_key(cell)
		if not out.has(chunk):
			out[chunk] = {}
		out[chunk][WorldSave.cell_key(cell)] = {"tile": names[Vector2i(entry[2], entry[3])]}
	return out


static func from_changes(changes: Dictionary, map: _WorldMap) -> Array:
	## The to_sync list in world save entries written by to_changes, for
	## replace_from_host. Call it after apply_map_params, before any bridge
	## is placed. An entry is dropped when its tile is not a plank piece or
	## the map no longer generates water on its cell; entries without "tile"
	## belong to other features and are left alone.
	var atlases := {}
	var names := _plank_names()
	for atlas in names:
		atlases[names[atlas]] = atlas
	var out := []
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			var cell = WorldSave.parse_cell(str(key))
			if not entry is Dictionary or not atlases.has(str(entry.get("tile", ""))) or cell == null:
				continue
			if map.predict_cell(cell)[0] != TileCatalog.WATER:
				continue
			var atlas: Vector2i = atlases[str(entry["tile"])]
			out.append([cell.x, cell.y, atlas.x, atlas.y])
	return out


static func _plank_names() -> Dictionary:
	## Atlas -> TileCatalog name of every plank piece laid on water.
	var out := {}
	for tile_name: String in TileCatalog.TILES:
		if tile_name.begins_with("BRIDGE_PLANK_") and tile_name.ends_with("_WATER"):
			out[TileCatalog.TILES[tile_name]["atlas"]] = tile_name
	return out


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
		_map.tree_sprouts().touch(c)
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
