extends "res://tests/helpers/test_helpers.gd"
## A join that never connects returns to the main menu (#348).


func _test_join_fail_no_host() -> int:
	## Join a free UDP port with nothing listening: within the ENet timeout
	## the main menu is back, the HUD is hidden, and JoinStatus shows
	## "Could not join …". Time cost: ~1–3 s in verify (client peer timeout
	## max 3 s; ~2 s alone with --only= plus boot).
	print("-- test_join_fail_no_host")
	var fail := 0
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL join_fail_no_host found no free UDP port")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	if scene.get_path() != NodePath("/root/Flagoria"):
		printerr("FAIL join_fail_no_host scene at %s, not /root/Flagoria" % scene.get_path())
		scene.queue_free()
		return 1
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	var hud: CanvasLayer = scene.get_node("CanvasLayer1")
	var status: Label = menu.get_node("MarginContainer/VBoxContainer/JoinStatus")
	menu.hide()
	hud.show()
	scene.address_entry.text = "127.0.0.1"
	scene.add_player_joined(port)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if menu.visible and status.visible:
			break
		await process_frame
	var want := "Could not join 127.0.0.1"
	if not menu.visible:
		printerr("FAIL join_fail_no_host: main menu still hidden after failed join")
		fail += 1
	if hud.visible:
		printerr("FAIL join_fail_no_host: HUD still visible after failed join")
		fail += 1
	if not status.visible or status.text != want:
		printerr("FAIL join_fail_no_host: status '%s' visible=%s, want '%s'"
				% [status.text, status.visible, want])
		fail += 1
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_join_fail_no_host (port %s)" % port)
	return fail


func _test_join_fail_host_quits() -> int:
	## A client whose host process exits lands back on the main menu. Runs
	## tests/join_fail_probe.gd in its own process (leave reloads the current
	## scene). Time cost: ~3–6 s in verify (~8 s alone with --only=).
	print("-- test_join_fail_host_quits")
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL join_fail_host_quits found no free UDP port")
		return 1
	var output := []
	var code := OS.execute(
		OS.get_executable_path(),
		[
			"--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "20000",
			"--script", "res://tests/join_fail_probe.gd", "--", "--port=%d" % port,
		],
		output,
		true
	)
	var log_text: String = "".join(output)
	if code != 0 or not log_text.contains("JOIN_FAIL_PROBE_OK"):
		for line in log_text.split("\n"):
			if line.contains("join_fail_probe") or line.contains("FAIL"):
				printerr(line)
		printerr("FAIL join_fail_host_quits probe exit=%s" % code)
		return 1
	print("PASS test_join_fail_host_quits")
	return 0
