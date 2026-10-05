extends SceneTree
## Loads the main scene and spawns a local player, then quits.
## Run as a subprocess by test_player_spawn_no_missing_nodes in run_tests.gd,
## which checks this process's output for "Node not found".

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("spawn_player_probe: cannot load main scene")
		quit(1)
		return
	for i in range(5):
		await process_frame
	var peer_id := get_multiplayer().get_unique_id()
	current_scene.add_player(peer_id)
	for i in range(5):
		await process_frame
	if not current_scene.has_node("World/%s" % peer_id):
		printerr("spawn_player_probe: player not spawned")
		quit(1)
		return
	print("SPAWN_PROBE_OK")
	quit(0)
