extends Node2D

const JoinAddress = preload("res://Scripts/join_address.gd")
const PORT = 9786
## Most cuts in one join message (#354); see _sync_map_params_to_peer.
const JOIN_CUTS_PER_MESSAGE := 500
var enet_peer = ENetMultiplayerPeer.new()
## UDP port the main menu's Host button listens on.
var host_port := PORT
const Player = preload("res://Player/character_body_2d.tscn")
@onready var address_entry = $CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/AddressEntry
var world_params: MapGenParams
## The world save this match writes. Empty until Host or Load chooses one.
var save_name := ""
## Client: the spot the server picked for its own player, until it is placed.
var _own_spot := Vector2.INF
## Server spots for players not yet spawned here (#352). Applied in
## _apply_player_spots / _on_world_child_entered so a late joiner never draws
## another player at (0, 0) while waiting for that owner's sync.
var _pending_spots: Dictionary = {}
## Called instead of SceneTree.quit() when set (tests).
var quit_hook := Callable()
## Address last passed to create_client; used by the join-failed message (#348).
## The typed endpoint when the field has text, otherwise "localhost".
var _join_address := ""
## Host and port of the last Join attempt. 0 / "" until one starts.
var _join_host := ""
var _join_port := 0
## Dedicated server only: SIGTERM writes a byte to this file.
var _dedicated := false
var _server_quit_path := ""
var _server_shutdown_started := false


func _ready():
	get_node("CanvasLayer2/MainMenu").connect("new_server_created",
		func(params: MapGenParams) -> void: setup_server(params, host_port))
	get_node("CanvasLayer2/MainMenu").connect("new_player_added", add_player)
	get_node("CanvasLayer2/MainMenu").connect("new_player_joined", add_player_joined)
	get_node("World").child_entered_tree.connect(_on_world_child_entered)
	$QuitLayer/QuitPrompt.quit_confirmed.connect(quit_game)

	var args := OS.get_cmdline_user_args()
	var server_port := server_port_from_args(args)
	if server_port == -1:
		push_error("dedicated server: --port must be a number from 1 to 65535")
		get_tree().quit(1)
	elif server_port > 0:
		var loaded := server_params_from_args(args)
		if loaded["error"] != "":
			push_error("dedicated server: " + loaded["error"])
			get_tree().quit(1)
		elif start_dedicated_server(server_port, loaded["params"]) != OK:
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


static func server_params_from_args(args: PackedStringArray) -> Dictionary:
	## Map params for `--params <file>` or `--params=<file>`, a map save
	## (MapSave). {"params": MapGenParams, or null without --params, "error"}.
	var path := ""
	for i in args.size():
		if args[i] == "--params":
			path = args[i + 1] if i + 1 < args.size() else ""
			if path == "" or path.begins_with("--"):
				return {"params": null, "error": "--params needs a map save file"}
		elif args[i].begins_with("--params="):
			path = args[i].trim_prefix("--params=")
			if path == "":
				return {"params": null, "error": "--params needs a map save file"}
	if path == "":
		return {"params": null, "error": ""}
	return MapSave.load_map(path)


func start_dedicated_server(port: int, params: MapGenParams = null) -> Error:
	## Host with `params` (the active MapGen params when null) and no local
	## player or menu. Remote clients join and receive the params through the
	## normal Join path.
	get_node("CanvasLayer2/MainMenu").hide()
	get_node("/root/MusicPlayer").stop(0.0)  # no one listens on a dedicated server
	var err := setup_server(params if params != null else get_node("/root/MapGen").params, port, false)
	if err != OK:
		push_error("dedicated server: cannot listen on UDP port %s (error %s)" % [port, err])
		return err
	get_node("World/worldMap").resolve_player_spawn()
	_install_server_quit()
	print("Dedicated server listening on UDP port %s" % port)
	return OK


