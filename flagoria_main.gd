extends Node2D

const PORT = 26000
var enet_peer = ENetMultiplayerPeer.new()
const Player = preload("res://character_body_2d.tscn")
var worldSeeds

# Called when the node enters the scene tree for the first time.
func _ready():
	get_node("CanvasLayer/MainMenu").connect("new_server_created", setup_server)
	get_node("CanvasLayer/MainMenu").connect("new_player_added", add_player)
	get_node("CanvasLayer/MainMenu").connect("new_player_joined", add_player_joined)
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)

func setup_server(seeds: WorldSeeder):
	self.worldSeeds = seeds
	print(worldSeeds.moist_seed)
	var world = get_node("World/worldMap")
	#world.moisture.seed = seeds.moist_seed
	#world.temperature.seed = seeds.temp_seed
	#world.altitude.seed = seeds.alt_seed
	#world.items_chance.seed = seeds.items_chance
	world.world_created = true
	# creating the server
	print("updated seeds")


func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	print("player added in add_player")
	get_node("/root/Flagoria/World").add_child(player)


func add_player_joined():
	var world = get_node("World/worldMap")
	#world.moisture.seed = worldSeeds.moist_seed
	#world.temperature.seed = worldSeeds.temp_seed
	#world.altitude.seed = worldSeeds.alt_seed
	#world.items_chance.seed = worldSeeds.items_chance
	world.world_created = true
	print("player_joined")
	# creating the server
	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer
