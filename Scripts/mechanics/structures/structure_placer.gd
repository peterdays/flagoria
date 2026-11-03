class_name StructurePlacer
extends RefCounted
## Structures placed on the world map (#270): the footprint check, writing
## the cells, and the list of placements. The map keeps wrappers
## (can_place_structure, place_structure, placed_structures) and asks
## has_cell / ground_at / object_at when it draws or predicts a cell.
## Host-alone only for now: while multiplayer is on nothing is placed; peer
## sync comes with #278.

const _WorldMap := preload("res://Scripts/TileMap.gd")

const WATER := "water"
const TREE := "tree"
const BUSH := "bush"
const OUT_OF_MAP := "out of map"
const OVERLAPS_STRUCTURE := "overlaps another structure"
const OVERLAPS_PLAYER := "overlaps a player"
const MULTIPLAYER_ON := "multiplayer on"
## Owner peer id -> flag tile for `team` legend entries. The host is blue and
## every other owner red until more owner colours exist (#274).
const OWNER_FLAGS := {1: "PROP_FLAG_BLUE"}
const OTHER_OWNER_FLAG := "PROP_FLAG_RED"

## Placed cell -> [layer-0 atlas or NO_PLANT to keep the generated ground,
## layer-1 atlas or NO_PLANT for none]. generate_chunk draws these instead
## of the generated cell; a new map clears them.
var _cells: Dictionary = {}
## Placement id -> {"name", "owner", "anchor"} (for saves, #42).
var _placed: Dictionary = {}
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
	_placed.clear()
	_next_id = 1


func can_place(structure: Structure, anchor_cell: Vector2i) -> Array[String]:
	## Why `structure` cannot go with its anchor on `anchor_cell`; empty when
	## it can. Each reason appears once, in the order of the constants above.
	## Read from predict_cell, so it works on cells not drawn yet.
	var found := {}
	if Interaction.multiplayer_on(_map.multiplayer):
		found[MULTIPLAYER_ON] = true
	for cell: Vector2i in footprint(structure, anchor_cell):
		var p: Array = _map.predict_cell(cell)
		if not _map.ground_is_walkable(p[0]) or _map._bridges.has_bridge(cell):
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
	var out: Array[String] = []
	for reason in [WATER, TREE, BUSH, OUT_OF_MAP, OVERLAPS_STRUCTURE, OVERLAPS_PLAYER, MULTIPLAYER_ON]:
		if found.has(reason):
			out.append(reason)
	return out


func place(structure: Structure, anchor_cell: Vector2i, owner: int) -> int:
	## Write `structure` with its anchor on `anchor_cell` for peer `owner`:
	## ground cells, then object cells with wall and gate pieces from
	## WallSolver and the owner's flag colour. Plants, decor and stumps
	## under it are removed. Returns the new placement id, or -1 and
	## nothing written when can_place gives any reason.
	if not can_place(structure, anchor_cell).is_empty():
		return -1
	var foot := footprint(structure, anchor_cell)
	var walls := {}
	for cell: Vector2i in foot:
		var o: Dictionary = foot[cell][1]
		if not o.is_empty() and o["tile"].begins_with("WALL_"):
			walls[cell] = {"gate": o["tile"].contains("GATE")}
	var solved := WallSolver.solve(walls)
	for cell: Vector2i in foot:
		var g: Dictionary = foot[cell][0]
		var o: Dictionary = foot[cell][1]
		var ground := _WorldMap.NO_PLANT if g.is_empty() else _atlas(g["tile"])
		var object := _WorldMap.NO_PLANT
		if not o.is_empty():
			var tile: String = o["tile"]
			if "auto" in o["attributes"] and solved.has(cell):
				tile = solved[cell]
			if "team" in o["attributes"] and tile.begins_with("PROP_FLAG_"):
				tile = OWNER_FLAGS.get(owner, OTHER_OWNER_FLAG)
			object = _atlas(tile)
		_cells[cell] = [ground, object]
		_map._tree_cuts.forget(cell)
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
	_map.ground_changed.emit(Rect2i(anchor_cell - structure.anchor, structure.size))
	return id


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
