extends "res://tests/helpers/test_helpers.gd"
## Run control: hold, tap, the run key, walk speed, and two players.


func _test_run_control() -> int:
	## The Run button sits beside the attack button and is smaller than it.
	## A long press runs only
	## while it is down; a short press latches. Shift holds run without
	## latching. Run speed is faster than the walk, and releasing the control
	## returns to the walk cap. The joystick axis, chop reach and sword do
	## not change.
	print("-- test_run_control")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var body = load("res://Player/character_body_2d.tscn").instantiate()
	body.name = str(scene.multiplayer.get_unique_id())
	body.collision_layer = 0
	body.collision_mask = 0
	scene.get_node("World").add_child(body)
	await process_frame
	await process_frame
	var run_button = scene.get_node("CanvasLayer1/RunButton")
	var menu_rect: Rect2 = scene.get_node("CanvasLayer1/InGameMenu").menu_button.get_global_rect()
	var run_rect: Rect2 = run_button.get_global_rect()
	var attack: TouchScreenButton = scene.get_node("CanvasLayer1/TouchScreenButton")
	var attack_rect := Rect2(attack.position, attack.texture_normal.get_size() * attack.scale)
	var zoom = body.get_node("Camera2D/MapZoom")
	if not _run_icon_ok(run_button) or run_button.button_pressed \
			or run_rect.intersects(attack_rect) or run_rect.intersects(menu_rect) \
			or _gap(run_rect, attack_rect) > 3.0 or run_rect.size.x >= attack_rect.size.x \
			or not zoom.starts_on_hud(run_rect.get_center()):
		printerr("FAIL run_control button icon %s pressed %s at %s, attack %s, menu %s"
				% [run_button.icon, run_button.button_pressed, run_rect, attack_rect, menu_rect])
		fail += 1
	if not body.is_multiplayer_authority():
		printerr("FAIL run_control hero is not the local one")
		fail += 1

	var reach: float = Interaction.REACH
	var chop: float = Interaction.CHOP_REACH
	var sword: int = body.SWORD_DAMAGE
	if run_button.running() or run_button.latched:
		printerr("FAIL run_control starts running")
		fail += 1
	run_button.button_down.emit()
	if not run_button.running() or run_button.latched:
		printerr("FAIL run_control hold did not run")
		fail += 1
	for _i in RunControl.TAP_FRAMES + 4:
		await process_frame
	if not run_button.button_pressed or not _run_on(run_button):
		printerr("FAIL run_control hold did not show the on face (pressed %s)" % run_button.button_pressed)
		fail += 1
	if not run_button.running() or run_button.latched:
		printerr("FAIL run_control long press latched")
		fail += 1
	run_button.button_up.emit()
	if run_button.running() or run_button.latched:
		printerr("FAIL run_control release did not return to a walk")
		fail += 1

	run_button.button_down.emit()
	run_button.button_up.emit()
	run_button.button_down.emit()
	run_button.button_up.emit()
	if not run_button.latched or not run_button.running():
		printerr("FAIL run_control same-frame double tap undid the latch")
		fail += 1
	await process_frame
	run_button.button_down.emit()
	run_button.button_up.emit()
	if run_button.latched or run_button.running():
		printerr("FAIL run_control second tap did not turn run off")
		fail += 1

	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.physical_keycode = KEY_SHIFT
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	if not Input.is_action_pressed("run") or not run_button.running() or run_button.latched:
		printerr("FAIL run_control Shift did not hold run (latched %s)" % run_button.latched)
		fail += 1
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	if Input.is_action_pressed("run") or run_button.running():
		printerr("FAIL run_control releasing Shift left run on")
		fail += 1

	var walked: float = await _run_speed(body, 36)
	run_button.button_down.emit()
	run_button.button_up.emit()
	var ran: float = await _run_speed(body, 36)
	if ran <= walked * 1.7 or ran <= float(body.MAX_SPEED):
		printerr("FAIL run_control speed walk %s run %s" % [walked, ran])
		fail += 1
	run_button.button_down.emit()
	run_button.button_up.emit()
	await physics_frame
	var back: float = body.velocity.length()
	Input.action_release("ui_right")
	if run_button.running() or back > float(body.MAX_SPEED) + 0.05:
		printerr("FAIL run_control after toggle off speed %s (cap %s)" % [back, body.MAX_SPEED])
		fail += 1

	body.velocity = Vector2.ZERO
	var joystick = scene.get_node("CanvasLayer1/player_joystick")
	var vp: Viewport = scene.get_viewport()
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = joystick.global_position
	touch.pressed = true
	vp.push_input(touch, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = joystick.global_position + Vector2(40, 0) * joystick.global_scale
	vp.push_input(drag, true)
	for _i in 30:
		await physics_frame
	var axis_walk: Vector2 = body.get_joystick_axis()
	var joy_walk: float = body.velocity.length()
	run_button.button_down.emit()
	run_button.button_up.emit()
	var axis_run: Vector2 = body.get_joystick_axis()
	for _i in 20:
		await physics_frame
	var joy_run: float = body.velocity.length()
	touch.pressed = false
	touch.position = drag.position
	vp.push_input(touch, true)
	if not axis_walk.is_equal_approx(axis_run) or axis_walk.x < 0.9 or absf(axis_walk.y) > 0.05:
		printerr("FAIL run_control joystick axis walk %s run %s" % [axis_walk, axis_run])
		fail += 1
	var stick: float = body.JOYSTICK_MAX_SPEED
	if joy_walk < stick * 0.9 or joy_walk > stick + 0.05 or joy_run < stick * RunControl.SPEED_SCALE * 0.9:
		printerr("FAIL run_control joystick speed walk %s run %s (cap %s)" % [joy_walk, joy_run, stick])
		fail += 1
	if Interaction.REACH != reach or Interaction.CHOP_REACH != chop or body.SWORD_DAMAGE != sword \
			or body.sword_active():
		printerr("FAIL run_control changed reach %s/%s or sword %s active %s" % [
			Interaction.REACH, Interaction.CHOP_REACH, body.SWORD_DAMAGE, body.sword_active()])
		fail += 1

	Input.action_release("ui_right")
	Input.action_release("run")
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_run_control (walk %s run %s, stick %s -> %s)" % [walked, ran, joy_walk, joy_run])
	return fail


func _run_speed(body: Node, frames: int) -> float:
	body.velocity = Vector2.ZERO
	Input.action_press("ui_right")
	for _i in frames:
		await physics_frame
	return body.velocity.length()


func _test_run_two_players() -> int:
	## One side latches run and the other walks, holding the same direction.
	## The runner goes farther. Each side's copy of the other body follows
	## that body's position.
	print("-- test_run_two_players")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL run_two_players found no free UDP port")
		return 1
	var server := Node.new()
	server.name = "RunServer"
	var client := Node.new()
	client.name = "RunClient"
	root.add_child(server)
	root.add_child(client)
	var smp := SceneMultiplayer.new()
	var cmp := SceneMultiplayer.new()
	set_multiplayer(smp, server.get_path())
	set_multiplayer(cmp, client.get_path())
	var speer := ENetMultiplayerPeer.new()
	var cpeer := ENetMultiplayerPeer.new()
	if speer.create_server(port) != OK:
		printerr("FAIL run_two_players server did not listen")
		fail = 1
	else:
		smp.multiplayer_peer = speer
		cpeer.create_client("127.0.0.1", port)
		cmp.multiplayer_peer = cpeer
		if not await _client_connected(smp, cpeer):
			printerr("FAIL run_two_players client did not connect")
			fail = 1
		else:
			var cid := str(cpeer.get_unique_id())
			var s_runner := _run_body(_run_world(server), "1", Vector2.ZERO)
			var s_walker := _run_body(server.get_node("World"), cid, Vector2(0, 40))
			var c_runner := _run_body(_run_world(client), "1", Vector2.ZERO)
			var c_walker := _run_body(client.get_node("World"), cid, Vector2(0, 40))
			await process_frame
			var s_button = server.get_node("CanvasLayer1/RunButton")
			var c_button = client.get_node("CanvasLayer1/RunButton")
			s_button.button_down.emit()
			s_button.button_up.emit()
			if not s_button.running() or c_button.running():
				printerr("FAIL run_two_players latch server %s client %s" % [s_button.running(), c_button.running()])
				fail += 1
			elif not s_runner.is_multiplayer_authority() or not c_walker.is_multiplayer_authority() \
					or c_runner.is_multiplayer_authority() or s_walker.is_multiplayer_authority():
				printerr("FAIL run_two_players owners runner %s walker %s" % [
					s_runner.is_multiplayer_authority(), c_walker.is_multiplayer_authority()])
				fail += 1
			else:
				Input.action_press("ui_right")
				for _i in 40:
					await physics_frame
				Input.action_release("ui_right")
				var settled := false
				for _i in 30:
					await physics_frame
					if absf(c_runner.position.x - s_runner.position.x) < 16.0 \
							and absf(s_walker.position.x - c_walker.position.x) < 16.0:
						settled = true
						break
				var run_x: float = s_runner.position.x
				var walk_x: float = c_walker.position.x
				if walk_x < 8.0 or run_x < walk_x * 1.4:
					printerr("FAIL run_two_players distance run %s walk %s" % [run_x, walk_x])
					fail += 1
				if not settled or absf(s_runner.position.y) > 2.0 or absf(c_walker.position.y - 40.0) > 2.0:
					printerr("FAIL run_two_players copies runner owner %s copy %s walker owner %s copy %s" % [
						s_runner.position, c_runner.position, c_walker.position, s_walker.position])
					fail += 1
	Input.action_release("ui_right")
	Input.action_release("run")
	for peer in [server, client]:
		var world: Node = peer.get_node_or_null("World")
		if world:
			for child in world.get_children():
				child.free()
	cpeer.close()
	speer.close()
	set_multiplayer(null, client.get_path())
	set_multiplayer(null, server.get_path())
	server.queue_free()
	client.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_run_two_players")
	return fail


func _run_world(peer: Node) -> Node2D:
	var world := Node2D.new()
	world.name = "World"
	peer.add_child(world)
	var layer := CanvasLayer.new()
	layer.name = "CanvasLayer1"
	peer.add_child(layer)
	var button := RunControl.new()
	button.name = "RunButton"
	layer.add_child(button)
	return world


func _run_icon_ok(button: Button) -> bool:
	var tex := button.icon
	return tex != null and tex.get_width() == 32 and tex.get_height() == 32 \
			and str(tex.resource_path).ends_with("icon_run.png") \
			and button.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST \
			and button.get_theme_constant("icon_max_width") < int(RoundHudStyle.RUN_SIZE)


func _run_on(button: Button) -> bool:
	var box := button.get_theme_stylebox("pressed") as StyleBoxFlat
	if box == null or box.border_width_left < 2:
		return false
	return box.border_color.r > RoundHudStyle.INK.r + 0.4 \
			and box.bg_color.get_luminance() > RoundHudStyle.FACE.get_luminance() + 0.15


func _gap(a: Rect2, b: Rect2) -> float:
	## Separation between two rects. Zero when they overlap or touch.
	var dx := 0.0
	if a.end.x < b.position.x:
		dx = b.position.x - a.end.x
	elif b.end.x < a.position.x:
		dx = a.position.x - b.end.x
	var dy := 0.0
	if a.end.y < b.position.y:
		dy = b.position.y - a.end.y
	elif b.end.y < a.position.y:
		dy = a.position.y - b.end.y
	return maxf(dx, dy)


func _run_body(world: Node, id: String, at: Vector2) -> CharacterBody2D:
	var body := load("res://Player/character_body_2d.tscn").instantiate() as CharacterBody2D
	body.name = id
	body.position = at
	body.collision_layer = 0
	body.collision_mask = 0
	world.add_child(body)
	return body
