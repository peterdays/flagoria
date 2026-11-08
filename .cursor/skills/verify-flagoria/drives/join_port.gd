extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 42
## Join address: blank uses localhost:9786, a bad address is rejected on the
## menu, 127.0.0.1:1 times out with "Could not join 127.0.0.1:1", and
## 127.0.0.1:9799 joins a dedicated server started by this drive (#434).
## The address is typed and Join is clicked. Servers are loopback only.
## Each server loads its own map save, with seeds that are not the client's
## local MapGen fixture. World snapshots wait for those params, then for
## nearby layer-0 cells drawn after that apply.

const ADDRESS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/AddressEntry"
const JOIN := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinButton"
const STATUS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinStatus"
const MENU := "CanvasLayer2/MainMenu"
const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"
## 9x9 around the hero, the same square snapshot() records for foliage.
const NEARBY_RADIUS := 4
const NEARBY_CELLS := (NEARBY_RADIUS * 2 + 1) * (NEARBY_RADIUS * 2 + 1)
const PARAMS_TIMEOUT_S := 10.0
const GROUND_TIMEOUT_S := 10.0

var _pids: Array[int] = []


func run() -> void:
	if not await _start_server(9786) or not await _start_server(9799):
		_end(false)
		return
	step("menu")
	if change_scene_to_file(MAIN) != OK:
		_end(false, "cannot load " + MAIN)
		return
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(JOIN), START_TIMEOUT_S):
		_end(false, "no join button")
		return
	if not await wait_until(func() -> bool:
			var button: Control = current_scene.get_node(JOIN)
			return button.size.x > 1.0, 5.0):
		_end(false, "join button has no size")
		return
	print("VERIFY_READY pid=%d scene=%s" % [OS.get_process_id(), MAIN])

	step("default")
	await snapshot("default-address")
	var local_altitude := _local_altitude()
	await click(JOIN)
	if not await wait_until(func() -> bool: return hero() != null, 20.0):
		_end(false, "blank address did not spawn a player (port %s)" % current_scene._join_port)
		return
	var default_ready := await _await_server_ground(9786, local_altitude)
	if default_ready == "":
		return
	await snapshot("joined-default")
	var default_ok: bool = str(current_scene._join_host) == "localhost" and int(current_scene._join_port) == 9786 and hero() != null and _server_ground_ready(9786, local_altitude)
	if not await _back_to_menu():
		_end(false, "could not return to the menu after the default join")
		return

	step("invalid")
	if not await _type_address("host:abc"):
		_end(false, "could not type host:abc (field '%s')" % _field().text)
		return
	var started := Time.get_ticks_msec()
	await click(JOIN)
	var status := _status()
	var invalid_ms := Time.get_ticks_msec() - started
	var invalid_ok: bool = status.visible and status.text == "Enter a hostname or an IPv4 address, and an optional port from 1 to 65535." and _menu().visible and invalid_ms < 2000 and _field().text == "host:abc"
	print("join_port: invalid status='%s' field='%s' ms=%d" % [status.text, _field().text, invalid_ms])
	await snapshot("invalid-address")

	step("timeout")
	if not await _type_address("127.0.0.1:1"):
		_end(false, "could not type 127.0.0.1:1 (field '%s')" % _field().text)
		return
	started = Time.get_ticks_msec()
	await click(JOIN)
	status = _status()
	var back := await wait_until(func() -> bool:
			return _menu().visible and _status().visible and _status().text != "", 8.0)
	var timeout_ms := Time.get_ticks_msec() - started
	status = _status()
	var timeout_ok: bool = back and status.text == "Could not join 127.0.0.1:1" and _field().text == "127.0.0.1:1" and timeout_ms >= 250
	print("join_port: timeout status='%s' field='%s' ms=%d" % [status.text, _field().text, timeout_ms])
	await snapshot("join-timeout")

	step("join-9799")
	if not await _type_address("127.0.0.1:9799"):
		_end(false, "could not type 127.0.0.1:9799 (field '%s')" % _field().text)
		return
	local_altitude = _local_altitude()
	await click(JOIN)
	var joined := await wait_until(func() -> bool: return hero() != null, 20.0)
	if not joined:
		_end(false, "127.0.0.1:9799 did not spawn a player (port %s)" % current_scene._join_port)
		return
	var explicit_ready := await _await_server_ground(9799, local_altitude)
	if explicit_ready == "":
		return
	await snapshot("joined-9799")
	var explicit_ok: bool = str(current_scene._join_host) == "127.0.0.1" and int(current_scene._join_port) == 9799 and _field().text == "127.0.0.1:9799" and hero() != null and _server_ground_ready(9799, local_altitude)
	_end(default_ok and invalid_ok and timeout_ok and explicit_ok)


func _type_address(text: String) -> bool:
	await click(ADDRESS)
	var kb: Node = current_scene.get_node_or_null("CanvasLayer2/MainMenu/LetterKeyboard")
	if kb == null or not await wait_until(func() -> bool: return kb.visible, 2.0):
		return false
	await process_frame
	await process_frame
	for i in text.length():
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = text.unicode_at(i)
		root.push_input(ev)
		await process_frame
	var ok_key: Control = kb.find_child("OK", true, false) as Control
	if ok_key == null:
		return false
	await click(str(current_scene.get_path_to(ok_key)))
	return _field().text == text


func _back_to_menu() -> bool:
	await click(MENU_BUTTON)
	var panel: Control = current_scene.get_node(MENU_PANEL)
	if not await wait_until(func() -> bool: return panel.is_visible_in_tree(), 5.0):
		return false
	await click(MAIN_MENU_BUTTON)
	return await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(HOST_BUTTON), 10.0)


