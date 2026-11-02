extends TileMap

## Layer-0 ground was drawn in `cells`, or (an empty Rect2i) cleared everywhere.
## Emitted on every peer right after the cells are set, so local visuals that
## depend on the ground (hidden mobs) update in the same frame.
signal ground_changed(cells: Rect2i)

var rng = RandomNumberGenerator.new()
var count = 0
var moisture = FastNoiseLite.new()
var temperature = FastNoiseLite.new()
var altitude = FastNoiseLite.new()
var items_chance = FastNoiseLite.new()
var biome = FastNoiseLite.new()
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
# predict_cell results by cell; cleared when the params change.
var _predict_cache: Dictionary = {}
## Tree and bush cuts and regrowth (Scripts/mechanics/trees/tree_cuts.gd).
var _tree_cuts := TreeCuts.new(self)
## Placed plank bridges (Scripts/mechanics/bridges/bridge_builder.gd).
var _bridges := BridgeBuilder.new(self)
## Seconds of play after a cut before any stump turns back into its plant,
## overriding each type's regrow_delay; negative (the default) uses the
## type's. Kept in TreeCuts; this property reads and writes it there.
var regrow_delay: float:
	get:
		return _tree_cuts.regrow_delay
	set(value):
		_tree_cuts.regrow_delay = value
## Seconds this map has been played; advanced in _process, cut times use it.
var play_time: float = 0.0
## Altitude shaping (Scripts/world/terrain_shape.gd); reads this map's values.
var _terrain := TerrainShape.new(self)
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
var pine_min_alt: float = 0.5
var pine_min_moist: float = -0.25
var pine_min_chance: float = 0.3
var bushy_tree_min_moist: float = 0.3
var biome_frequency: float = 0.0
var biome_seed: int = 0

# Walkable ground decorations (flowers, stones) sit on their own layer at the ground's
# z_index so the player always draws over them; layer 1 (bushes, trees) is z 1.
const GROUND_DECOR_LAYER := 2
# plant_tile result for a cell without a plant.
const NO_PLANT := Vector2i(-1, -1)

# Spawn search constants other scripts and tests read from the map.
const SPAWN_MIN_REACHABLE := SpawnFinder.SPAWN_MIN_REACHABLE
const SPAWN_RADIUS := SpawnFinder.SPAWN_RADIUS
const SPAWN_CLEARANCE := SpawnFinder.SPAWN_CLEARANCE


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

	biome_frequency = working.biome_frequency
	biome_seed = working.biome_seed
	if biome_frequency > 0.0:
		_configure_noise(biome, working.biome_seed, working.biome_frequency, working)

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
	_terrain._rebuild_archipelago_active_squares()
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
	pine_min_alt = working.pine_min_alt
	pine_min_moist = working.pine_min_moist
	pine_min_chance = working.pine_min_chance
	bushy_tree_min_moist = working.bushy_tree_min_moist

	clear()
	_predict_cache.clear()
	_tree_cuts.clear()
	_bridges.clear()
	spawn_point = Vector2i(0, 0)
	ground_changed.emit(Rect2i())


func _configure_noise(noise: FastNoiseLite, seed_value: int, frequency: float, p: MapGenParams) -> void:
	noise.seed = seed_value
	noise.noise_type = p.noise_type
	noise.frequency = frequency
	noise.fractal_octaves = p.fractal_octaves
	noise.fractal_lacunarity = p.fractal_lacunarity
	noise.fractal_gain = p.fractal_gain


func _process(delta):
	play_time += delta
	count += 1
	if (count % chunk_refresh_frames) == 0 and not _tree_cuts.is_empty():
		regrow_due()
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
			var b := biome_at(cell)
			var alt := cell_altitude(cell, b)
			var chance = items_chance.get_noise_2d(new_x, new_y)

			set_tile_type_z0(cell, alt, moist, temp, chance, b)
			set_tile_type_z1(cell, alt, moist, temp, chance, b)
	var corner := Vector2i(tile_pos.x - chunk_width / 2, tile_pos.y - chunk_height / 2)
	ground_changed.emit(Rect2i(corner, Vector2i(chunk_width, chunk_height)))