func _install_server_quit() -> void:
	## Catch SIGTERM so a laptop `kill -TERM` closes ENet and exits 0.
	## The helper loads with the project. Its handler arms only when this
	## process was started with `--server`. Load status 2 means it is
	## already loaded, which is fine.
	_dedicated = true
	_server_quit_path = "/tmp/flagoria-server-quit-%d" % OS.get_process_id()
	var status := GDExtensionManager.load_extension("res://addons/server_shutdown/server_shutdown.gdextension")
	if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
		push_error("dedicated server: SIGTERM helper failed to load (status %s)" % status)


func _process(_delta: float) -> void:
	if not _dedicated or _server_shutdown_started or _server_quit_path == "":
		return
	if not FileAccess.file_exists(_server_quit_path):
		return
	var handle := FileAccess.open(_server_quit_path, FileAccess.READ)
	if handle == null or handle.get_length() <= 0:
		return
	_shutdown_dedicated()


func _shutdown_dedicated() -> void:
	## One log line, then exit 0 after the disconnect can leave the socket.
	if _server_shutdown_started:
		return
	_server_shutdown_started = true
	enet_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("Dedicated server stopped.")
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		get_tree().quit(0))


func setup_server(params: MapGenParams, port: int = PORT, with_castle := true) -> Error:
	## Host applies the chosen map params locally, then syncs the full set to
	## joining peers. With `with_castle` (a host that plays), the host's
	## starting castle goes next to the spawn while it is still alone, before
	## the mobs (#271); joining peers receive it with the map (#278).
	world_params = params.duplicate_params()
	world_params.ensure_seeds()
	get_node("/root/MapGen").params = world_params.duplicate_params()
	_apply_params_to_world(world_params)
	_restore_loaded_world()
	if with_castle and not StructureSaves.adopt_start_castle(get_node("World/worldMap"), 1):
		get_node("World/worldMap").place_start_castle(1)  # the host is peer 1

	var err := enet_peer.create_server(port)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_connected.connect(_sync_map_params_to_peer)
	multiplayer.peer_disconnected.connect(remove_player)
	if err == OK:
		spawn_mobs()
	return err


func spawn_mobs() -> int:
	## Server only: place this map's mobs around the player spawn, at this
	## host's saved mob spawn rate.
	var world = get_node("World/worldMap")
	var origin: Vector2i = world.resolve_player_spawn()
	var rate: float = get_node("/root/GameSettings").mob_rate
	return get_node("World/Mobs").spawn_for_world(world, origin, world_params.altitude_seed, rate)


func _restore_loaded_world() -> int:
	## After the params are applied and before any chunk is drawn or any
	## player spawns: put back the cuts, the plank bridges (#226) and the
	## structures and walls (#42) of the
	## save MapGen.load_map_inputs read, when this host is starting that
	## world. Returns how many cuts, bridge cells, placements and walls came back.
	var loaded: WorldSave = get_node("/root/MapGen").take_loaded_world(world_params)
	var world = get_node("World/worldMap")
	if loaded == null or world == null:
		return 0
	var bridges: int = world.replace_bridges(BridgeBuilder.from_changes(loaded.tile_edits, world))
	var cuts: int = world.restore_cuts(loaded.object_changes)
	return cuts + bridges + StructureSaves.restore(loaded.structures, world)  # after cuts: a structure clears its cells


func _apply_params_to_world(params: MapGenParams) -> void:
	var world = get_node("World/worldMap")
	if world:
		world.apply_map_params(params)


func _land_spawn_position(for_player: Node = null) -> Vector2:
	## The map's land spawn point. For a player, the nearest spot near it that
	## no other living player stands on (see SPAWN_RADIUS in Scripts/world/spawn_finder.gd).
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