func _field() -> LineEdit:
	return current_scene.get_node(ADDRESS) as LineEdit


func _status() -> Label:
	return current_scene.get_node(STATUS) as Label


func _menu() -> Control:
	return current_scene.get_node(MENU) as Control


func _server_seeds(port: int) -> Array:
	## Fixed seeds for this listen port. They are not the launch --seed fixture
	## (42 and the four seeds after it) and not a randomized local map.
	var base := port * 100
	return [base + 1, base + 2, base + 3, base + 4, base + 5]


func _seed_list(params) -> Array:
	if params == null:
		return []
	return [params.altitude_seed, params.moisture_seed, params.temperature_seed, params.items_seed, params.biome_seed]


func _seeds_text(params) -> String:
	var values := _seed_list(params)
	if values.is_empty():
		return "none"
	return "%s,%s,%s,%s,%s" % values


func _local_altitude() -> int:
	var map_gen = root.get_node_or_null("MapGen")
	if map_gen == null or map_gen.params == null:
		return -1
	return int(map_gen.params.altitude_seed)


func _write_server_map(port: int) -> String:
	var params := MapGenParams.new()
	params.ensure_seeds()
	var seeds := _server_seeds(port)
	params.altitude_seed = seeds[0]
	params.moisture_seed = seeds[1]
	params.temperature_seed = seeds[2]
	params.items_seed = seeds[3]
	params.biome_seed = seeds[4]
	var saved: Dictionary = MapSave.save_map(params, "join_port_%d" % port)
	if str(saved["error"]) != "":
		printerr("join_port: could not write the server map for %d (%s)" % [port, saved["error"]])
		return ""
	return str(saved["path"])


func _ground_count() -> int:
	var h := hero()
	if h == null or current_scene == null:
		return 0
	var map: TileMap = current_scene.get_node_or_null(WORLD_MAP)
	if map == null:
		return 0
	var cell := map.local_to_map(map.to_local(h.global_position))
	var n := 0
	for dy in range(-NEARBY_RADIUS, NEARBY_RADIUS + 1):
		for dx in range(-NEARBY_RADIUS, NEARBY_RADIUS + 1):
			if map.get_cell_source_id(0, cell + Vector2i(dx, dy)) != -1:
				n += 1
	return n


func _params_are_server(port: int) -> bool:
	if current_scene == null:
		return false
	return _seed_list(current_scene.world_params) == _server_seeds(port)


func _server_ground_ready(port: int, local_altitude: int) -> bool:
	return _params_are_server(port) and int(current_scene.world_params.altitude_seed) != local_altitude and _ground_count() == NEARBY_CELLS


## "ok" on success. On failure the drive has already ended and this returns "".
func _await_server_ground(port: int, local_altitude: int) -> String:
	var params_ok := await wait_until(func() -> bool: return _params_are_server(port), PARAMS_TIMEOUT_S)
	if not params_ok:
		_end(false, "server map params did not arrive for port %d within %ss (world_params=%s local_altitude=%s)" % [
			port, PARAMS_TIMEOUT_S, _seeds_text(current_scene.world_params if current_scene else null), local_altitude])
		return ""
	# receive_map_params applies the server map and clears tiles in that call.
	# Cells counted after this wait were drawn from those params, not from the
	# client's earlier local chunk.
	var ground_ok := await wait_until(func() -> bool: return _params_are_server(port) and _ground_count() == NEARBY_CELLS, GROUND_TIMEOUT_S)
	var ground := _ground_count()
	if not ground_ok:
		_end(false, "nearby ground did not draw after server params for port %d within %ss (ground=%d/%d world_params=%s)" % [
			port, GROUND_TIMEOUT_S, ground, NEARBY_CELLS, _seeds_text(current_scene.world_params if current_scene else null)])
		return ""
	if int(current_scene.world_params.altitude_seed) == local_altitude:
		_end(false, "joined map altitude %s matches the client local fixture on port %d" % [local_altitude, port])
		return ""
	print("join_port: ready port=%d host=%s field='%s' players=%s seeds=%s local_altitude=%s ground=%d/%d" % [
		current_scene._join_port, current_scene._join_host, _field().text, _player_names(),
		_seeds_text(current_scene.world_params), local_altitude, ground, NEARBY_CELLS])
	return "ok"


func _player_names() -> String:
	var names: PackedStringArray = []
	for child in current_scene.get_node("World").get_children():
		if str(child.name).is_valid_int():
			names.append(str(child.name))
	return ",".join(names)


func _start_server(port: int) -> bool:
	if _udp_bound(port):
		printerr("join_port: UDP %d is already in use" % port)
		return false
	var params_path := _write_server_map(port)
	if params_path == "":
		return false
	var pid := OS.create_process(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--", "--server", "--port=%d" % port, "--params=%s" % params_path,
	])
	if pid <= 0:
		printerr("join_port: could not start the server on %d" % port)
		return false
	_pids.append(pid)
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if not OS.is_process_running(pid):
			printerr("join_port: server on %d exited before it listened" % port)
			return false
		if _udp_bound(port):
			print("join_port: listening %d" % port)
			return true
		await process_frame
	printerr("join_port: server on %d never listened" % port)
	return false


func _udp_bound(port: int) -> bool:
	## /proc UDP tables are not regular files, so FileAccess reads them empty.
	var needle := ":%04X" % port
	var output: Array = []
	var code := OS.execute("grep", ["-q", needle, "/proc/net/udp", "/proc/net/udp6"], output, true)
	return code == 0


func _stop_servers() -> void:
	for pid in _pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func _end(ok: bool, why := "") -> void:
	if why != "":
		printerr("join_port: " + why)
	_stop_servers()
	done(ok)
