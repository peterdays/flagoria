class_name SpawnFinder
extends RefCounted
## Player spawn search on the world map (Scripts/TileMap.gd): a spawn cell the
## player can walk away from, and free spots around it so players never stand
## on one another. Every function takes the map it searches.

const _WorldMap := preload("res://Scripts/TileMap.gd")

const SPAWN_NEIGHBORS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
# Player moves between cells by 4-neighbour steps.
const SPAWN_STEPS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
# A spawn must reach at least this many clear-ground cells on foot.
const SPAWN_MIN_REACHABLE := 200
## Players spawn and respawn at a free spot at most this far (px) from the
## spawn point, so several of them never stand on one another. 64 px is four
## 16 px tiles: room for dozens of players, all on screen around the spawn.
const SPAWN_RADIUS := 64.0
# Two players closer than this (px, centre to centre) would touch; one tile
# apart keeps their 8 x 10 bodies from overlapping.
const SPAWN_CLEARANCE := 16.0
# Clear cells walked from the spawn point when looking for a free spot, at
# least (more when many players stand around it, see free_spawn_position).
const SPAWN_SEARCH_LIMIT := 400


static func count_walkable_neighbors(map: _WorldMap, cell: Vector2i) -> int:
	var n := 0
	for d in SPAWN_NEIGHBORS:
		if map.is_walkable_land(cell + d):
			n += 1
	return n


static func reachable_clear_cells(map: _WorldMap, start: Vector2i, limit: int = SPAWN_MIN_REACHABLE) -> Array[Vector2i]:
	## Clear-ground cells reachable from start by 4-neighbour steps, start
	## included, in flood order. Stops once limit cells are found.
	var found: Array[Vector2i] = []
	if not map.is_clear_ground(start):
		return found
	var seen := {start: true}
	found.append(start)
	var head := 0
	while head < found.size() and found.size() < limit:
		var current: Vector2i = found[head]
		head += 1
		for d in SPAWN_STEPS:
			var next: Vector2i = current + d
			if seen.has(next):
				continue
			seen[next] = true
			if map.is_clear_ground(next):
				found.append(next)
				if found.size() >= limit:
					break
	return found


static func resolve_player_spawn(map: _WorldMap, origin_cell: Vector2i = Vector2i(0, 0), max_radius: int = 96) -> Vector2i:
	## Nearest clear-ground cell to origin_cell (ring order) from which the
	## player can walk to at least SPAWN_MIN_REACHABLE clear cells. If none is
	## within max_radius, the candidate with the largest reachable area; if no
	## clear cell at all, origin_cell.
	var best := origin_cell
	var best_size := 0
	# Cells of areas already measured as too small, so each is flooded once.
	var small_area := {}
	var visited := {origin_cell: true}
	var queue: Array[Vector2i] = [origin_cell]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if not small_area.has(cell) and map.is_clear_ground(cell):
			var area := reachable_clear_cells(map, cell)
			if area.size() >= SPAWN_MIN_REACHABLE:
				map.spawn_point = cell
				return cell
			for c in area:
				small_area[c] = true
			if area.size() > best_size:
				best_size = area.size()
				best = cell
		for d in SPAWN_NEIGHBORS:
			var next: Vector2i = cell + d
			if visited.has(next):
				continue
			if absi(next.x - origin_cell.x) > max_radius or absi(next.y - origin_cell.y) > max_radius:
				continue
			visited[next] = true
			queue.append(next)

	map.spawn_point = best
	return best


static func spawn_spots(map: _WorldMap, origin_cell: Vector2i, limit: int = SPAWN_SEARCH_LIMIT) -> Array[Vector2]:
	## Centres of up to limit clear cells a player can walk to from
	## origin_cell, nearest first (ties by y, then x), so every peer gets the
	## same order.
	var origin := map.map_to_local(origin_cell)
	var spots: Array[Vector2] = []
	for cell in reachable_clear_cells(map, origin_cell, limit):
		spots.append(map.map_to_local(cell))
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da := a.distance_squared_to(origin)
		var db := b.distance_squared_to(origin)
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	return spots


static func free_spawn_position(map: _WorldMap, origin_cell: Vector2i, taken: Array[Vector2]) -> Vector2:
	## The nearest spot to origin_cell clear of every position in taken. That
	## is within SPAWN_RADIUS unless the area is full; then the nearest free
	## spot further out. One position blocks at most per_taken cell centres,
	## so the search walks enough cells that taken cannot cover them all.
	## Only when all the ground reachable from origin_cell is taken does it
	## fall back to origin_cell itself.
	var span := 2 * ceili(SPAWN_CLEARANCE / map.tile_set.tile_size.x) + 1
	var per_taken := span * span
	for spot in spawn_spots(map, origin_cell, maxi(SPAWN_SEARCH_LIMIT, per_taken * taken.size() + 1)):
		if _clear_of(spot, taken):
			return spot
	return map.map_to_local(origin_cell)


static func _clear_of(at: Vector2, taken: Array[Vector2]) -> bool:
	for other in taken:
		if at.distance_to(other) < SPAWN_CLEARANCE:
			return false
	return true
