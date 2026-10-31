class_name TerrainShape
extends RefCounted
## Altitude shaping for the world map (Scripts/TileMap.gd): altitude noise,
## the biome bias, one island around the origin and the archipelago squares.
## The map owns the noise and the Map Settings values; this reads them from
## the map it was made for and keeps the archipelago square cache.

const _WorldMap := preload("res://Scripts/TileMap.gd")

# Kept Vector2i squares when archipelago_island_count > 0.
var _archipelago_active_squares: Dictionary = {}
var _archipelago_count_limited: bool = false
var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func cell_altitude(cell: Vector2i, biome_id: int) -> float:
	## Final altitude at a cell: noise, biome bias (biomes on), island and
	## archipelago shaping. generate_chunk and tools/render_biomes.gd share it.
	var alt := _map.altitude.get_noise_2d(cell.x, cell.y)
	if _map.biome_frequency > 0.0:
		alt += BiomeCatalog.altitude_bias(biome_id)
	return archipelago_altitude(cell, island_altitude(cell, alt))


func island_altitude(cell: Vector2i, alt: float) -> float:
	## Add island_falloff * (1 - (distance / island_radius)^2): cells near the
	## origin are raised into land, the radius is unchanged, cells beyond it sink.
	if _map.island_radius <= 0:
		return alt
	var d := Vector2(cell).length() / float(_map.island_radius)
	return alt + _map.island_falloff * (1.0 - d * d)


func archipelago_altitude(cell: Vector2i, alt: float) -> float:
	## Add island_falloff * (1 - (distance / archipelago_island_radius)^2), where
	## distance is to the nearest active archipelago centre, so every active
	## square of archipelago_spacing tiles gets its own island with sea between.
	## With archipelago_island_count set, each kept square only uses its own
	## centre and its first row and column are sea, so islands never merge;
	## dropped squares are all sea.
	if _map.archipelago_spacing <= 0:
		return alt
	var square := Vector2i(floori(float(cell.x) / _map.archipelago_spacing), floori(float(cell.y) / _map.archipelago_spacing))
	if _archipelago_count_limited:
		var local := cell - square * _map.archipelago_spacing
		if not _archipelago_active_squares.has(square) or local.x == 0 or local.y == 0:
			return _map.water_max_alt - 1.0
		var own := Vector2(cell).distance_to(archipelago_centre(square)) / float(_map.archipelago_island_radius)
		return alt + _map.island_falloff * (1.0 - own * own)
	var nearest := INF
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var sq := square + Vector2i(dx, dy)
			if not archipelago_square_active(sq):
				continue
			var centre := archipelago_centre(sq)
			nearest = minf(nearest, Vector2(cell).distance_to(centre))
	if nearest == INF:
		return alt
	var d := nearest / float(_map.archipelago_island_radius)
	return alt + _map.island_falloff * (1.0 - d * d)


func archipelago_centre(square: Vector2i) -> Vector2:
	## Centre of the island in grid square `square`: the square's middle, moved
	## by a per-square offset that depends only on the square and the altitude seed.
	var h: int = hash(Vector3i(square.x, square.y, _map.archipelago_seed))
	var offset := Vector2(float(h & 0xFFFF) / 65535.0, float((h >> 16) & 0xFFFF) / 65535.0) * 2.0 - Vector2.ONE
	var half := _map.archipelago_spacing * 0.5
	return (Vector2(square) + Vector2(0.5, 0.5)) * _map.archipelago_spacing + offset * _map.archipelago_jitter * half


func archipelago_square_active(square: Vector2i) -> bool:
	## True when this spacing square contributes an island centre.
	if _map.archipelago_spacing <= 0:
		return false
	if _archipelago_count_limited:
		return _archipelago_active_squares.has(square)
	if _map.archipelago_world_extent > 0 and not _archipelago_square_intersects_extent(square):
		return false
	# Spawn square always stays active.
	if square == Vector2i.ZERO:
		return true
	if _map.biome_frequency > 0.0:
		return _archipelago_square_kept_by_biome(square)
	return true


func _archipelago_square_kept_by_biome(square: Vector2i) -> bool:
	## Keep the square when a deterministic hash falls under that biome's density.
	var half := int(_map.archipelago_spacing / 2)
	var centre_cell := square * _map.archipelago_spacing + Vector2i(half, half)
	var dens := BiomeCatalog.density(_map.biome_at(centre_cell))
	if dens >= 1.0:
		return true
	var h: int = hash(Vector3i(square.x, square.y, _map.biome_seed))
	var frac := float(h & 0xFFFF) / 65535.0
	return frac < dens


func _archipelago_square_intersects_extent(square: Vector2i) -> bool:
	## Grid square [sx*S, (sx+1)*S) x [sy*S, (sy+1)*S) overlaps [-E, E]^2.
	var s := _map.archipelago_spacing
	var e := _map.archipelago_world_extent
	var min_x := square.x * s
	var max_x := (square.x + 1) * s - 1
	var min_y := square.y * s
	var max_y := (square.y + 1) * s - 1
	return min_x <= e and max_x >= -e and min_y <= e and max_y >= -e


func _rebuild_archipelago_active_squares() -> void:
	## Cache the kept squares when archipelago_island_count is set. Candidates
	## are the squares inside archipelago_world_extent, or a box around the
	## origin big enough for the count when the extent is 0. The spawn square
	## (0, 0) is always kept; the rest are taken nearest-first.
	_archipelago_active_squares.clear()
	_archipelago_count_limited = false
	if _map.archipelago_spacing <= 0 or _map.archipelago_island_count <= 0:
		return
	_archipelago_count_limited = true
	var lo: int
	var hi: int
	if _map.archipelago_world_extent > 0:
		lo = floori(float(-_map.archipelago_world_extent) / _map.archipelago_spacing) - 1
		hi = floori(float(_map.archipelago_world_extent) / _map.archipelago_spacing) + 1
	else:
		hi = ceili(sqrt(float(_map.archipelago_island_count))) + 1
		lo = -hi
	var candidates: Array[Vector2i] = []
	for sx in range(lo, hi + 1):
		for sy in range(lo, hi + 1):
			var sq := Vector2i(sx, sy)
			if sq == Vector2i.ZERO:
				continue
			if _map.archipelago_world_extent <= 0 or _archipelago_square_intersects_extent(sq):
				candidates.append(sq)
	candidates.sort_custom(_archipelago_square_closer)
	_archipelago_active_squares[Vector2i.ZERO] = true
	for i in range(mini(_map.archipelago_island_count - 1, candidates.size())):
		_archipelago_active_squares[candidates[i]] = true


func _archipelago_square_closer(a: Vector2i, b: Vector2i) -> bool:
	## Sort key: square centre distance to origin, then hash for ties.
	var da := ((Vector2(a) + Vector2(0.5, 0.5)) * float(_map.archipelago_spacing)).length_squared()
	var db := ((Vector2(b) + Vector2(0.5, 0.5)) * float(_map.archipelago_spacing)).length_squared()
	if da != db:
		return da < db
	var ha: int = hash(Vector3i(a.x, a.y, _map.archipelago_seed))
	var hb: int = hash(Vector3i(b.x, b.y, _map.archipelago_seed))
	return ha < hb
