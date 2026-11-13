class_name StructurePlacer
extends RefCounted
## Structures placed on the world map (#270): the footprint check, writing
## the cells, and the list of placements. The map keeps wrappers
## (can_place_structure, place_structure, placed_structures) and asks
## has_cell / ground_at / object_at when it draws or predicts a cell.
## can_place still reports multiplayer on, so a client does not write. The
## host writes an accepted tower with place_from_host (#497). A joining peer
## gets the host's list with the map (to_sync, replace_from_host). Free-form
## walls placed after a join go through StructureRequests (#498).

const _WorldMap := preload("res://Scripts/TileMap.gd")

const WATER := "water"
const TREE := "tree"
const BUSH := "bush"
const OUT_OF_MAP := "out of map"
const OVERLAPS_STRUCTURE := "overlaps another structure"
const OVERLAPS_PLAYER := "overlaps a player"
const OVERLAPS_MOB := "overlaps a mob"
const MULTIPLAYER_ON := "multiplayer on"
## Owners that are not a peer id (#274): a tower nobody holds, and one the
## mobs took.
const OWNER_NEUTRAL := 0
const OWNER_MOBS := -1
## Owner -> flag tile for `team` legend entries. The host is blue, a neutral
## tower grey, a mob tower purple, and every other peer red until more owner
## colours exist.
const OWNER_FLAGS := {1: "PROP_FLAG_BLUE", OWNER_NEUTRAL: "PROP_FLAG_NEUTRAL", OWNER_MOBS: "PROP_FLAG_MOBS"}
const OTHER_OWNER_FLAG := "PROP_FLAG_RED"
const DIR := "res://structures"

## Placed cell -> [layer-0 atlas or NO_PLANT to keep the generated ground,
## layer-1 atlas or NO_PLANT for none]. generate_chunk draws these instead
## of the generated cell; a new map clears them.
var _cells: Dictionary = {}
## Auto wall or tower-ring cell -> WallSolver entry. Solved with free-form
## walls, not on its own (#414).
var _auto: Dictionary = {}
## Placement id -> {"name", "owner", "anchor"} (for saves, #42).
var _placed: Dictionary = {}
## Placement id -> its `team` flag cells, the towers TowerCapture watches.
var _flags: Dictionary = {}
var _next_id := 1
var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


func ground_at(cell: Vector2i, default: Vector2i) -> Vector2i:
	## The placed ground at `cell`, or `default` where the structure keeps it.
	var g: Vector2i = _cells[cell][0] if _cells.has(cell) else _WorldMap.NO_PLANT
	return default if g == _WorldMap.NO_PLANT else g


func object_at(cell: Vector2i) -> Vector2i:
	## The placed object at `cell` (has_cell must be true), or NO_PLANT.
	return _cells[cell][1]


func placements() -> Dictionary:
	return _placed.duplicate(true)


func clear() -> void:
	_cells.clear()
	_auto.clear()
	_placed.clear()
	_flags.clear()
	_next_id = 1


func auto_cells() -> Dictionary:
	## Auto wall and tower-ring cells -> solver entries.
	return _auto


func apply_solved(cell: Vector2i, tile_name: String) -> void:
	## Store and, when the chunk is drawn, paint a solved structure wall.
	var atlas: Vector2i = _atlas(tile_name)
	if not _cells.has(cell) or _cells[cell][1] == atlas:
		return
	_cells[cell][1] = atlas
	_map._predict_cache.erase(cell)
	if _map.get_cell_source_id(0, cell) == -1:
		return
	_map.erase_cell(1, cell)
	_map.erase_cell(_WorldMap.GROUND_DECOR_LAYER, cell)
	_map.set_cell(1, cell, TileCatalog.SOURCE_ID, atlas)


