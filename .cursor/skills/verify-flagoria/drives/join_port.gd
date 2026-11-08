extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 42
## Join address: blank uses localhost:9786, a bad address is rejected on the
## menu, 127.0.0.1:1 times out with "Could not join 127.0.0.1:1", and
## 127.0.0.1:9799 joins a dedicated server started by this drive (#434).
## The address is typed and Join is clicked. Servers are loopback only.

const ADDRESS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/AddressEntry"
const JOIN := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinButton"
const STATUS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinStatus"
const MENU := "CanvasLayer2/MainMenu"
const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"

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
	await click(JOIN)
	if not await wait_until(func() -> bool: return hero() != null, 20.0):
		_end(false, "blank address did not spawn a player (port %s)" % current_scene._join_port)
		return
	print("join_port: default host=%s port=%s players=%s" % [
		current_scene._join_host, current_scene._join_port, _player_names()])
	await snapshot("joined-default")
	var default_ok: bool = str(current_scene._join_host) == "localhost" and int(current_scene._join_port) == 9786 and hero() != null
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
	await click(JOIN)
	var joined := await wait_until(func() -> bool: return hero() != null, 20.0)
	print("join_port: explicit host=%s port=%s field='%s' players=%s" % [
		current_scene._join_host, current_scene._join_port, _field().text, _player_names()])
	await snapshot("joined-9799")
	var explicit_ok: bool = joined and str(current_scene._join_host) == "127.0.0.1" and int(current_scene._join_port) == 9799 and _field().text == "127.0.0.1:9799" and hero() != null
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
	var pid := OS.create_process(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--", "--server", "--port=%d" % port,
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
