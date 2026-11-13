extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 7
## A client builds a tower and steps aside. The host captures it with
## TowerCapture.tick. Snapshots: tower-tool, host-captured, client-captured.png.


const CAPTURE_STEPS := 40  ## 40 * 0.125 s = TowerCapture.CAPTURE_TIME
const CLIENT_JOIN_S := 30.0
const CLIENT_SHOT_S := 20.0


func run() -> void:
	step("start")
	if not await start_game():
		return
	for node in current_scene.get_node("World/Mobs").get_children():
		if node is Mob:
			node.global_position = Vector2(100000, 100000)
	var evidence := OS.get_environment("VERIFY_EVIDENCE_DIR")
	var client_out := evidence.path_join("client.json") if evidence != "" else ""
	var shot := evidence.path_join("client-captured.png") if evidence != "" else ""
	step("client-join")
	var pid := _launch_client(client_out, shot)
	if pid <= 0:
		printerr("tower capture: the client process did not start")
		done(false)
		return
	if not await wait_until(func() -> bool: return _client(client_out).get("ready", false), CLIENT_JOIN_S):
		printerr("tower capture: the client did not join: %s" % _client(client_out))
		await _stop_client(pid, client_out)
		done(false)
		return
	step("tower-tool")
	await toggle_mode()
	var it: Node = current_scene.get_node(INTERACTION)
	if not await wait_until(func() -> bool: return it.mode == 1, 2.0):
		printerr("tower capture: interact mode did not open")
		await _stop_client(pid, client_out)
		done(false)
		return
	await click("CanvasLayer1/BuildingsButton")
	var tower_btn := current_scene.get_node_or_null("CanvasLayer1/BuildPicker/TowerButton") as Button
	if not await wait_until(func() -> bool: return tower_btn != null and tower_btn.visible, 2.0):
		printerr("tower capture: the Tower tool was not visible with a peer connected")
		await _stop_client(pid, client_out)
		done(false)
		return
	await snapshot("tower-tool")
	step("built")
	if not await wait_until(func() -> bool:
		var info := _client(client_out)
		var builder := int(str(info.get("id", "0")))
		return info.get("aside", false) and builder > 1 and _owner() == builder, CLIENT_JOIN_S):
		printerr("tower capture: the client did not build a tower: %s" % _client(client_out))
		await _stop_client(pid, client_out)
		done(false)
		return
	step("capture")
	var capture: Node = current_scene.get_node("World/TowerCapture")
	capture.set_physics_process(false)
	for node in current_scene.get_node("World/Mobs").get_children():
		if node is Mob:
			node.global_position = Vector2(100000, 100000)
	var flag: Vector2i = _flag()
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	hero().global_position = map.to_global(map.map_to_local(flag))
	for _i in CAPTURE_STEPS:
		capture.tick(0.125)
	if _owner() != 1:
		printerr("tower capture: owner after %d ticks is %d, want the host" % [CAPTURE_STEPS, _owner()])
		await _stop_client(pid, client_out)
		done(false)
		return
	await snapshot("host-captured")
	step("client-view")
	if shot != "" and not await wait_until(func() -> bool: return _client(client_out).get("shot", false), CLIENT_SHOT_S):
		printerr("tower capture: the client did not save its view: %s" % _client(client_out))
		await _stop_client(pid, client_out)
		done(false)
		return
	await _stop_client(pid, client_out)
	done(true)


func _launch_client(client_out: String, shot: String) -> int:
	if client_out == "":
		printerr("tower capture: VERIFY_EVIDENCE_DIR is unset")
		return -1
	var config := OS.get_environment("XDG_CONFIG_HOME")
	var data := OS.get_environment("XDG_DATA_HOME")
	var cache := OS.get_environment("XDG_CACHE_HOME")
	if config == "" or data == "" or cache == "":
		printerr("tower capture: XDG user dirs are unset; launch.sh sets them")
		return -1
	DirAccess.make_dir_recursive_absolute(config.path_join("client"))
	DirAccess.make_dir_recursive_absolute(data.path_join("client"))
	DirAccess.make_dir_recursive_absolute(cache.path_join("client"))
	var godot := OS.get_executable_path()
	var args := ""
	if DisplayServer.get_name() == "headless":
		args = "--headless "
	else:
		args = "--rendering-driver opengl3 "
	var cmd := "export XDG_CONFIG_HOME='%s' XDG_DATA_HOME='%s' XDG_CACHE_HOME='%s'; exec '%s' %s--path '%s' --script '%s' -- --port=9786 --out='%s' --mode=drive --shot='%s'" % [
		config.path_join("client"), data.path_join("client"), cache.path_join("client"),
		godot, args, ProjectSettings.globalize_path("res://"),
		ProjectSettings.globalize_path("res://tests/tower_sync_probe.gd"),
		client_out, shot,
	]
	return OS.create_process("/bin/bash", ["-c", cmd])


func _client(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _tower() -> Dictionary:
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var placed: Dictionary = map.placed_structures()
	var towers: Dictionary = map._structures.towers()
	for id in placed.keys():
		if str(placed[id]["name"]) == "tower_wood" and towers.has(id):
			return {"owner": int(placed[id]["owner"]), "flag": towers[id][0]}
	return {}


func _owner() -> int:
	var info := _tower()
	return int(info["owner"]) if not info.is_empty() else -1


func _flag() -> Vector2i:
	return _tower()["flag"]


func _stop_client(pid: int, client_out: String) -> void:
	if client_out != "":
		FileAccess.open(client_out + ".stop", FileAccess.WRITE).close()
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and OS.is_process_running(pid):
		await process_frame
	if OS.is_process_running(pid):
		OS.kill(pid)