func cell_altitude(cell: Vector2i, biome_id: int) -> float:
	return _terrain.cell_altitude(cell, biome_id)


func island_altitude(cell: Vector2i, alt: float) -> float:
	return _terrain.island_altitude(cell, alt)


func archipelago_altitude(cell: Vector2i, alt: float) -> float:
	return _terrain.archipelago_altitude(cell, alt)


func archipelago_centre(square: Vector2i) -> Vector2:
	return _terrain.archipelago_centre(square)


func archipelago_square_active(square: Vector2i) -> bool:
	return _terrain.archipelago_square_active(square)


func biome_at(cell: Vector2i) -> int:
	## Biome id at a cell. Frequency 0 keeps everything temperate (biomes off).
	if biome_frequency <= 0.0:
		return BiomeCatalog.TEMPERATE
	return BiomeCatalog.from_noise(biome.get_noise_2d(cell.x, cell.y))


func set_tile_type_z0(pos_vec, alt, moist, _temp, chance, biome_id: int = BiomeCatalog.TEMPERATE):
	if _bridges.has_bridge(pos_vec):
		set_cell(0, pos_vec, TileCatalog.SOURCE_ID, _bridges.piece(pos_vec))
		return
	var tile_vec := ground_tile(alt, moist, chance, biome_id)
	if tile_vec != TileCatalog.WATER and tile_vec != TileCatalog.SAND \
			and tile_vec != TileCatalog.SWAMP and tile_vec != TileCatalog.SWAMP_SPECIAL:
		# ground — record first land tile as spawn hint
		if spawn_point == Vector2i(0, 0):
			spawn_point = pos_vec

	set_cell(0, pos_vec, TileCatalog.SOURCE_ID, tile_vec)


func ground_tile(alt: float, moist: float, chance: float, biome_id: int = BiomeCatalog.TEMPERATE) -> Vector2i:
	## Layer-0 tile for one cell. With biomes on, BiomeCatalog.TERRAIN moves the
	## beach top and the swamp moisture threshold per biome; with biomes off the
	## Map Settings thresholds apply unchanged.
	var sand_top := sand_max_alt
	var swamp_special_top := swamp_special_alt
	var swamp_moist := 0.0
	if biome_frequency > 0.0:
		var band := BiomeCatalog.terrain(biome_id, "sand_band")
		sand_top = maxf(water_max_alt, sand_max_alt + band)
		swamp_special_top = swamp_special_alt + band
		swamp_moist = BiomeCatalog.terrain(biome_id, "swamp_moisture")
	if alt <= water_max_alt:  # water
		return TileCatalog.WATER
	if alt < sand_top:  # sand
		return TileCatalog.SAND
	if alt > sand_top and moist < swamp_moist:  # swamp
		if alt < swamp_special_top and chance < 0:
			return TileCatalog.SWAMP_SPECIAL
		return TileCatalog.SWAMP
	return get_random_ground_vec(chance)


func get_random_ground_vec(chance):
	var vec = TileCatalog.GRASS_A
	if chance < ground_chance_a:
		vec = TileCatalog.GRASS_A
	elif chance < ground_chance_b:
		vec = TileCatalog.GRASS_B
	elif chance < ground_chance_c:
		vec = TileCatalog.GRASS_C
	else:
		vec = TileCatalog.GRASS_D
	return vec


