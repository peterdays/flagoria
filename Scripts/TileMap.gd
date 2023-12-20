extends TileMap

var rng = RandomNumberGenerator.new()
var count = 0
var moisture = FastNoiseLite.new()
var temperature = FastNoiseLite.new()
var altitude = FastNoiseLite.new()
var items_chance = FastNoiseLite.new()
const CHUNK_WIDTH = 32
const CHUNK_HEIGHT = 32
var player_spawned = false
var spawn_point = Vector2i(0, 0)


# Called when the node enters the scene tree for the first time.
func _ready():
	items_chance.frequency = 1


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
#	if not is_multiplayer_authority(): return

	count += 1
	if (count % 15) == 0 and player_spawned:
		var current_player_id = str(multiplayer.get_unique_id())
		count = 0

		var curr_player = get_node_or_null("/root/Flagoria/World/" + str(current_player_id))
		if curr_player:
			generate_chunk(curr_player.position)


func generate_chunk(position):
	var tile_pos = local_to_map(position)
	for x in range(CHUNK_WIDTH):
		for y in range(CHUNK_HEIGHT):
			var new_x = tile_pos.x - CHUNK_WIDTH/2 + x
			var new_y = tile_pos.y - CHUNK_HEIGHT/2 + y
			var moist = moisture.get_noise_2d(new_x, new_y)
			var temp = temperature.get_noise_2d(new_x, new_y)
			var alt = altitude.get_noise_2d(new_x, new_y)
			var chance = items_chance.get_noise_2d(new_x, new_y)
			
			set_tile_type_z0(Vector2i(new_x, new_y), alt, moist, temp, chance)
			set_tile_type_z1(Vector2i(new_x, new_y), alt, moist, temp, chance)

			# set_cell(0, Vector2i(new_x, new_y), 0, Vector2i(5, 1))

func set_tile_type_z0(pos_vec, alt, moist, temp, chance):

	var tile_vec = get_random_ground_vec(chance)
	if alt <= 0.2:  # water
		tile_vec = Vector2i(5, 6)
	elif alt > 0.2 and alt < 0.25: # sand
		tile_vec = Vector2i(5, 4)
	elif alt > 0.25 and moist < 0:  # swamp
		if alt < 0.26 and chance < 0:
			tile_vec = Vector2i(27, 7)
		else:
			tile_vec = Vector2i(14, 7)
	else:
		# no change made and the tile_vec is ground
		if spawn_point == Vector2i(0, 0):  # only the first time to change
			spawn_point = pos_vec

	set_cell(0, pos_vec, 0, tile_vec)

func get_random_ground_vec(chance):
	# the ground tiles are a matrix from (5,0) to (6,1) of 4 tiles
	var vec = Vector2i(5, 0)
	if chance < -0.25:
		vec = Vector2i(5, 0)
	elif chance < 0.25:
		vec = Vector2i(5, 1)
	elif chance < 0.75:
		vec = Vector2i(6, 0)
	else:
		vec = Vector2i(6, 1)
		
	return vec

func set_tile_type_z1(pos_vec, alt, moist, temp, chance):
	
	if moist > 0 and alt > 0.3 and alt <= 0.4 and chance > 0:
		var tile_vec = Vector2i(7, 3)
		set_cell(1, pos_vec, 0, tile_vec)
	elif moist > 0 and alt > 0.4 and chance > 0.3:
		set_cell(1, pos_vec, 0, Vector2i(7, 0))
