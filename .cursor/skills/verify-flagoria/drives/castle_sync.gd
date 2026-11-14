extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 7
## A client joins and receives a castle of their own. Snapshots: host-castles.
## The client writes client-castles.png in the same evidence directory.


const CLIENT_JOIN_S := 40.0
const CLIENT_SHOT_S := 25.0


func run() -> void:
	step("start")
	if not await start_game():
		return
	var capture: Node = current_scene.get_node("World/TowerCapture")
	capture.set_physics_process(false)
	for node in current_scene.get_node("World/Mobs").get_children():
		if node is Mob:
			node.global_position = Vector2(100000, 100000)
	var evidence := OS.get_environment("VERIFY_EVIDENCE_DIR")
	var client_out := evidence.path_join("client.json") if evidence != "" else ""
	var shot := evidence.path_join("client-castles.png") if evidence != "" else ""
	step("client-join")
	var pid := _launch_client(client_out, shot)
	if pid <= 0:
		printerr("castle sync: the client process did not start")
		done(false)
		return
	if not await wait_until(func() -> bool: return _ready(client_out), CLIENT_JOIN_S):
		printerr("castle sync: the client did not share the castles: %s" % _client(client_out))
		await _stop_client(pid, client_out)
		done(false)
		return
	step("host-castles")
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	hero().global_position = _viewpoint(map)
	if not await _phone():
		await _stop_client(pid, client_out)
		done(false)
		return
	await snapshot("host-castles")
	step("client-view")
	if shot != "" and not await wait_until(func() -> bool: return _client(client_out).get("shot", false), CLIENT_SHOT_S):
		printerr("castle sync: the client did not save its view: %s" % _client(client_out))
		await _stop_client(pid, client_out)
		done(false)
		return
	await _stop_client(pid, client_out)
	done(true)


func _ready(path: String) -> bool:
	var info := _client(path)
	if not info.get("ready", false) or str(info.get("id", "")) == "":
		return false
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var mine := 0
	var theirs := 0
	var builder := int(str(info.get("id")))
	for entry in map.placed_structures().values():
		if str(entry["name"]) != "castle":
			continue
		var owner := int(entry["owner"])
		if owner == 1:
			mine += 1
		elif owner == builder:
			theirs += 1
	if mine != 1 or theirs != 1:
		return false
	for row in info.get("castles", []):
		var owner := int(row.get("owner", 0))
		if owner != 1 and owner != builder:
			return false
	return info.get("castles", []).size() == 2


func _phone() -> bool:
	## Landscape phone window, the same size the explored-map drive uses.
	root.size = Vector2i(854, 480)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(854, 480))
	for _i in 10:
		await process_frame
	var got := DisplayServer.window_get_size()
	print("castle sync: phone window %s" % got)
	if got.x != 854 or got.y != 480:
		printerr("castle sync: window stayed %s" % got)
		return false
	return true


func _viewpoint(map: TileMap) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for entry in map.placed_structures().values():
		if str(entry["name"]) != "castle":
			continue
		var anchor: Vector2i = entry["anchor"]
		sum += Vector2(anchor)
		n += 1
	if n == 0:
		return hero().global_position
	var mid := Vector2i(roundi(sum.x / n), roundi(sum.y / n))
	return map.to_global(map.map_to_local(mid + Vector2i(0, 2)))


func _launch_client(client_out: String, shot: String) -> int:
	if client_out == "":
		printerr("castle sync: VERIFY_EVIDENCE_DIR is unset")
		return -1
	var config := OS.get_environment("XDG_CONFIG_HOME")
	var data := OS.get_environment("XDG_DATA_HOME")
	var cache := OS.get_environment("XDG_CACHE_HOME")
	if config == "" or data == "" or cache == "":
		printerr("castle sync: XDG user dirs are unset; launch.sh sets them")
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
		ProjectSettings.globalize_path("res://tests/castle_sync_probe.gd"),
		client_out, shot,
	]
	return OS.create_process("/bin/bash", ["-c", cmd])


func _client(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _stop_client(pid: int, client_out: String) -> void:
	if client_out != "":
		FileAccess.open(client_out + ".stop", FileAccess.WRITE).close()
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and OS.is_process_running(pid):
		await process_frame
	if OS.is_process_running(pid):
		OS.kill(pid)
