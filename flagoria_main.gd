extends Node2D

const PORT = 9786
var enet_peer = ENetMultiplayerPeer.new()
const world = preload("res://tile_map.tscn")
const Player = preload("res://character_body_2d.tscn")
var worldSeeds

# Called when the node enters the scene tree for the first time.
func _ready():
	get_node("CanvasLayer/MainMenu").connect("new_server_created", setup_server)
	get_node("CanvasLayer/MainMenu").connect("new_player_added", add_player)
	get_node("CanvasLayer/MainMenu").connect("new_player_joined", add_player_joined)


func setup_server(seeds: WorldSeeder):
	self.worldSeeds = seeds
	var world = get_node("World/worldMap")
	# creating the server
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	#world.moisture.seed = seeds.moist_seed
	#world.temperature.seed = seeds.temp_seed
	#world.altitude.seed = seeds.alt_seed
	#world.items_chance.seed = seeds.items_chance


#func add_player(peer_id):
#	#enet_peer.create_server(PORT)
#	#multiplayer.multiplayer_peer = enet_peer
#
#	var world = get_node("World/worldMap")
#
#	print("updated seeds")
#	aux_add_player_signal(peer_id)
#	print("player added in add_player")

func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	print("player added")
	get_node("/root/Flagoria/World").add_child(player)

	if peer_id > 1:
		var player1 = get_node("World").get_child(3)
		print(player1.name, "AAAAAA")
	var world = get_node("World/worldMap")
	world.player_spawned = true

func add_player_joined():
#	var world = get_node("World/worldMap")
	#world.moisture.seed = worldSeeds.moist_seed
	#world.temperature.seed = worldSeeds.temp_seed
	#world.altitude.seed = worldSeeds.alt_seed
	#world.items_chance.seed = worldSeeds.items_chance

	print("player_joined")
	# creating the server
	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer

func remove_player(peer_id):
	var player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	
