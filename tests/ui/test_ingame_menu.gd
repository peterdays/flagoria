extends "res://tests/helpers/test_helpers.gd"
## In-game menu and the quit prompt on Back.


func _test_ingame_menu_open_resume() -> int:
	## During a match the HUD's three-bar menu button, or Esc, opens the in-game menu
	## and Resume, or Esc again, closes it. On the main menu Esc does nothing.
	## A closed menu leaves the open map to pinch zoom; an open one covers it.
	print("-- test_ingame_menu_open_resume")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var cam := Camera2D.new()
	var zoom := Node.new()
	zoom.set_script(load("res://Scripts/map_zoom.gd"))
	cam.add_child(zoom)
	root.add_child(cam)
	await process_frame
	var menu = scene.get_node_or_null("CanvasLayer1/InGameMenu")
	if menu == null:
		printerr("FAIL ingame_menu_open_resume: no in-game menu in the HUD")
		cam.queue_free()
		scene.queue_free()
		await process_frame
		return 1
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	if menu.is_open() or menu.menu_button.is_visible_in_tree():
		printerr("FAIL ingame_menu_open_resume: menu reachable from the main menu")
		fail += 1
	scene.get_node("CanvasLayer1").show()  # as Host and Join do
	var centre: Vector2 = scene.get_viewport().get_visible_rect().get_center()
	var corner: Vector2 = menu.menu_button.get_global_rect().get_center()
	if not menu.menu_button.is_visible_in_tree() or not zoom.starts_on_hud(corner) or zoom.starts_on_hud(centre):
		printerr("FAIL ingame_menu_open_resume: Menu button not shown, or the closed menu covers the map")
		fail += 1
	# A compact three-bar icon button, still a phone-sized tap target at
	# 1280x720, clear of the hearts and points in the other corner.
	var button_rect: Rect2 = menu.menu_button.get_global_rect()
	var tap_px: float = button_rect.size.x * 1280.0 / scene.get_viewport().get_visible_rect().size.x
	var hearts_rect: Rect2 = scene.get_node("CanvasLayer1/HeartsHud").get_global_rect()
	var score_rect: Rect2 = scene.get_node("CanvasLayer1/ScoreHud").get_global_rect()
	if menu.menu_button.text != "" or menu.menu_button.icon == null \
			or button_rect.size.x != button_rect.size.y or tap_px < 40.0 or tap_px > 48.5 \
			or button_rect.intersects(hearts_rect) or button_rect.intersects(score_rect):
		printerr(
			"FAIL ingame_menu_open_resume: menu button text=%s icon=%s rect=%s (%s px at 1280x720)"
			% [menu.menu_button.text, menu.menu_button.icon, button_rect, tap_px]
		)
		fail += 1
	menu.menu_button.pressed.emit()
	if not menu.is_open() or not zoom.starts_on_hud(centre):
		printerr("FAIL ingame_menu_open_resume: Menu button did not open the panel over the map")
		fail += 1
	menu.resume_button.pressed.emit()
	if menu.is_open() or not menu.menu_button.visible:
		printerr("FAIL ingame_menu_open_resume: Resume did not close the panel")
		fail += 1
	menu._unhandled_input(esc)
	var opened_by_esc: bool = menu.is_open()
	menu._unhandled_input(esc)
	if not opened_by_esc or menu.is_open():
		printerr("FAIL ingame_menu_open_resume: Esc open=%s, second Esc open=%s" % [opened_by_esc, menu.is_open()])
		fail += 1
	cam.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_ingame_menu_open_resume")
	return fail


func _test_ingame_menu_leave() -> int:
	## Main menu in the in-game menu returns to the main menu with no network
	## peer, players or errors left, and a second game hosts on the same port.
	## Runs tests/ingame_menu_probe.gd in its own process: leaving reloads the
	## current scene, which this test runner does not have.
	print("-- test_ingame_menu_leave")
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL ingame_menu_leave found no free UDP port")
		return 1
	var output := []
	var code := OS.execute(
		OS.get_executable_path(),
		[
			"--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "3000",
			"--script", "res://tests/ingame_menu_probe.gd", "--", "--port=%d" % port,
		],
		output,
		true
	)
	var log_text: String = "".join(output)
	if code != 0 or not log_text.contains("INGAME_MENU_PROBE_OK"):
		for line in log_text.split("\n"):
			if line.contains("ingame_menu_probe"):
				printerr(line)
		printerr("FAIL ingame_menu_leave probe exit=%s" % code)
		return 1
	print("PASS test_ingame_menu_leave")
	return 0