func can_place(structure: Structure, anchor_cell: Vector2i) -> Array[String]:
	## Why `structure` cannot go with its anchor on `anchor_cell`; empty when
	## it can. Each reason appears once, in the order of the constants above.
	## Read from predict_cell, so it works on cells not drawn yet.
	var found := {}
	if Interaction.multiplayer_on(_map.multiplayer):
		found[MULTIPLAYER_ON] = true
	for cell: Vector2i in footprint(structure, anchor_cell):
		var p: Array = _map.predict_cell(cell)
		if not _map.ground_is_walkable(p[0]) or _map.has_bridge(cell):
			found[WATER] = true
		elif p[1] == TileCatalog.TREE or p[1] == TileCatalog.TREE_BUSHY or p[1] == TileCatalog.PINE:
			found[TREE] = true
		elif p[1] == TileCatalog.BUSH:
			found[BUSH] = true
		if _outside_world(cell):
			found[OUT_OF_MAP] = true
		if _cells.has(cell):
			found[OVERLAPS_STRUCTURE] = true
		if _map.player_on_cell(cell):
			found[OVERLAPS_PLAYER] = true
		if _map.mob_on_cell(cell):
			found[OVERLAPS_MOB] = true
	var out: Array[String] = []
	for reason in [WATER, TREE, BUSH, OUT_OF_MAP, OVERLAPS_STRUCTURE, OVERLAPS_PLAYER, OVERLAPS_MOB, MULTIPLAYER_ON]:
		if found.has(reason):
			out.append(reason)
	return out


func place(structure: Structure, anchor_cell: Vector2i, owner: int) -> int:
	## Write `structure` with its anchor on `anchor_cell` for peer `owner`:
	## ground cells, then object cells. Auto walls and tower rings are solved
	## with every other wall (an `open` gate drawn open). The owner's flag
	## colour is applied. Plants, decor and stumps under it are removed.
	## Returns the new placement id, or -1 and nothing written when can_place
	## gives any reason.
	if not can_place(structure, anchor_cell).is_empty():
		return -1
	return _write(structure, anchor_cell, owner)


func place_from_host(structure: Structure, anchor_cell: Vector2i, owner: int) -> int:
	## The host already decided this placement (#497). Same footprint rules
	## as can_place, without the multiplayer refuse a client still gets from
	## can_place. Returns the new id, or -1 when the footprint is refused.
	var why: Array[String] = []
	for reason in can_place(structure, anchor_cell):
		if reason != MULTIPLAYER_ON:
			why.append(reason)
	if not why.is_empty():
		return -1
	return _write(structure, anchor_cell, owner)


func to_sync() -> Array:
	## The placements in id order as [name, owner, anchor], the list the host
	## sends a joining peer with the map.
	var out := []
	var ids := _placed.keys()
	ids.sort()
	for id in ids:
		out.append([_placed[id]["name"], _placed[id]["owner"], _placed[id]["anchor"]])
	return out


func replace_from_host(list: Array) -> int:
	## Client: make the placements exactly the host's `list` (to_sync), in
	## its order, so ids match. Call it right after the params are applied,
	## before the chunks are drawn again. The host checked each placement, so
	## can_place is not asked (it refuses while multiplayer is on). An entry
	## of the wrong shape, or naming no shipped structure file, is skipped.
	## Returns how many placements it holds.
	clear()
	for entry in list:
		if not entry is Array or entry.size() != 3 or not entry[0] is String \
				or not entry[1] is int or not entry[2] is Vector2i:
			continue
		var structure := load_named(entry[0])
		if structure != null:
			_write(structure, entry[2], entry[1])
	return _placed.size()


static func load_named(structure_name: String) -> Structure:
	## The shipped structure file `structure_name` (res://structures/NAME.txt),
	## or null when the name is not one.
	var path := "%s/%s.txt" % [DIR, structure_name]
	if RegEx.create_from_string("^[a-z0-9_]+$").search(structure_name) == null or not FileAccess.file_exists(path):
		return null
	return Structure.parse(FileAccess.get_file_as_string(path))["structure"]


