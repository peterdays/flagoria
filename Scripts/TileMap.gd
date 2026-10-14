extends TileMap

var rng = RandomNumberGenerator.new()
var count = 0
var moisture = FastNoiseLite.new()
var temperature = FastNoiseLite.new()
var altitude = FastNoiseLite.new()
var items_chance = FastNoiseLite.new()
var chunk_width: int = 32
var chunk_height: int = 32
var chunk_refresh_frames: int = 15
var player_spawned = false
var spawn_point = Vector2i(0, 0)

# Cached thresholds from MapGenParams (defaults match prior hardcoded values)
var water_max_alt: float = 0.2
var sand_max_alt: float = 0.25
var swamp_special_alt: float = 0.26
var island_radius: int = 0
var island_falloff: float = 1.0
var archipelago_spacing: int = 0
var archipelago_island_radius: int = 24
var archipelago_jitter: float = 0.5
var archipelago_seed: int = 0
var archipelago_world_extent: int = 0
var archipelago_island_count: int = 0
# Kept Vector2i squares when archipelago_island_count > 0.
var _archipelago_active_squares: Dictionary = {}
var _archipelago_count_limited: bool = false
var ground_chance_a: float = -0.25
var ground_chance_b: float = 0.25
var ground_chance_c: float = 0.75
var bush_min_alt: float = 0.3
var bush_max_alt: float = 0.4
var bush_min_chance: float = 0.0
var tree_min_alt: float = 0.4
var tree_min_chance: float = 0.3
var flower_min_alt: float = 0.25
var flower_max_alt: float = 0.3
var flower_min_chance: float = 0.3

const SPAWN_NEIGHBORS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


func _ready():
	apply_map_params(get_node("/root/MapGen").params)


func apply_map_params(p: MapGenParams) -> void:
	## Apply the full parameter set and clear existing tiles so the next chunk regen is clean.
	var working = p.duplicate_params()
	working.ensure_seeds()

	_configure_noise(altitude, working.altitude_seed, working.altitude_frequency, working)
	_configure_noise(moisture, working.moisture_seed, working.moisture_frequency, working)
	_configure_noise(temperature, working.temperature_seed, working.temperature_frequency, working)
	_configure_noise(items_chance, working.items_seed, working.items_frequency, working)

	chunk_width = working.chunk_width
	chunk_height = working.chunk_height
	chunk_refresh_frames = maxi(1, working.chunk_refresh_frames)
	water_max_alt = working.water_max_alt
	sand_max_alt = working.sand_max_alt
	swamp_special_alt = working.swamp_special_alt
	island_radius = working.island_radius
	island_falloff = working.island_falloff
	archipelago_spacing = working.archipelago_spacing
	archipelago_island_radius = maxi(1, working.archipelago_island_radius)
	archipelago_jitter = working.archipelago_jitter
	archipelago_seed = working.altitude_seed
	archipelago_world_extent = maxi(0, working.archipelago_world_extent)
	archipelago_island_count = maxi(0, working.archipelago_island_count)
	_rebuild_archipelago_active_squares()
	ground_chance_a = working.ground_chance_a
	ground_chance_b = working.ground_chance_b
	ground_chance_c = working.ground_chance_c
	bush_min_alt = working.bush_min_alt
	bush_max_alt = working.bush_max_alt
	bush_min_chance = working.bush_min_chance
	tree_min_alt = working.tree_min_alt
	tree_min_chance = working.tree_min_chance
	flower_min_alt = working.flower_min_alt
	flower_max_alt = working.flower_max_alt
	flower_min_chance = working.flower_min_chance

	clear()
	spawn_point = Vector2i(0, 0)


func _configure_noise(noise: FastNoiseLite, seed_value: int, frequency: float, p: MapGenParams) -> void:
	noise.seed = seed_value
	noise.noise_type = p.noise_type
	noise.frequency = frequency
	noise.fractal_octaves = p.fractal_octaves
	noise.fractal_lacunarity = p.fractal_lacunarity
	noise.fractal_gain = p.fractal_gain


func _process(_delta):
	count += 1
	if (count % chunk_refresh_frames) == 0 and player_spawned:
		var current_player_id = str(multiplayer.get_unique_id())
		count = 0

		var curr_player = get_node_or_null("/root/Flagoria/World/" + str(current_player_id))
		if curr_player:
			generate_chunk(curr_player.position)