func _place_own_player() -> void:
	## Client: put its own player on the spot the server picked for it. The
	## player arrives at (0, 0), as the server never sends the position of a
	## node the client owns. Other players' copies used to stay at (0, 0)
	## until their owner's sync (#352); _apply_player_spots places them from
	## the server's list. The client still must not pick a spawn from its
	## copies of others: they can be out of date, so a spot picked from them
	## can land on someone (found in a multi-peer play-test).
	if _own_spot != Vector2.INF:
		_pending_spots[str(multiplayer.get_unique_id())] = _own_spot
		_own_spot = Vector2.INF
	_apply_player_spots({})


func _player_spots() -> Dictionary:
	## Each player name -> position on this peer (the server's copies when
	## the host calls it).
	var spots := {}
	for child in get_node("World").get_children():
		if child is CharacterBody2D:
			spots[str(child.name)] = child.position
	return spots


func _apply_player_spots(spots: Dictionary) -> void:
	## Put each listed player on the given spot. Spots for players not yet
	## in the tree wait in _pending_spots until _on_world_child_entered.
	for key in spots:
		_pending_spots[str(key)] = spots[key]
	for key in _pending_spots.keys():
		var node = get_node_or_null("World/" + str(key))
		if node is CharacterBody2D:
			node.position = _pending_spots[key]
			_pending_spots.erase(key)


func _on_world_child_entered(node: Node) -> void:
	# The map (with the spots) can reach a client before its players do.
	if not node is CharacterBody2D:
		return
	var key := str(node.name)
	if _pending_spots.has(key):
		node.position = _pending_spots[key]
		_pending_spots.erase(key)
	elif key == str(multiplayer.get_unique_id()) and _own_spot != Vector2.INF:
		_place_own_player.call_deferred()


func _sync_map_params_to_peer(peer_id: int) -> void:
	## Send the full parameter dictionary (not just seeds) so both players
	## share one map, with the spot add_player picked for the peer's player
	## and the host's tree and bush cuts in the world save format
	## (TreeCuts.to_changes), so a joining peer draws the same stumps. Later
	## cuts reach it through Interaction.apply_cut, sent after this on the
	## same reliable channel, and regrowth through
	## Interaction.apply_regrow_cells (#298).
	## The placed structures go too (StructurePlacer.to_sync), so the peer's
	## castles match the host's from its first frame (#278 join half).
	## Placed plank bridges go too (BridgeBuilder.to_sync, #297).
	## The cut list goes JOIN_CUTS_PER_MESSAGE cuts at a time (#354): the
	## first part with the params, the rest in receive_join_cuts right after.
	if world_params == null:
		return
	var player = get_node_or_null("World/" + str(peer_id))
	var spot: Vector2 = player.position if player else Vector2.INF
	var world = get_node("World/worldMap")
	var parts := WorldSave.split_changes(world.cut_changes(), JOIN_CUTS_PER_MESSAGE)
	rpc_id(peer_id, "receive_map_params", world_params.to_dict(), spot, parts[0],
			world.structures_for_sync(), world.bridges_for_sync(), _player_spots())
	for i in range(1, parts.size()):
		rpc_id(peer_id, "receive_join_cuts", parts[i])


@rpc("authority", "reliable", "call_remote")
func receive_map_params(data: Dictionary, spot: Vector2, cuts: Dictionary, placements: Array,
		bridges: Array = [], spots: Dictionary = {}) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return  # only the host sends the map; the rpc mode already refuses others
	var params = MapGenParams.new()
	params.from_dict(data)
	world_params = params
	get_node("/root/MapGen").params = params.duplicate_params()
	_apply_params_to_world(params)
	get_node("World/worldMap").replace_cuts(cuts)  # the host's set, before the chunks are drawn again
	get_node("World/worldMap").replace_structures(placements)  # likewise, before the player is placed
	get_node("World/worldMap").replace_bridges(bridges)  # plank bridges (#297)
	_own_spot = spot
	_apply_player_spots(spots)  # other players' server spots (#352), before any draw
	_place_own_player()  # or once the player arrives, see _on_world_child_entered
	var world = get_node("World/worldMap")
	world.player_spawned = true


