class_name StartCastle
extends RefCounted
## The castle each player starts with (#271): structures/castle.txt placed
## next to the player spawn so the player starts on the land outside its
## gate. The castle's anchor is its gate, in the bottom wall. The host's
## castle is placed while it is still alone. A joining peer's castle is
## placed by the host outside the shared spawn disk and sent to every peer
## (StructurePlacer, #278). Players still spawn beside the host's gate.

const _WorldMap := preload("res://Scripts/TileMap.gd")

const PATH := "res://structures/castle.txt"
## The cell outside the gate, from the gate (the anchor).
const GATE_FRONT := Vector2i(0, 1)
## Furthest the gate front may be from the spawn, in cells along x or y.
const SEARCH_RADIUS := 48
## A later castle's footprint stays this many cells (chebyshev) off the
## shared spawn, so players still fit inside SPAWN_RADIUS of that spawn.
const SPAWN_KEEP := 6


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


static func place_for_peer(map: _WorldMap, owner: int) -> Variant:
	## Place `owner`'s castle outside the shared spawn disk. Returns the
	## anchor, or null when this peer already has a castle or none fits.
	## Does not move the spawn: players still gather at the host's gate.
	var castle := structure()
	for entry in map.placed_structures().values():
		if str(entry["name"]) == castle.name and int(entry["owner"]) == owner:
			return null
	var origin: Vector2i = map.resolve_player_spawn()
	var anchor: Variant = find_anchor(map, castle, origin, SPAWN_KEEP)
	if anchor == null or map._structures.place_from_host(castle, anchor, owner) <= 0:
		return null
	return anchor


static func find_anchor(map: _WorldMap, castle: Structure, origin: Vector2i, keep := -1) -> Variant:
	## The castle anchor whose gate front is nearest `origin` (ties by y,
	## then x) where can_place gives no reason and the gate front is clear
	## ground that reaches SPAWN_MIN_REACHABLE clear cells around the
	## castle; null when none is within SEARCH_RADIUS. `keep` >= 0 is the
	## host placing a later castle: skip the multiplayer refuse, and skip a
	## footprint that comes within `keep` cells of `origin`. The ring walk
	## rejects terrain before it measures players and mobs, so a join does
	## not stall long enough to drop the peer.
	if keep >= 0:
		return _find_outside(map, castle, origin, keep)
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
		if _fits(map, castle, front, false):
			return front - GATE_FRONT
	return null


static func _find_outside(map: _WorldMap, castle: Structure, origin: Vector2i, keep: int) -> Variant:
	## Nearer rings first, every front, so a spot the full grid would accept
	## is still accepted. The actor check stays off until the terrain fits.
	var reach := _front_reach(castle)
	for dist in range(keep + 1, SEARCH_RADIUS + 1):
		for front in _ring(origin, dist, 1):
			if _front_too_close(front, origin, keep, reach) \
					and _covers_spawn(castle, front - GATE_FRONT, origin, keep):
				continue
			if _fits(map, castle, front, true):
				return front - GATE_FRONT
	return null


static func _ring(origin: Vector2i, dist: int, step: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if dist == 0:
		out.append(origin)
		return out
	for x in range(-dist, dist + 1, step):
		out.append(origin + Vector2i(x, -dist))
		out.append(origin + Vector2i(x, dist))
	for y in range(-dist + step, dist, step):
		out.append(origin + Vector2i(-dist, y))
		out.append(origin + Vector2i(dist, y))
	return out


static func _fits(map: _WorldMap, castle: Structure, front: Vector2i, from_host: bool) -> bool:
	var anchor := front - GATE_FRONT
	if not map.predicted_clear(front) \
			or not map._structures.can_place(castle, anchor, 0, from_host, false).is_empty():
		return false
	if not map._structures.can_place(castle, anchor, 0, from_host).is_empty():
		return false
	var foot := StructurePlacer.footprint(castle, anchor)
	return SpawnFinder.reachable_clear_cells(map, front, SpawnFinder.SPAWN_MIN_REACHABLE, foot).size() >= SpawnFinder.SPAWN_MIN_REACHABLE


static func _front_reach(castle: Structure) -> int:
	## How far a footprint cell can sit from the gate front, in chebyshev cells.
	var reach := 0
	for cell: Vector2i in StructurePlacer.footprint(castle, Vector2i.ZERO):
		var from_front: Vector2i = cell - GATE_FRONT
		reach = maxi(reach, maxi(absi(from_front.x), absi(from_front.y)))
	return reach


static func _front_too_close(front: Vector2i, origin: Vector2i, keep: int, reach: int) -> bool:
	var d: Vector2i = front - origin
	return maxi(absi(d.x), absi(d.y)) <= keep + reach


static func _covers_spawn(castle: Structure, anchor: Vector2i, origin: Vector2i, keep: int) -> bool:
	for cell: Vector2i in StructurePlacer.footprint(castle, anchor):
		var d: Vector2i = cell - origin
		if maxi(absi(d.x), absi(d.y)) <= keep:
			return true
	return false