func generate_chunk(position):
	var tile_pos = local_to_map(position)
	for x in range(chunk_width):
		for y in range(chunk_height):
			var new_x = tile_pos.x - chunk_width / 2 + x
			var new_y = tile_pos.y - chunk_height / 2 + y
			var moist = moisture.get_noise_2d(new_x, new_y)
			var temp = temperature.get_noise_2d(new_x, new_y)
			var cell := Vector2i(new_x, new_y)
			var alt = archipelago_altitude(cell, island_altitude(cell, altitude.get_noise_2d(new_x, new_y)))
			var chance = items_chance.get_noise_2d(new_x, new_y)

			set_tile_type_z0(Vector2i(new_x, new_y), alt, moist, temp, chance)
			set_tile_type_z1(Vector2i(new_x, new_y), alt, moist, temp, chance)


func island_altitude(cell: Vector2i, alt: float) -> float:
	## Add island_falloff * (1 - (distance / island_radius)^2): cells near the
	## origin are raised into land, the radius is unchanged, cells beyond it sink.
	if island_radius <= 0:
		return alt
	var d := Vector2(cell).length() / float(island_radius)
	return alt + island_falloff * (1.0 - d * d)


func archipelago_altitude(cell: Vector2i, alt: float) -> float:
	## Add island_falloff * (1 - (distance / archipelago_island_radius)^2), where
	## distance is to the nearest active archipelago centre, so every active
	## square of archipelago_spacing tiles gets its own island with sea between.
	## With archipelago_island_count set, each kept square only uses its own
	## centre and its first row and column are sea, so islands never merge;
	## dropped squares are all sea.
	if archipelago_spacing <= 0:
		return alt
	var square := Vector2i(floori(float(cell.x) / archipelago_spacing), floori(float(cell.y) / archipelago_spacing))
	if _archipelago_count_limited:
		var local := cell - square * archipelago_spacing
		if not _archipelago_active_squares.has(square) or local.x == 0 or local.y == 0:
			return water_max_alt - 1.0
		var own := Vector2(cell).distance_to(archipelago_centre(square)) / float(archipelago_island_radius)
		return alt + island_falloff * (1.0 - own * own)
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
	var d := nearest / float(archipelago_island_radius)
	return alt + island_falloff * (1.0 - d * d)


func archipelago_centre(square: Vector2i) -> Vector2:
	## Centre of the island in grid square `square`: the square's middle, moved
	## by a per-square offset that depends only on the square and the altitude seed.
	var h: int = hash(Vector3i(square.x, square.y, archipelago_seed))
	var offset := Vector2(float(h & 0xFFFF) / 65535.0, float((h >> 16) & 0xFFFF) / 65535.0) * 2.0 - Vector2.ONE
	var half := archipelago_spacing * 0.5
	return (Vector2(square) + Vector2(0.5, 0.5)) * archipelago_spacing + offset * archipelago_jitter * half


func archipelago_square_active(square: Vector2i) -> bool:
	## True when this spacing square contributes an island centre.
	if archipelago_spacing <= 0:
		return false
	if _archipelago_count_limited:
		return _archipelago_active_squares.has(square)
	if archipelago_world_extent <= 0:
		return true
	return _archipelago_square_intersects_extent(square)


func _archipelago_square_intersects_extent(square: Vector2i) -> bool:
	## Grid square [sx*S, (sx+1)*S) x [sy*S, (sy+1)*S) overlaps [-E, E]^2.
	var s := archipelago_spacing
	var e := archipelago_world_extent
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
	if archipelago_spacing <= 0 or archipelago_island_count <= 0:
		return
	_archipelago_count_limited = true
	var lo: int
	var hi: int
	if archipelago_world_extent > 0:
		lo = floori(float(-archipelago_world_extent) / archipelago_spacing) - 1
		hi = floori(float(archipelago_world_extent) / archipelago_spacing) + 1
	else:
		hi = ceili(sqrt(float(archipelago_island_count))) + 1
		lo = -hi
	var candidates: Array[Vector2i] = []
	for sx in range(lo, hi + 1):
		for sy in range(lo, hi + 1):
			var sq := Vector2i(sx, sy)
			if sq == Vector2i.ZERO:
				continue
			if archipelago_world_extent <= 0 or _archipelago_square_intersects_extent(sq):
				candidates.append(sq)
	candidates.sort_custom(_archipelago_square_closer)
	_archipelago_active_squares[Vector2i.ZERO] = true
	for i in range(mini(archipelago_island_count - 1, candidates.size())):
		_archipelago_active_squares[candidates[i]] = true


