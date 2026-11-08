extends SceneTree
## Host process that joins a published UDP port. The address is whatever
## --address= says (the smoke passes 127.0.0.1). It is not a container on
## the server's compose network.
##
##   --address=127.0.0.1 --port=9786 --out=PATH
##
## Writes JSON every 100 ms. PATH.walk holds an input action. PATH.stop ends it.


var _out := ""
var _walking := ""
var _id := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var address := ""
	var port := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--address="):
			address = arg.trim_prefix("--address=")
		elif arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if address == "" or port == 0 or _out == "":
		printerr("docker_publish_probe: needs --address= --port= --out=")
		quit(1)
		return
	if change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("docker_publish_probe: cannot load the main scene")
		quit(1)
		return
	for _i in 3:
		await process_frame
	var main = current_scene
	main.address_entry.text = address
	print("JOIN_DIAL text=%s port_arg=%s" % [main.address_entry.text, port])
	main.add_player_joined(port)
	print("JOIN_ENDPOINT host=%s port=%s endpoint=%s" % [main._join_host, main._join_port, main._join_address])
	var world: Node = main.get_node("World")
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(_out + ".stop"):
		_id = main.multiplayer.get_unique_id()
		var walk := ""
		if FileAccess.file_exists(_out + ".walk"):
			walk = FileAccess.get_file_as_string(_out + ".walk").strip_edges()
		if walk != _walking:
			if _walking != "":
				Input.action_release(_walking)
			if walk != "" and InputMap.has_action(walk):
				Input.action_press(walk)
			_walking = walk
		if Time.get_ticks_msec() >= next_write:
			next_write = Time.get_ticks_msec() + 100
			_write(main, world)
		await process_frame
	_write(main, world)
	quit(0)


func _write(main: Node, world: Node) -> void:
	var players := {}
	for child in world.get_children():
		if child is CharacterBody2D and str(child.name).is_valid_int():
			players[str(child.name)] = [child.position.x, child.position.y]
	var seed_value := 0
	if main.world_params != null:
		seed_value = int(main.world_params.altitude_seed)
	var status := -1
	var peer = main.multiplayer.multiplayer_peer
	if peer != null:
		status = int(peer.get_connection_status())
	var file := FileAccess.open(_out + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"id": str(_id),
		"endpoint": "%s:%s" % [main._join_host, main._join_port],
		"status": status,
		"seed": seed_value,
		"players": players,
	}))
	file.close()
	DirAccess.rename_absolute(_out + ".tmp", _out)
