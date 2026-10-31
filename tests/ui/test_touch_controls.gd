extends "res://tests/helpers/test_helpers.gd"
## Touch look and joystick hold.


func _test_touch_controls_look() -> int:
	## Castle Stone touch controls (#231): the attack button shows its idle,
	## pressed and aim art as the finger lands, leaves the dead zone and comes
	## back; the move stick shows its active knob only while dragged. The cone
	## fill pulses 0.40 -> 0.55 -> 0.40 alpha every 0.8 s, and its lines are
	## one screen pixel at any camera zoom.
	print("-- test_touch_controls_look")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	scene.get_node("World").add_child(player)
	player.position = player.spawn_position()
	await process_frame
	await process_frame
	var aim: AttackAim = player.get_node("AttackAim")
	var button = aim.attack_button()
	var stick = scene.get_node("CanvasLayer1/player_joystick")
	var c: Vector2 = button.aim_center()
	var vp: Viewport = scene.get_viewport()
	var touch := func(index: int, pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.index = index
		e.position = pos
		e.pressed = pressed
		vp.push_input(e, true)
	var drag := func(index: int, pos: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = pos
		vp.push_input(e, true)

	if c.distance_to(Vector2(398, 202)) > 0.5:
		printerr("FAIL touch_controls_look attack button centre %s, want (398, 202)" % c)
		fail += 1
	var steps := [
		["idle", func(): pass, button.texture_idle],
		["down", func(): touch.call(1, c, true), button.texture_down],
		["aim", func(): drag.call(1, c + Vector2(-30, 0)), button.texture_aim],
		["back in the dead zone", func(): drag.call(1, c), button.texture_down],
		["lifted", func(): touch.call(1, c, false), button.texture_idle],
	]
	for step in steps:
		step[1].call()
		if step[2] == null or button.texture_normal != step[2]:
			printerr("FAIL touch_controls_look attack button %s shows %s" % [step[0], button.texture_normal])
			fail += 1
	var knob: TouchScreenButton = stick.touch
	touch.call(0, stick.global_position + Vector2(25, 0), true)  # on the base's rim: starts a drag
	if stick.ongoing_drag != 0 or knob.texture_normal != stick.stick_active:
		printerr("FAIL touch_controls_look stick dragged: finger %s, knob %s" % [stick.ongoing_drag, knob.texture_normal])
		fail += 1
	touch.call(0, stick.global_position, false)
	if knob.texture_normal != stick.stick:
		printerr("FAIL touch_controls_look stick released still shows %s" % knob.texture_normal)
		fail += 1

	var style := aim.style
	for t in [[0.0, 0.40], [0.2, 0.475], [0.4, 0.55], [0.8, 0.40]]:
		var fill: Color = style.fill_at(t[0])
		if not is_equal_approx(fill.a, t[1]) or fill.to_html(false) != "3d3a5c":
			printerr("FAIL touch_controls_look fill at %.1f s is %s, want 3d3a5c at %.3f" % [t[0], fill, t[1]])
			fail += 1
	var camera: Camera2D = player.get_node("Camera2D")
	for z in [0.7, 1.4]:
		camera.zoom = Vector2(z, z)
		await process_frame
		if not is_equal_approx(aim.screen_px() * z, 1.0):
			printerr("FAIL touch_controls_look at zoom %s a screen px is %s world px" % [z, aim.screen_px()])
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_touch_controls_look")
	return fail


func _test_joystick_hold_keeps_moving() -> int:
	## Touch joystick: a finger held still at one offset, with no further
	## touch or drag events, keeps the player moving at the joystick's top
	## speed every physics frame; letting go brings the player to rest.
	print("-- test_joystick_hold_keeps_moving")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var local = load("res://Player/character_body_2d.tscn").instantiate()
	local.name = str(scene.multiplayer.get_unique_id())
	scene.get_node("World").add_child(local)
	local.collision_mask = 0  # input to velocity only; terrain is not under test
	await process_frame
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
	var top: float = local.JOYSTICK_MAX_SPEED
	for i in range(60):
		await physics_frame
	var held: Vector2 = local.velocity
	if not (held.x > top * 0.9 and held.length() <= top + 0.01 and absf(held.y) < 0.01):
		printerr("FAIL joystick_hold velocity after 60 frames held still: %s (want ~%s, +x)" % [held, top])
		fail += 1
	if local.lastAnimDirection != "Right":
		printerr("FAIL joystick_hold facing %s, want Right" % local.lastAnimDirection)
		fail += 1
	touch.pressed = false
	touch.position = drag.position
	vp.push_input(touch, true)
	for i in range(60):
		await physics_frame
	var at: Vector2 = local.position
	await physics_frame
	if local.velocity != Vector2.ZERO or local.position != at:
		printerr("FAIL joystick_hold still moving after release: v %s" % local.velocity)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_joystick_hold_keeps_moving (held %s)" % held)
	return fail
