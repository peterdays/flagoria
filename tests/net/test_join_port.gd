extends "res://tests/helpers/test_helpers.gd"
## Main Menu Join: hostname or IPv4, optional :port, default 9786 (#434).
## Every case presses MainMenu._on_join_button_pressed. The address field
## is left as typed. A bad address is rejected on the menu with no dial.
## Port 1 is a real port: nothing is listening, and the menu must say
## "Could not join 127.0.0.1:1".

const JoinAddress = preload("res://Scripts/join_address.gd")
const Main = preload("res://flagoria_main.gd")

const ADDRESS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/AddressEntry"
const STATUS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinStatus"


func _test_join_port_button() -> int:
	## Button presses for blank, bare hosts, explicit ports, rejected forms,
	## and one no-listener port-1 timeout. No second process. Time cost:
	## ~4 s in verify (the port-1 wait is the ENet timeout, about 3 s).
	print("-- test_join_port_button")
	var fail := 0
	if JoinAddress.DEFAULT_PORT != Main.PORT:
		printerr("FAIL join_port_button default port %s, flagoria PORT %s" % [JoinAddress.DEFAULT_PORT, Main.PORT])
		return 1
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if scene.get_path() != NodePath("/root/Flagoria"):
		printerr("FAIL join_port_button scene at %s" % scene.get_path())
		_drop_scene(scene)
		return 1
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	var hud: CanvasLayer = scene.get_node("CanvasLayer1")

	for row in [
		[":9799", JoinAddress.ERROR_ADDRESS],
		["host:", JoinAddress.ERROR_ADDRESS],
		["host:abc", JoinAddress.ERROR_ADDRESS],
		["host:0", JoinAddress.ERROR_PORT],
		["host:65536", JoinAddress.ERROR_PORT],
		["::1", JoinAddress.ERROR_UNSUPPORTED],
		["[::1]:9799", JoinAddress.ERROR_UNSUPPORTED],
		["host:1:2", JoinAddress.ERROR_UNSUPPORTED],
	]:
		var typed: String = row[0]
		var want: String = row[1]
		scene.get_node(ADDRESS).text = typed
		var started := Time.get_ticks_msec()
		menu._on_join_button_pressed()
		var elapsed := Time.get_ticks_msec() - started
		var status: Label = scene.get_node(STATUS)
		if not menu.visible or hud.visible or not status.visible or status.text != want:
			printerr("FAIL join_port_button reject '%s': menu=%s hud=%s status='%s' want '%s'" % [
				typed, menu.visible, hud.visible, status.text, want])
			fail += 1
		if scene.get_node(ADDRESS).text != typed:
			printerr("FAIL join_port_button reject '%s' rewrote the field to '%s'" % [typed, scene.get_node(ADDRESS).text])
			fail += 1
		if scene._join_port != 0 or scene._join_host != "":
			printerr("FAIL join_port_button reject '%s' still dialed %s:%s" % [typed, scene._join_host, scene._join_port])
			fail += 1
		if elapsed > 300:
			printerr("FAIL join_port_button reject '%s' took %d ms (no dial should be immediate)" % [typed, elapsed])
			fail += 1
		if status.text.begins_with("Could not join"):
			printerr("FAIL join_port_button reject '%s' used the timeout message" % typed)
			fail += 1

	for row in [
		["", "localhost", JoinAddress.DEFAULT_PORT, "localhost"],
		["   ", "localhost", JoinAddress.DEFAULT_PORT, "localhost"],
		["127.0.0.1", "127.0.0.1", JoinAddress.DEFAULT_PORT, "127.0.0.1"],
		["localhost", "localhost", JoinAddress.DEFAULT_PORT, "localhost"],
		["127.0.0.1:65535", "127.0.0.1", 65535, "127.0.0.1:65535"],
		["localhost:9799", "localhost", 9799, "localhost:9799"],
	]:
		fail += _dial(scene, menu, hud, row[0], row[1], row[2], row[3], false)

	# DNS for this name fails immediately. The port is still the default,
	# and the menu names the typed host rather than calling it invalid.
	fail += _dial(scene, menu, hud, "my-host.local", "my-host.local", JoinAddress.DEFAULT_PORT, "my-host.local", true)

	scene.get_node(ADDRESS).text = "127.0.0.1:1"
	var started := Time.get_ticks_msec()
	menu._on_join_button_pressed()
	var status: Label = scene.get_node(STATUS)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if menu.visible and status.visible and status.text != "":
			break
		await process_frame
	var elapsed := Time.get_ticks_msec() - started
	var want := "Could not join 127.0.0.1:1"
	if status.text != want or not menu.visible or hud.visible:
		printerr("FAIL join_port_button port 1: menu=%s hud=%s status='%s' want '%s' (%d ms)" % [
			menu.visible, hud.visible, status.text, want, elapsed])
		fail += 1
	elif scene._join_host != "127.0.0.1" or scene._join_port != 1:
		printerr("FAIL join_port_button port 1 dialed %s:%s" % [scene._join_host, scene._join_port])
		fail += 1
	elif elapsed < 250:
		printerr("FAIL join_port_button port 1 returned in %d ms; want the no-listener wait" % elapsed)
		fail += 1
	if scene.get_node(ADDRESS).text != "127.0.0.1:1":
		printerr("FAIL join_port_button port 1 rewrote the field to '%s'" % scene.get_node(ADDRESS).text)
		fail += 1

	# After the timeout the menu can reject again, then dial the default port.
	scene.get_node(ADDRESS).text = "host:abc"
	var again := Time.get_ticks_msec()
	menu._on_join_button_pressed()
	status = scene.get_node(STATUS)
	if status.text != JoinAddress.ERROR_ADDRESS or not menu.visible or Time.get_ticks_msec() - again > 300:
		printerr("FAIL join_port_button retry reject after timeout: status='%s'" % status.text)
		fail += 1
	fail += _dial(scene, menu, hud, "", "localhost", JoinAddress.DEFAULT_PORT, "localhost", false)

	_drop_scene(scene)
	if fail == 0:
		print("PASS test_join_port_button")
	return fail