func _test_ingame_menu_save() -> int:
	## Save in the in-game menu writes the world being played as a world save
	## that load_world reads back with the same generation inputs, says so
	## under the buttons and keeps the menu open. A second save never
	## replaces the first; before the world has loaded nothing is written.
	print("-- test_ingame_menu_save")
	var fail := 0
	var ui = root.get_node("UiSfx")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer1/InGameMenu")
	scene.get_node("CanvasLayer1").show()  # as Host and Join do
	var before_saves := MapSave.list_saves().size()

	menu.menu_button.pressed.emit()
	var panel: Control = menu.get_node("Pause/Panel")
	var empty_height: float = panel.get_combined_minimum_size().y

	# The world as Host or Join leaves it: resolved seeds in world_params.
	var params := MapGenParams.make_defaults()
	params.altitude_seed = 4242
	params.ensure_seeds()
	params.water_max_alt = 0.37
	scene.world_params = params
	ui._last_ms.clear()
	var before_sfx: Dictionary = ui.plays.duplicate()
	menu.save_button.pressed.emit()
	var saves := MapSave.list_saves()
	var paths: Array[String] = []
	for row in saves:
		paths.append(row["path"])
	if saves.size() != before_saves + 1:
		printerr("FAIL ingame_menu_save: Save wrote %d files, want 1" % (saves.size() - before_saves))
		fail += 1
	else:
		var loaded := MapSave.load_world(saves[0]["path"])
		if loaded["error"] != "" or loaded["version"] != MapSave.FORMAT_VERSION \
				or loaded["world"].params.to_dict() != params.to_dict():
			printerr("FAIL ingame_menu_save: load_world error=%s version=%s same inputs=%s"
					% [loaded["error"], loaded["version"], loaded["world"] != null and loaded["world"].params.to_dict() == params.to_dict()])
			fail += 1
		var save_name: String = saves[0]["name"]
		var want := "Saved: %s %s" % [save_name.substr(5, 5), save_name.substr(11, 5).replace("-", ":")]
		if menu.status_label.text != want or not menu.status_label.is_visible_in_tree():
			printerr("FAIL ingame_menu_save: status '%s' for save %s, want '%s'" % [menu.status_label.text, save_name, want])
			fail += 1
		# One line, and the panel keeps the height it had before the save.
		var height: float = panel.get_combined_minimum_size().y
		if menu.status_label.get_line_count() != 1 or height != empty_height:
			printerr("FAIL ingame_menu_save: status on %d lines, panel %s tall, %s before the save"
					% [menu.status_label.get_line_count(), height, empty_height])
			fail += 1
	if not menu.is_open() or _ui_plays_since(ui, before_sfx).get("saved", 0) != 1:
		printerr("FAIL ingame_menu_save: menu open=%s, sounds %s" % [menu.is_open(), _ui_plays_since(ui, before_sfx)])
		fail += 1

	# A second save in the same second gets its own name.
	var again: Dictionary = menu.save_world()
	paths.append(again["path"])
	if again["error"] != "" or MapSave.list_saves().size() != before_saves + 2:
		printerr("FAIL ingame_menu_save: second save error=%s, %d files" % [again["error"], MapSave.list_saves().size() - before_saves])
		fail += 1
	var stamp: String = menu.auto_save_name({"year": 2026, "month": 3, "day": 4, "hour": 5, "minute": 6, "second": 7})
	if stamp != "2026-03-04 05-06-07" or stamp.validate_filename() != stamp:
		printerr("FAIL ingame_menu_save: auto name %s" % stamp)
		fail += 1

	# Before the world has loaded nothing is written.
	scene.world_params = null
	var early: Dictionary = menu.save_world()
	if early["error"] == "" or MapSave.list_saves().size() != before_saves + 2 or not menu.status_label.text.begins_with("Not saved"):
		printerr("FAIL ingame_menu_save: save before the world loaded error=%s status=%s" % [early["error"], menu.status_label.text])
		fail += 1

	menu.resume_button.pressed.emit()
	if menu.status_label.text != "":
		printerr("FAIL ingame_menu_save: status '%s' kept after Resume" % menu.status_label.text)
		fail += 1
	for path in paths:
		DirAccess.remove_absolute(path)
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_ingame_menu_save")
	return fail


func _test_quit_prompt_on_back() -> int:
	## Back (Android) or closing the window asks "Do you want to quit?"
	## instead of exiting, on the main menu and in a match. Cancel, Esc or a
	## second back closes the prompt and the game carries on; Quit closes the
	## network session and quits. The world is not paused behind the prompt.
	print("-- test_quit_prompt_on_back")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var prompt = scene.get_node_or_null("QuitLayer/QuitPrompt")
	if prompt == null:
		printerr("FAIL quit_prompt_on_back: no quit prompt in the main scene")
		scene.queue_free()
		await process_frame
		return 1
	var quits := []
	scene.quit_hook = func() -> void: quits.append(true)

	# Main menu: back opens the prompt, a second back closes it.
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if not prompt.is_open() or not quits.is_empty():
		printerr("FAIL quit_prompt_on_back: back on the main menu open=%s quits=%d" % [prompt.is_open(), quits.size()])
		fail += 1
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if prompt.is_open() or not quits.is_empty():
		printerr("FAIL quit_prompt_on_back: second back did not just close the prompt (open=%s quits=%d)" % [prompt.is_open(), quits.size()])
		fail += 1
	# Window close opens it too; Cancel closes it.
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var opened_by_close: bool = prompt.is_open()
	prompt.cancel_button.pressed.emit()
	if not opened_by_close or prompt.is_open() or not quits.is_empty():
		printerr("FAIL quit_prompt_on_back: window close open=%s, after Cancel open=%s quits=%d" % [opened_by_close, prompt.is_open(), quits.size()])
		fail += 1

	# In a match (a hosted session): Esc closes the prompt without opening the
	# in-game menu, the world keeps running, and Quit closes the session.
	var port := _free_udp_port()
	scene.enet_peer.create_server(port)
	scene.multiplayer.multiplayer_peer = scene.enet_peer
	scene.get_node("CanvasLayer1").show()  # as Host and Join do
	var menu = scene.get_node("CanvasLayer1/InGameMenu")
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	if prompt.is_open() or menu.is_open():
		printerr("FAIL quit_prompt_on_back: Esc in a match left prompt open=%s, in-game menu open=%s" % [prompt.is_open(), menu.is_open()])
		fail += 1
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if not prompt.is_open() or paused or not quits.is_empty():
		printerr("FAIL quit_prompt_on_back: back in a match open=%s paused=%s quits=%d" % [prompt.is_open(), paused, quits.size()])
		fail += 1
	prompt.quit_button.pressed.emit()
	if quits.size() != 1 or not scene.multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
			or scene.enet_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		printerr("FAIL quit_prompt_on_back: Quit quits=%d peer=%s" % [quits.size(), scene.multiplayer.multiplayer_peer])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_quit_prompt_on_back")
	return fail
