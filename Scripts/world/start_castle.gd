class_name StartCastle
extends RefCounted
## The castle each player starts with (#271): structures/castle.txt placed
## next to the player spawn so the player starts on the land outside its
## gate. The castle's anchor is its gate, in the bottom wall. Placed by the
## host while alone; joining peers get it with the map (StructurePlacer, #278).

const _WorldMap := preload("res://Scripts/TileMap.gd")

const PATH := "res://structures/castle.txt"
## The cell outside the gate, from the gate (the anchor).
const GATE_FRONT := Vector2i(0, 1)
## Furthest the gate front may be from the spawn, in cells along x or y.
const SEARCH_RADIUS := 32


static func structure() -> Structure:
	return Structure.parse(FileAccess.get_file_as_string(PATH))["structure"]


static func place(map: _WorldMap, owner: int) -> Variant:
	## Place the castle for peer `owner` at the spot find_anchor picks from
	## the map's spawn. Returns the gate front cell, or null and nothing
	## placed when no spot fits.
	var castle := structure()
	var anchor: Variant = find_anchor(map, castle, SpawnFinder.resolve_player_spawn(map))
	if anchor == null or map.place_structure(castle, anchor, owner) <= 0:
		return null
	return anchor + GATE_FRONT


static func find_anchor(map: _WorldMap, castle: Structure, origin: Vector2i) -> Variant:
	## The castle anchor whose gate front is nearest `origin` (ties by y,
	## then x) where can_place gives no reason and the gate front is clear
	## ground that reaches SPAWN_MIN_REACHABLE clear cells around the
	## castle; null when none is within SEARCH_RADIUS.
	var fronts: Array[Vector2i] = []
	for y in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for x in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			fronts.append(origin + Vector2i(x, y))
	fronts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - origin).length_squared()
		var db := (b - origin).length_squared()
		if da != db:
			return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for front in fronts:
		var anchor := front - GATE_FRONT
		if not map.predicted_clear(front) or not map.can_place_structure(castle, anchor).is_empty():
			continue
		var foot := StructurePlacer.footprint(castle, anchor)
		if SpawnFinder.reachable_clear_cells(map, front, SpawnFinder.SPAWN_MIN_REACHABLE, foot).size() >= SpawnFinder.SPAWN_MIN_REACHABLE:
			return anchor
	return null