func set_tile_type_z1(pos_vec, alt, moist, _temp, chance, biome_id: int = BiomeCatalog.TEMPERATE):
	if not is_walkable_land(pos_vec) or _bridges.has_bridge(pos_vec):
		return
	if _tree_cuts.has_cut(pos_vec):
		set_cell(GROUND_DECOR_LAYER, pos_vec, TileCatalog.SOURCE_ID, _tree_cuts.leftover(pos_vec))
		return
	var tile := NO_PLANT
	# Biomes can widen beaches into the foliage bands; beaches get no plants.
	if biome_frequency <= 0.0 or get_cell_atlas_coords(0, pos_vec) != TileCatalog.SAND:
		tile = plant_tile(alt, moist, chance, biome_id)
	if tile == NO_PLANT:
		tile = structure_tile(chance, biome_id)
	if tile == TileCatalog.FLOWER or tile == TileCatalog.STONES:
		set_cell(GROUND_DECOR_LAYER, pos_vec, TileCatalog.SOURCE_ID, tile)
	elif tile != NO_PLANT:
		set_cell(1, pos_vec, TileCatalog.SOURCE_ID, tile)


func plant_tile(alt: float, moist: float, chance: float, biome_id: int = BiomeCatalog.TEMPERATE) -> Vector2i:
	## Bush, tree, bushy tree, pine or flower for one walkable cell, or
	## NO_PLANT. With biomes on, BiomeCatalog.PLANTS shifts the tree, bush and
	## pine chance thresholds and the bushy tree moisture threshold, and
	## BiomeCatalog.TERRAIN the flower threshold; with biomes off there are no
	## pines or bushy trees and the Map Settings thresholds apply unchanged.
	var bush_chance := bush_min_chance
	var tree_chance := tree_min_chance
	var flower_chance := flower_min_chance
	if biome_frequency > 0.0:
		bush_chance += BiomeCatalog.plants(biome_id, "bush_chance")
		tree_chance += BiomeCatalog.plants(biome_id, "tree_chance")
		flower_chance += BiomeCatalog.terrain(biome_id, "flower_chance")
	if moist > 0 and alt > bush_min_alt and alt <= bush_max_alt and chance > bush_chance:
		return TileCatalog.BUSH
	if moist > 0 and alt > tree_min_alt and chance > tree_chance:
		if biome_frequency > 0.0 and moist > bushy_tree_min_moist + BiomeCatalog.plants(biome_id, "bushy_moist"):
			return TileCatalog.TREE_BUSHY
		return TileCatalog.TREE
	if biome_frequency > 0.0 and moist <= 0 and alt > pine_min_alt:
		# Dry high ground; the moisture floor never goes below the biome's
		# swamp threshold, so pines stay off swamp.
		var pine_moist := maxf(pine_min_moist, BiomeCatalog.terrain(biome_id, "swamp_moisture"))
		if moist > pine_moist and chance > pine_min_chance + BiomeCatalog.plants(biome_id, "pine_chance"):
			return TileCatalog.PINE
	if moist > 0 and alt > flower_min_alt and alt <= flower_max_alt and chance > flower_chance:
		return TileCatalog.FLOWER
	return NO_PLANT


func structure_tile(chance: float, biome_id: int = BiomeCatalog.TEMPERATE) -> Vector2i:
	## Stones for one walkable cell that has no plant, or NO_PLANT. Only with
	## biomes on: BiomeCatalog.STRUCTURES sets the chance threshold per biome.
	## With biomes off there are no structures and the map is unchanged.
	if biome_frequency <= 0.0:
		return NO_PLANT
	if chance > BiomeCatalog.structures(biome_id, "stone_chance"):
		return TileCatalog.STONES
	return NO_PLANT


func predict_cell(cell: Vector2i) -> Array:
	## [ground atlas, plant or structure atlas or NO_PLANT] that generate_chunk
	## puts at `cell`, computed from the noise alone: no tiles are placed, so
	## code away from the players (mobs) can read terrain anywhere.
	if _predict_cache.has(cell):
		return _predict_cache[cell]
	var moist := moisture.get_noise_2d(cell.x, cell.y)
	var chance := items_chance.get_noise_2d(cell.x, cell.y)
	var b := biome_at(cell)
	var alt := cell_altitude(cell, b)
	var ground: Vector2i = _bridges.piece_or(cell, ground_tile(alt, moist, chance, b))
	var top := NO_PLANT
	if ground_is_walkable(ground) and not _bridges.has_bridge(cell):
		if biome_frequency <= 0.0 or ground != TileCatalog.SAND:
			top = plant_tile(alt, moist, chance, b)
		if top == NO_PLANT:
			top = structure_tile(chance, b)
		if _tree_cuts.has_cut(cell):
			top = _tree_cuts.leftover(cell)
	var out := [ground, top]
	_predict_cache[cell] = out
	return out


func predicted_clear(cell: Vector2i) -> bool:
	## is_clear_ground from predict_cell: walkable, no tree, bush or stones.
	var p := predict_cell(cell)
	if not ground_is_walkable(p[0]):
		return false
	return p[1] == NO_PLANT or p[1] == TileCatalog.FLOWER or InteractableCatalog.is_leftover(p[1])


func choppable(cell: Vector2i) -> InteractableType:
	return _tree_cuts.choppable(cell)


func has_tree(cell: Vector2i) -> bool:
	return _tree_cuts.has_tree(cell)


func cut_choppable(cell: Vector2i) -> InteractableType:
	return _tree_cuts.cut_choppable(cell)


func regrow_due() -> int:
	return _tree_cuts.regrow_due()


func build_bridge(from: Vector2i, to: Vector2i) -> bool:
	return _bridges.build_bridge(from, to)


static func bridge_pieces(length: int, horizontal: bool, land_before: bool, land_after: bool) -> Array[Vector2i]:
	return BridgeBuilder.bridge_pieces(length, horizontal, land_before, land_after)


func player_on_cell(cell: Vector2i) -> bool:
	## True when a player's body box (a CharacterBody2D next to this map)
	## overlaps the cell.
	var cell_rect := Rect2(to_global(map_to_local(cell) - Vector2(8, 8)), Vector2(16, 16) * global_scale)
	for node in get_parent().get_children():
		if not node is CharacterBody2D:
			continue
		var body := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if body and body.shape and (body.global_transform * body.shape.get_rect()).intersects(cell_rect):
			return true
	return false


func ground_is_walkable(atlas: Vector2i) -> bool:
	## True when the layer-0 tile at `atlas` has no collision.
	var src := tile_set.get_source(TileCatalog.SOURCE_ID) as TileSetAtlasSource
	var td := src.get_tile_data(atlas, 0) if src and src.has_tile(atlas) else null
	return td != null and td.get_collision_polygons_count(0) == 0


func is_walkable_land(cell: Vector2i) -> bool:
	if get_cell_source_id(0, cell) == -1:
		return false
	var td = get_cell_tile_data(0, cell)
	if td == null:
		return false
	return td.get_collision_polygons_count(0) == 0


func count_walkable_neighbors(cell: Vector2i) -> int:
	return SpawnFinder.count_walkable_neighbors(self, cell)


func is_clear_ground(cell: Vector2i) -> bool:
	## Walkable ground with no tree, bush or stones on it. Generates the cell's
	## chunk first if it has not been generated yet.
	if get_cell_source_id(0, cell) == -1:
		generate_chunk(map_to_local(cell))
	if not is_walkable_land(cell):
		return false
	if get_cell_source_id(1, cell) != -1:
		return false
	return get_cell_atlas_coords(GROUND_DECOR_LAYER, cell) != TileCatalog.STONES


func reachable_clear_cells(start: Vector2i, limit: int = SpawnFinder.SPAWN_MIN_REACHABLE) -> Array[Vector2i]:
	return SpawnFinder.reachable_clear_cells(self, start, limit)


func resolve_player_spawn(origin_cell: Vector2i = Vector2i(0, 0), max_radius: int = 96) -> Vector2i:
	return SpawnFinder.resolve_player_spawn(self, origin_cell, max_radius)


func spawn_spots(origin_cell: Vector2i, limit: int = SpawnFinder.SPAWN_SEARCH_LIMIT) -> Array[Vector2]:
	return SpawnFinder.spawn_spots(self, origin_cell, limit)


func free_spawn_position(origin_cell: Vector2i, taken: Array[Vector2]) -> Vector2:
	return SpawnFinder.free_spawn_position(self, origin_cell, taken)

