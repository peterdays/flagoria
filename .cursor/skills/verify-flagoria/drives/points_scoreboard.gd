extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --display
## Four players, discovery points on the host, open scoreboard, phone snapshot (#509).

const SCORE_TOGGLE := "CanvasLayer1/ScoreboardToggle"
const CLIENT_JOIN_S := 45.0
const SCOREBOARD := "CanvasLayer1/ScoreboardPanel"
const MIN_PLAYERS := 4


func run() -> void:
	step("start")
	if not await start_game():
		return
	var evidence := OS.get_environment("VERIFY_EVIDENCE_DIR")
	if evidence == "":
		printerr("points_scoreboard: VERIFY_EVIDENCE_DIR is unset")
		done(false)
		return
	step("four-clients")
	var pids: Array = []
	var outs: Array = []
	for i in MIN_PLAYERS - 1:
		var name := "client" if i == 0 else "client%d" % (i + 1)
		var out := evidence.path_join("%s.json" % name)
		var pid := _launch_client(out, name, MIN_PLAYERS)
		if pid <= 0:
			await _stop_clients(pids, outs)
			done(false)
			return
		pids.append(pid)
		outs.append(out)
		if not await wait_until(func() -> bool: return _client(out).get("ready", false), CLIENT_JOIN_S):
			printerr("points_scoreboard: joiner %s did not become ready: %s" % [name, _client(out)])
			await _stop_clients(pids, outs)
			done(false)
			return
	if not await wait_until(func() -> bool: return _player_count() >= MIN_PLAYERS, CLIENT_JOIN_S):
		printerr("points_scoreboard: fewer than %d players under World" % MIN_PLAYERS)
		await _stop_clients(pids, outs)
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
	var labels := panel.display_lines() if opened else PackedStringArray()
	print("points_scoreboard: open=%s rows=%s lines=%s" % [opened, rows, labels])
	if not opened or rows.size() < MIN_PLAYERS:
		printerr("points_scoreboard: scoreboard missing rows: %s" % rows)
		await _stop_clients(pids, outs)
		done(false)
		return
	for line in labels:
		var t := str(line)
		if not t.begins_with("You") and not t.begins_with("Player"):
			printerr("points_scoreboard: unreadable label %s" % t)
			await _stop_clients(pids, outs)
			done(false)
			return
	await snapshot("phone-scoreboard")
	await _stop_clients(pids, outs)
	done(true)


func _player_count() -> int:
	return current_scene.get_node("World").get_child_count() if current_scene else 0


func _launch_client(client_out: String, client_name: String, min_players: int) -> int:
	var config := OS.get_environment("XDG_CONFIG_HOME")
	var data := OS.get_environment("XDG_DATA_HOME")
	var cache := OS.get_environment("XDG_CACHE_HOME")
	if config == "" or data == "" or cache == "":
		printerr("points_scoreboard: XDG user dirs are unset; launch.sh sets them")
		return -1
	var sub := client_name
	DirAccess.make_dir_recursive_absolute(config.path_join(sub))
	DirAccess.make_dir_recursive_absolute(data.path_join(sub))
	DirAccess.make_dir_recursive_absolute(cache.path_join(sub))
	var godot := OS.get_executable_path()
	var args := ""
	if DisplayServer.get_name() == "headless":
		args = "--headless "
	else:
		args = "--rendering-driver opengl3 "
	var cmd := "export XDG_CONFIG_HOME='%s' XDG_DATA_HOME='%s' XDG_CACHE_HOME='%s'; exec '%s' %s--path '%s' --script '%s' -- --port=9786 --min-players=%d --out='%s'" % [
		config.path_join(sub), data.path_join(sub), cache.path_join(sub),
		godot, args, ProjectSettings.globalize_path("res://"),
		ProjectSettings.globalize_path("res://tests/scoreboard_join_probe.gd"),
		min_players, client_out,
	]
	return OS.create_process("/bin/bash", ["-c", cmd])


func _client(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _stop_clients(pids: Array, outs: Array) -> void:
	for out in outs:
		if str(out) != "":
			FileAccess.open(str(out) + ".stop", FileAccess.WRITE).close()
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until:
		var running := false
		for pid in pids:
			if OS.is_process_running(pid):
				running = true
				break
		if not running:
			break
		await process_frame
	for pid in pids:
		if OS.is_process_running(pid):
			OS.kill(pid)