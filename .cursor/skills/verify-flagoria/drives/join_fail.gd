extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 42
## Failed Join returns to the main menu with "Could not join …" (#348).
## Joins a free UDP port with nothing listening, then snapshots the menu.


func run() -> void:
	step("menu")
	if change_scene_to_file(MAIN) != OK:
		_fail("cannot load " + MAIN)
		return
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node("CanvasLayer2/MainMenu"), START_TIMEOUT_S):
		_fail("no main menu")
		return
	print("VERIFY_READY pid=%d scene=%s" % [OS.get_process_id(), MAIN])
	var menu: Node = current_scene.get_node("CanvasLayer2/MainMenu")
	var hud: CanvasLayer = current_scene.get_node("CanvasLayer1")
	var status: Label = menu.get_node("MarginContainer/VBoxContainer/JoinStatus")
	var address: LineEdit = menu.get_node("MarginContainer/VBoxContainer/AddressEntry")
	# Pick a free port so create_client is OK but nothing answers.
	var port := _free_port()
	if port == 0:
		printerr("join_fail: no free UDP port")
		done(false)
		return
	current_scene.host_port = port  # unused for join; keep aside
	address.text = "127.0.0.1"
	# Override PORT used by add_player_joined default by calling it with port
	# after the button would fire — press Join then immediately re-issue with port.
	await snapshot("before-join")
	step("join")
	# Mirror the button: hide menu / show HUD / game music, then join `port`.
	menu.hide()
	hud.show()
	var music = root.get_node("MusicPlayer")
	music.play(music.GAME_TRACK)
	current_scene.add_player_joined(port)
	var back := await wait_until(
		func() -> bool: return menu.visible and status.visible, 8.0
	)
	print("join_fail: menu_back=%s status='%s'" % [back, status.text])
	var ok := back and status.text == "Could not join 127.0.0.1" and not hud.visible
	await snapshot("join-failed")
	done(ok)


func _free_port() -> int:
	## Same idea as test helpers: bind UDP port 0, read the OS pick, close.
	var udp := PacketPeerUDP.new()
	if udp.bind(0, "127.0.0.1") != OK:
		return 0
	var p := udp.get_local_port()
	udp.close()
	return p
