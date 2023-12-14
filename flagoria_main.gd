extends Node2D

const PORT = 9786
var enet_peer = ENetMultiplayerPeer.new()
const Player = preload("res://character_body_2d.tscn")
@onready var address_entry = $CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/AddressEntry
var worldSeeds

# Called when the node enters the scene tree for the first time.
func _ready():
	get_node("CanvasLayer2/MainMenu").connect("new_server_created", setup_server)
	get_node("CanvasLayer2/MainMenu").connect("new_player_added", add_player)
	get_node("CanvasLayer2/MainMenu").connect("new_player_joined", add_player_joined)


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
	# host
	var player = Player.instantiate()
	player.name = str(peer_id)
	print("player added")
	get_node("/root/Flagoria/World").add_child(player)

	if peer_id > 1:
		var player1 = get_node("World").get_child(3)
	var world = get_node("World/worldMap")
	world.player_spawned = true
	
	unpn_setup()

func add_player_joined():
#	var world = get_node("World/worldMap")
	#world.moisture.seed = worldSeeds.moist_seed
	#world.temperature.seed = worldSeeds.temp_seed
	#world.altitude.seed = worldSeeds.alt_seed
	#world.items_chance.seed = worldSeeds.items_chance

	print("player_joined")
	# creating the server
	var server_ip = "localhost"
	if address_entry.text:
		server_ip = address_entry.text

	enet_peer.create_client(server_ip, PORT)
	multiplayer.multiplayer_peer = enet_peer
	var world = get_node("World/worldMap")
	world.player_spawned = true

func remove_player(peer_id):

	var player = get_node_or_null("/root/Flagoria/World/" + str(peer_id))

	if player:
		player.queue_free()


func unpn_setup():
	var upnp = UPNP.new()

	var discover_result = upnp.discover()
	assert(discover_result == UPNP.UPNP_RESULT_SUCCESS, \
		"UPNP Discovery failed! Error %s" % discover_result)

	assert(upnp.get_gateway() and upnp.get_gateway().is_valid_gateway(), \
		"UPNP Invalid gateway")

	var map_result = upnp.add_port_mapping(PORT)
	assert(map_result == UPNP.UPNP_RESULT_SUCCESS, \
		"UPNP Port mapping failed! Error %s" % map_result)
	
	print("SUCCESS!! Join address: %s" % upnp.query_external_address())

