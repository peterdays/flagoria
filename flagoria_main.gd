extends Node2D

const PORT = 9786
var enet_peer = ENetMultiplayerPeer.new()
const Player = preload("res://Player/character_body_2d.tscn")
@onready var address_entry = $CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/AddressEntry
var world_params: MapGenParams


func _ready():
	get_node("CanvasLayer2/MainMenu").connect("new_server_created", setup_server)
	get_node("CanvasLayer2/MainMenu").connect("new_player_added", add_player)
	get_node("CanvasLayer2/MainMenu").connect("new_player_joined", add_player_joined)

	var server_port := server_port_from_args(OS.get_cmdline_user_args())
	if server_port == -1:
		push_error("dedicated server: --port must be a number from 1 to 65535")
		get_tree().quit(1)
	elif server_port > 0 and start_dedicated_server(server_port) != OK:
		get_tree().quit(1)


static func server_port_from_args(args: PackedStringArray) -> int:
	## Port for `-- --server [--port N]`, 0 without --server, -1 for a bad port.
	if not args.has("--server"):
		return 0
	var port_text := str(PORT)
	for i in args.size():
		if args[i] == "--port":
			port_text = args[i + 1] if i + 1 < args.size() else ""
		elif args[i].begins_with("--port="):
			port_text = args[i].trim_prefix("--port=")
	if not port_text.is_valid_int() or port_text.to_int() < 1 or port_text.to_int() > 65535:
		return -1
	return port_text.to_int()


func start_dedicated_server(port: int) -> Error:
	## Host with the active MapGen params and no local player or menu. Remote
	## clients join and receive the params through the normal Join path.
	get_node("CanvasLayer2/MainMenu").hide()
	get_node("/root/MusicPlayer").stop(0.0)  # no one listens on a dedicated server
	var err := setup_server(get_node("/root/MapGen").params, port)
	if err != OK:
		push_error("dedicated server: cannot listen on UDP port %s (error %s)" % [port, err])
		return err
	get_node("World/worldMap").resolve_player_spawn()
	print("Dedicated server listening on UDP port %s" % port)
	return OK


func setup_server(params: MapGenParams, port: int = PORT) -> Error:
	## Host applies the chosen map params locally, then syncs the full set to joining peers.
	world_params = params.duplicate_params()
	world_params.ensure_seeds()
	get_node("/root/MapGen").params = world_params.duplicate_params()
	_apply_params_to_world(world_params)

	var err := enet_peer.create_server(port)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_connected.connect(_sync_map_params_to_peer)
	multiplayer.peer_disconnected.connect(remove_player)
	if err == OK:
		spawn_mobs()
	return err


func spawn_mobs() -> int:
	## Server only: place this map's mobs around the player spawn.
	var world = get_node("World/worldMap")
	var origin: Vector2i = world.resolve_player_spawn()
	return get_node("World/Mobs").spawn_for_world(world, origin, world_params.altitude_seed)


func _apply_params_to_world(params: MapGenParams) -> void:
	var world = get_node("World/worldMap")
	if world:
		world.apply_map_params(params)


func _land_spawn_position(for_player: Node = null) -> Vector2:
	## The map's land spawn point. For a player, the nearest spot near it that
	## no other living player stands on (see SPAWN_RADIUS in TileMap.gd).
	var world = get_node("World/worldMap")
	var cell = world.resolve_player_spawn()
	if for_player == null:
		return world.map_to_local(cell)
	return world.free_spawn_position(cell, _taken_spawn_spots(for_player))


func _taken_spawn_spots(except: Node) -> Array[Vector2]:
	## Where the living players other than except stand. Dead bodies have no
	## collision, so they do not take a spot.
	var taken: Array[Vector2] = []
	for child in get_node("World").get_children():
		if child is CharacterBody2D and child != except:
			var health = child.get_node_or_null("Health")
			if health == null or not health.is_dead():
				taken.append(child.position)
	return taken


func _place_players_on_land() -> void:
	# Players the server already placed on a free spot near the spawn keep it;
	# the rest move to one.
	var world = get_node("World/worldMap")
	var cell: Vector2i = world.resolve_player_spawn()
	var world_root = get_node("/root/Flagoria/World")
	for child in world_root.get_children():
		if child is CharacterBody2D:
			if not world.is_free_spawn_spot(child.position, cell, _taken_spawn_spots(child)):
				child.position = _land_spawn_position(child)


func _sync_map_params_to_peer(peer_id: int) -> void:
	## Send the full parameter dictionary (not just seeds) so both players share one map.
	if world_params == null:
		return
	rpc_id(peer_id, "receive_map_params", world_params.to_dict())


@rpc("authority", "reliable", "call_remote")
func receive_map_params(data: Dictionary) -> void:
	var params = MapGenParams.new()
	params.from_dict(data)
	world_params = params
	get_node("/root/MapGen").params = params.duplicate_params()
	_apply_params_to_world(params)
	_place_players_on_land()
	var world = get_node("World/worldMap")
	world.player_spawned = true


func add_player(peer_id):
	# host / peer spawn
	var player = Player.instantiate()
	player.name = str(peer_id)
	print("player added", player.name)
	player.position = _land_spawn_position(player)
	get_node("/root/Flagoria/World").add_child(player)

	var world = get_node("World/worldMap")
	world.player_spawned = true


func add_player_joined(port: int = PORT):
	print("player_joined")
	var server_ip = "localhost"
	if address_entry.text:
		server_ip = address_entry.text

	enet_peer.create_client(server_ip, port)
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
