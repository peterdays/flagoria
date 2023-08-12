extends TileMap

var moisture = FastNoiseLite.new()
var temperature = FastNoiseLite.new()
var altitude = FastNoiseLite.new()
const CHUNK_WIDTH = 32
const CHUNK_HEIGHT = 32
# advised against in production; the positions of nodes may change
@onready var player = get_parent().get_child(1)

# Called when the node enters the scene tree for the first time.
func _ready():
	moisture.seed = randi()
	temperature.seed = randi()
	altitude.seed = randi()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
#	if (delta % 15) == 0:
	generate_chunk(player.position)

func generate_chunk(position):
	var tile_pos = local_to_map(position)
	for x in range(CHUNK_WIDTH):
		for y in range(CHUNK_HEIGHT):
			var new_x = tile_pos.x - CHUNK_WIDTH/2 + x
			var new_y = tile_pos.y - CHUNK_HEIGHT/2 + y
			var moist = moisture.get_noise_2d(new_x, new_y)
			var temp = temperature.get_noise_2d(new_x, new_y)
			var alt = altitude.get_noise_2d(new_x, new_y)
			
			set_tile_type_z0(Vector2i(new_x, new_y), alt, moist, temp)
			#set_tile_type_z1(Vector2i(new_x, new_y), alt, moist, temp)

			# set_cell(0, Vector2i(new_x, new_y), 0, Vector2i(5, 1))

func set_tile_type_z0(pos_vec, alt, moist, temp):
	var tyle_vec = Vector2i(5, 1)
	if alt < 0.2:  # water
		tyle_vec = Vector2i(5, 6)

	set_cell(0, pos_vec, 0, tyle_vec)

func set_tile_type_z1(pos_vec, alt, moist, temp):

	if alt > 0.2 and moist > 0.35 and moist < 0.4:
		var tyle_vec = Vector2i(7, 3)
		set_cell(1, pos_vec, 0, tyle_vec)
