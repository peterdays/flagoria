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
var ground_chance_a: float = -0.25
var ground_chance_b: float = 0.25
var ground_chance_c: float = 0.75
var bush_min_alt: float = 0.3
var bush_max_alt: float = 0.4
var bush_min_chance: float = 0.0
var tree_min_alt: float = 0.4
var tree_min_chance: float = 0.3

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
	ground_chance_a = working.ground_chance_a
	ground_chance_b = working.ground_chance_b
	ground_chance_c = working.ground_chance_c
	bush_min_alt = working.bush_min_alt
	bush_max_alt = working.bush_max_alt
	bush_min_chance = working.bush_min_chance
	tree_min_alt = working.tree_min_alt
	tree_min_chance = working.tree_min_chance

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
			var alt = island_altitude(Vector2i(new_x, new_y), altitude.get_noise_2d(new_x, new_y))
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