func _dial(scene, menu: Node, hud: CanvasLayer, typed: String, host: String, port: int, endpoint: String, resolve_fails: bool) -> int:
	scene.get_node(ADDRESS).text = typed
	var started := Time.get_ticks_msec()
	menu._on_join_button_pressed()
	var elapsed := Time.get_ticks_msec() - started
	var status: Label = scene.get_node(STATUS)
	var fail := 0
	if scene.get_node(ADDRESS).text != typed:
		printerr("FAIL join_port_button dial '%s' rewrote the field to '%s'" % [typed, scene.get_node(ADDRESS).text])
		fail += 1
	if scene._join_host != host or scene._join_port != port or scene._join_address != endpoint:
		printerr("FAIL join_port_button dial '%s' -> %s:%s endpoint '%s', want %s:%s '%s'" % [
			typed, scene._join_host, scene._join_port, scene._join_address, host, port, endpoint])
		fail += 1
	if resolve_fails:
		if status.text != "Could not join %s" % endpoint or not menu.visible:
			printerr("FAIL join_port_button dial '%s' status='%s' menu=%s" % [typed, status.text, menu.visible])
			fail += 1
	else:
		if menu.visible or not hud.visible:
			printerr("FAIL join_port_button dial '%s' did not leave the menu (status='%s')" % [typed, status.text])
			fail += 1
		_abort_dial(scene)
	if elapsed > 1000:
		printerr("FAIL join_port_button dial '%s' took %d ms" % [typed, elapsed])
		fail += 1
	return fail


func _abort_dial(scene) -> void:
	var mp = scene.multiplayer
	if mp.connection_failed.is_connected(scene._on_connection_failed):
		mp.connection_failed.disconnect(scene._on_connection_failed)
	if mp.server_disconnected.is_connected(scene._on_server_disconnected):
		mp.server_disconnected.disconnect(scene._on_server_disconnected)
	scene.enet_peer.close()
	mp.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.get_node("CanvasLayer2/MainMenu").show()
	scene.get_node("CanvasLayer1").hide()


func _drop_scene(scene) -> void:
	if scene == null:
		return
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()


func _test_join_port_dedicated() -> int:
	## A headless `--server` on a free port, then Join through the button at
	## 127.0.0.1:port and localhost:port. Each client gets a World player and
	## the server spawns no player 1. An invalid address on the same menu
	## does not block the following join. Time cost: ~8 s in verify, and
	## ~8 s x 20 in netcode stress (one scenario, 4 at a time).
	print("-- test_join_port_dedicated")
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL join_port_dedicated found no free UDP port")
		return 1
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("FAIL join_port_dedicated could not start the server")
		return 1
	var fail := 0
	fail += await _button_join(pid, "host:abc", JoinAddress.ERROR_ADDRESS, false, port)
	if fail == 0:
		fail += await _button_join(pid, "127.0.0.1:%d" % port, "", true, port)
	if fail == 0:
		fail += await _button_join(pid, "localhost:%d" % port, "", true, port)
	if OS.is_process_running(pid):
		OS.kill(pid)
	if fail == 0:
		print("PASS test_join_port_dedicated (port %s)" % port)
	return fail


func _button_join(pid: int, typed: String, error_text: String, want_player: bool, port: int) -> int:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	var hud: CanvasLayer = scene.get_node("CanvasLayer1")
	var status: Label = scene.get_node(STATUS)
	scene.get_node(ADDRESS).text = typed
	menu._on_join_button_pressed()
	var fail := 0
	if not want_player:
		if not menu.visible or hud.visible or status.text != error_text:
			printerr("FAIL join_port_dedicated reject '%s' status='%s' menu=%s" % [typed, status.text, menu.visible])
			fail = 1
		if scene._join_port != 0:
			printerr("FAIL join_port_dedicated reject '%s' dialed port %s" % [typed, scene._join_port])
			fail = 1
	else:
		var deadline := Time.get_ticks_msec() + 30000
		var client_id := 0
		var world: Node = scene.get_node("World")
		while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
			client_id = scene.multiplayer.get_unique_id()
			var params_ok: bool = scene.world_params != null and scene.world_params.altitude_seed != 0
			if params_ok and client_id != 1 and world.has_node(str(client_id)):
				break
			await process_frame
		if not OS.is_process_running(pid):
			printerr("FAIL join_port_dedicated server exited before '%s' joined" % typed)
			fail = 1
		elif scene.world_params == null or not world.has_node(str(client_id)) or world.has_node("1"):
			printerr("FAIL join_port_dedicated '%s' player=%s params=%s node1=%s port=%s" % [
				typed, client_id, scene.world_params != null, world.has_node("1"), scene._join_port])
			fail = 1
		elif scene._join_host == "" or scene._join_port != port or scene.get_node(ADDRESS).text != typed:
			printerr("FAIL join_port_dedicated '%s' dialed %s:%s field '%s'" % [
				typed, scene._join_host, scene._join_port, scene.get_node(ADDRESS).text])
			fail = 1
	_drop_scene(scene)
	await process_frame
	return fail