@rpc("authority", "reliable", "call_remote")
func receive_player_spots(spots: Dictionary) -> void:
	## Host: a player just spawned (or moved onto its join spot). Remotes put
	## their copy on that spot at once (#352), so they never show (0, 0) while
	## waiting for the owner's MultiplayerSynchronizer.
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_player_spots(spots)


@rpc("authority", "reliable", "call_remote")
func receive_join_cuts(cuts: Dictionary) -> void:
	## The rest of the host's cut list after receive_map_params (#354): added
	## to the cuts that message replaced, on the same reliable channel, so
	## they land before any later cut or regrowth.
	if multiplayer.get_remote_sender_id() != 1:
		return  # only the host sends the map; the rpc mode already refuses others
	get_node("World/worldMap").restore_cuts(cuts)


func add_player(peer_id):
	# host / peer spawn
	var player = Player.instantiate()
	player.name = str(peer_id)
	print("player added", player.name)
	player.position = _land_spawn_position(player)
	get_node("/root/Flagoria/World").add_child(player)
	# Remotes' MultiplayerSpawner copies start at (0, 0) until the owner's
	# sync; send the server's spot so every peer draws them in place (#352).
	rpc("receive_player_spots", {str(peer_id): player.position})

	var world = get_node("World/worldMap")
	world.player_spawned = true


func add_player_joined(port: int = PORT):
	print("player_joined")
	var parsed: Dictionary = JoinAddress.parse(address_entry.text if address_entry != null else "")
	if not parsed["ok"]:
		_fail_join_address(str(parsed["error"]))
		return
	# A host:port in the field is the address Join dials. Callers that pass a
	# port and a host-only field (the join-fail drive, headless tests) keep
	# that port. An explicit port in the text wins, so the typed endpoint and
	# the socket agree.
	var host := str(parsed["host"])
	if parsed["explicit"]:
		port = int(parsed["port"])
	_join_host = host
	_join_port = port
	_join_address = str(parsed["endpoint"])
	# A fresh peer each attempt: close() then create_client on the same
	# object fails a second Join after a timeout.
	enet_peer.close()
	enet_peer = ENetMultiplayerPeer.new()
	var err := enet_peer.create_client(host, port)
	if err != OK:
		_on_join_failed()
		return
	multiplayer.multiplayer_peer = enet_peer
	_ensure_join_signals()
	# Fail faster than ENet's default when nothing answers (#348 tests).
	var peer := enet_peer.get_peer(1)
	if peer != null:
		peer.set_timeout(8, 800, 3000)
	var world = get_node("World/worldMap")
	world.player_spawned = true


func _ensure_join_signals() -> void:
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_connection_failed() -> void:
	_on_join_failed()


func _on_join_failed() -> void:
	## Close the peer and put the main menu back with "Could not join …" (#348).
	_close_join_peer()
	var menu := get_node("CanvasLayer2/MainMenu")
	menu.show_join_failed(_join_address if _join_address != "" else "localhost")


func _fail_join_address(message: String) -> void:
	## The field is not a host or host:port. No ENet client is opened.
	_close_join_peer()
	get_node("CanvasLayer2/MainMenu").show_address_error(message)


func _close_join_peer() -> void:
	enet_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var world = get_node_or_null("World/worldMap")
	if world:
		world.player_spawned = false


func _on_server_disconnected() -> void:
	## Host left mid-game: same return as the in-game Main menu button (#348).
	leave_to_main_menu()


func leave_to_main_menu() -> void:
	## Leave the match for the main menu (the in-game menu's Main menu).
	## Closes the network session, so the port is free to host again, then
	## reloads this scene: the world, players and mobs are freed, and the new
	## main menu starts its music as on launch.
	enet_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().reload_current_scene()


func quit_game() -> void:
	## Quit from the quit prompt: close the network session first, as leaving
	## for the main menu does, so other players see this one leave.
	enet_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if quit_hook.is_valid():
		quit_hook.call()
	else:
		get_tree().quit()


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
