extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --display
## Two players, discovery points on the host, open scoreboard, phone snapshot (#509).

const SCORE_TOGGLE := "CanvasLayer1/ScoreHud/Toggle"
const CLIENT_JOIN_S := 30.0
const SCOREBOARD := "CanvasLayer1/ScoreboardPanel"


func run() -> void:
	step("start")
	if not await start_game():
		return
	var evidence := OS.get_environment("VERIFY_EVIDENCE_DIR")
	var client_out := evidence.path_join("client.json") if evidence != "" else ""
	step("client-join")
	var pid := _launch_client(client_out)
	if pid <= 0:
		done(false)
		return
	if client_out != "" and not await wait_until(func() -> bool: return _client(client_out).get("ready", false), CLIENT_JOIN_S):
		printerr("points_scoreboard: the client did not join: %s" % _client(client_out))
		await _stop_client(pid, client_out)
		done(false)
		return
	if not await wait_until(func() -> bool: return _player_count() >= 2, CLIENT_JOIN_S):
		printerr("points_scoreboard: fewer than two players under World")
		await _stop_client(pid, client_out)
		done(false)
		return
	step("points")
	await hold("ui_right", 90)
	await hold("ui_down", 45)
	var me: int = get_multiplayer().get_unique_id()
	var pts: Points = current_scene.get_node("Points")
	print("points_scoreboard: host total %s after walking" % pts.total_of(me))
	step("scoreboard")
	await click(SCORE_TOGGLE)
	var panel: ScoreboardPanel = current_scene.get_node(SCOREBOARD)
	var opened := await wait_until(func() -> bool: return panel.is_open(), 3.0)
	var rows := panel.sorted_rows() if opened else []
	print("points_scoreboard: open=%s rows=%s" % [opened, rows])
	if not opened or rows.size() < 2:
		printerr("points_scoreboard: scoreboard did not open with two rows: %s" % rows)
		await _stop_client(pid, client_out)
		done(false)
		return
	await snapshot("phone-scoreboard")
	await _stop_client(pid, client_out)
	done(true)


func _player_count() -> int:
	return current_scene.get_node("World").get_child_count() if current_scene else 0


func _launch_client(client_out: String) -> int:
	if client_out == "":
		printerr("points_scoreboard: VERIFY_EVIDENCE_DIR is unset")
		return -1
	var config := OS.get_environment("XDG_CONFIG_HOME")
	var data := OS.get_environment("XDG_DATA_HOME")
	var cache := OS.get_environment("XDG_CACHE_HOME")
	if config == "" or data == "" or cache == "":
		printerr("points_scoreboard: XDG user dirs are unset; launch.sh sets them")
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
	var cmd := "export XDG_CONFIG_HOME='%s' XDG_DATA_HOME='%s' XDG_CACHE_HOME='%s'; exec '%s' %s--path '%s' --script '%s' -- --port=9786 --out='%s'" % [
		config.path_join("client"), data.path_join("client"), cache.path_join("client"),
		godot, args, ProjectSettings.globalize_path("res://"),
		ProjectSettings.globalize_path("res://tests/scoreboard_join_probe.gd"),
		client_out,
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