func _write(structure: Structure, anchor_cell: Vector2i, owner: int) -> int:
	var foot := footprint(structure, anchor_cell)
	var flags: Array[Vector2i] = []
	for cell: Vector2i in foot:
		var g: Dictionary = foot[cell][0]
		var o: Dictionary = foot[cell][1]
		var ground := _WorldMap.NO_PLANT if g.is_empty() else _atlas(g["tile"])
		var object := _WorldMap.NO_PLANT
		if not o.is_empty():
			var tile: String = o["tile"]
			var attrs: PackedStringArray = o["attributes"]
			if "auto" in attrs and _remember_auto(structure, anchor_cell, cell, tile, attrs):
				pass
			else:
				if "team" in attrs and tile.begins_with("PROP_FLAG_"):
					tile = OWNER_FLAGS.get(owner, OTHER_OWNER_FLAG)
					flags.append(cell)
				object = _atlas(tile)
		_cells[cell] = [ground, object]
		_map.forget_cut(cell)
		_map._predict_cache.erase(cell)
		if _map.get_cell_source_id(0, cell) == -1:
			continue  # not drawn yet: generate_chunk draws it
		if ground != _WorldMap.NO_PLANT:
			_map.set_cell(0, cell, TileCatalog.SOURCE_ID, ground)
		_map.erase_cell(1, cell)
		_map.erase_cell(_WorldMap.GROUND_DECOR_LAYER, cell)
		if object != _WorldMap.NO_PLANT:
			_map.set_cell(1, cell, TileCatalog.SOURCE_ID, object)
	var id := _next_id
	_next_id += 1
	_placed[id] = {"name": structure.name, "owner": owner, "anchor": anchor_cell}
	if not flags.is_empty():
		_flags[id] = flags
	_map._walls.resolve()
	_map.ground_changed.emit(Rect2i(anchor_cell - structure.anchor, structure.size))
	return id


func _remember_auto(structure: Structure, anchor_cell: Vector2i, cell: Vector2i, tile: String, attrs: PackedStringArray) -> bool:
	## Record a solved wall or tower ring. False when `tile` is neither.
	if tile.begins_with("TOWER_"):
		var ring := WallSolver.ring_at(cell - anchor_cell + structure.anchor)
		if ring == "":
			return false
		_auto[cell] = {"family": WallSolver.TOWER, "ring": ring}
		return true
	if tile.begins_with("WALL_"):
		_auto[cell] = {
			"family": WallSolver.STONE,
			"gate": tile.contains("GATE"),
			"open": "open" in attrs,
		}
		return true
	return false


func towers() -> Dictionary:
	## Placement id -> its `team` flag cells, for placements that have one.
	return _flags.duplicate(true)


func owner_of(id: int) -> int:
	## Placement `id`'s owner peer (or OWNER_NEUTRAL / OWNER_MOBS), or 0 when
	## there is no such placement. Read-only; no copy of the placements dict.
	return _placed[id]["owner"] if _placed.has(id) else 0


func set_owner(id: int, owner: int) -> void:
	## Hand placement `id` to `owner` (a captured tower, #274): its owner
	## entry and its flag cells' colour change, nothing else.
	if not _placed.has(id):
		return
	_placed[id]["owner"] = owner
	var flag := _atlas(OWNER_FLAGS.get(owner, OTHER_OWNER_FLAG))
	for cell: Vector2i in _flags.get(id, []):
		_cells[cell][1] = flag
		_map._predict_cache.erase(cell)
		if _map.get_cell_source_id(1, cell) != -1:
			_map.set_cell(1, cell, TileCatalog.SOURCE_ID, flag)


static func footprint(structure: Structure, anchor_cell: Vector2i) -> Dictionary:
	## Map cell -> [ground legend entry, object legend entry] ({} for '.')
	## for every grid cell with something on either layer.
	var out := {}
	for y in structure.size.y:
		for x in structure.size.x:
			var g: String = structure.layers["ground"][y][x]
			var o: String = structure.layers["object"][y][x]
			if g == Structure.EMPTY and o == Structure.EMPTY:
				continue
			out[anchor_cell + Vector2i(x, y) - structure.anchor] = [
				structure.legend.get(g, {}), structure.legend.get(o, {})]
	return out


func _outside_world(cell: Vector2i) -> bool:
	## Past the archipelago world bound, when the map has one.
	var e := _map.archipelago_world_extent
	return _map.archipelago_spacing > 0 and e > 0 and (absi(cell.x) > e or absi(cell.y) > e)


static func _atlas(tile: String) -> Vector2i:
	return TileCatalog.TILES[tile]["atlas"]