func _archipelago_square_closer(a: Vector2i, b: Vector2i) -> bool:
	## Sort key: square centre distance to origin, then hash for ties.
	var da := ((Vector2(a) + Vector2(0.5, 0.5)) * float(archipelago_spacing)).length_squared()
	var db := ((Vector2(b) + Vector2(0.5, 0.5)) * float(archipelago_spacing)).length_squared()
	if da != db:
		return da < db
	var ha: int = hash(Vector3i(a.x, a.y, archipelago_seed))
	var hb: int = hash(Vector3i(b.x, b.y, archipelago_seed))
	return ha < hb


func set_tile_type_z0(pos_vec, alt, moist, _temp, chance):
	var tile_vec = get_random_ground_vec(chance)
	if alt <= water_max_alt:  # water
		tile_vec = Vector2i(5, 6)
	elif alt > water_max_alt and alt < sand_max_alt:  # sand
		tile_vec = Vector2i(5, 4)
	elif alt > sand_max_alt and moist < 0:  # swamp
		if alt < swamp_special_alt and chance < 0:
			tile_vec = Vector2i(27, 7)
		else:
			tile_vec = Vector2i(14, 7)
	else:
		# ground — record first land tile as spawn hint
		if spawn_point == Vector2i(0, 0):
			spawn_point = pos_vec

	set_cell(0, pos_vec, 0, tile_vec)


func get_random_ground_vec(chance):
	# the ground tiles are a matrix from (5,0) to (6,1) of 4 tiles
	var vec = Vector2i(5, 0)
	if chance < ground_chance_a:
		vec = Vector2i(5, 0)
	elif chance < ground_chance_b:
		vec = Vector2i(5, 1)
	elif chance < ground_chance_c:
		vec = Vector2i(6, 0)
	else:
		vec = Vector2i(6, 1)
	return vec


func set_tile_type_z1(pos_vec, alt, moist, _temp, chance):
	if not is_walkable_land(pos_vec):
		return
	if moist > 0 and alt > bush_min_alt and alt <= bush_max_alt and chance > bush_min_chance:
		set_cell(1, pos_vec, 0, Vector2i(7, 3))
	elif moist > 0 and alt > tree_min_alt and chance > tree_min_chance:
		set_cell(1, pos_vec, 0, Vector2i(7, 0))
	elif moist > 0 and alt > flower_min_alt and alt <= flower_max_alt and chance > flower_min_chance:
		set_cell(1, pos_vec, 0, Vector2i(9, 3))


func is_walkable_land(cell: Vector2i) -> bool:
	if get_cell_source_id(0, cell) == -1:
		return false
	var td = get_cell_tile_data(0, cell)
	if td == null:
		return false
	return td.get_collision_polygons_count(0) == 0


func count_walkable_neighbors(cell: Vector2i) -> int:
	var n := 0
	for d in SPAWN_NEIGHBORS:
		if is_walkable_land(cell + d):
			n += 1
	return n


func resolve_player_spawn(origin_cell: Vector2i = Vector2i(0, 0), max_radius: int = 96) -> Vector2i:
	generate_chunk(map_to_local(origin_cell))
	if is_walkable_land(origin_cell):
		spawn_point = origin_cell
		return origin_cell

	var visited := {}
	var queue: Array[Vector2i] = [origin_cell]
	visited[origin_cell] = true
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for d in SPAWN_NEIGHBORS:
			var next: Vector2i = current + d
			if visited.has(next):
				continue
			var dx: int = absi(next.x - origin_cell.x)
			var dy: int = absi(next.y - origin_cell.y)
			if dx > max_radius or dy > max_radius:
				continue
			visited[next] = true
			if get_cell_source_id(0, next) == -1:
				generate_chunk(map_to_local(next))
			if is_walkable_land(next):
				spawn_point = next
				return next
			queue.append(next)

	spawn_point = origin_cell
	return origin_cell
