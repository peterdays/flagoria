extends "res://tests/helpers/test_helpers.gd"
## Attack aim by mouse and touch (Scripts/attack_aim.gd).


func _test_attack_aim_mouse() -> int:
	## Mouse aim (#231): holding the left button on the map in combat mode
	## shows the cone toward the cursor, snapped to the four swing directions,
	## and releasing swings that way. The cone covers the sword's hitbox at
	## mid-swing in every direction. Right-click cancels; mouse events made
	## from touches, clicks on the HUD, interact mode and a dead player never
	## aim; an unknown RPC direction swings in the facing direction.
	print("-- test_attack_aim_mouse")
	var fail := 0
	if AttackAim.direction_name(Vector2(-3, 1)) != "Left" or AttackAim.direction_name(Vector2(1, -3)) != "Up" \
			or AttackAim.direction_name(Vector2(2, 2)) != "Right" or AttackAim.direction_name(Vector2(0, 5)) != "Down" \
			or AttackAim.direction_name(Vector2.ZERO) != "":
		printerr("FAIL attack_aim_mouse direction_name snaps wrong")
		fail += 1
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
	var aim: AttackAim = player.get_node_or_null("AttackAim")
	if aim == null:
		printerr("FAIL attack_aim_mouse the local player has no AttackAim")
		scene.queue_free()
		await process_frame
		return fail + 1
	var vp: Viewport = scene.get_viewport()
	var at := func(offset: Vector2) -> Vector2:  # world offset from the player to viewport px
		return aim.get_canvas_transform() * (player.global_position + offset)
	var mouse := func(button: MouseButton, pos: Vector2, pressed: bool, device := 0) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.position = pos
		e.pressed = pressed
		e.device = device
		vp.push_input(e, true)
	var move := func(pos: Vector2) -> void:
		var e := InputEventMouseMotion.new()
		e.position = pos
		vp.push_input(e, true)
	var wait_swing := func() -> void:
		var until := Time.get_ticks_msec() + 3000
		while player.isAttacking and Time.get_ticks_msec() < until:
			await process_frame

	# Hold, move the cursor round, release: the cone follows and the swing
	# goes the last way it showed.
	player.lastAnimDirection = "Down"
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(-60, 5)), true)
	if not aim.aiming or aim.aim_direction() != "Left" or player.isAttacking:
		printerr("FAIL attack_aim_mouse press: aiming %s toward %s, attacking %s"
				% [aim.aiming, aim.aim_direction(), player.isAttacking])
		fail += 1
	move.call(at.call(Vector2(10, -70)))
	if aim.aim_direction() != "Up":
		printerr("FAIL attack_aim_mouse cone did not follow the cursor up (%s)" % aim.aim_direction())
		fail += 1
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(10, -70)), false)
	if aim.aiming or not player.isAttacking or player.lastAnimDirection != "Up" \
			or player.animations.current_animation != "attackUp":
		printerr("FAIL attack_aim_mouse release: aiming %s, attacking %s, facing %s, anim %s"
				% [aim.aiming, player.isAttacking, player.lastAnimDirection, player.animations.current_animation])
		fail += 1
	await wait_swing.call()

	# The cone covers the sword's hitbox at mid-swing, every direction.
	for direction in AttackAim.DIRECTIONS:
		aim._pointer = at.call(AttackAim.direction_vector(direction) * 50.0)
		var cone := aim.cone_points()
		player.attack_animation(direction)
		player.animations.seek(0.1, true)
		var blade: Vector2 = aim.to_local(player.sword_shape.global_position)
		if not Geometry2D.is_point_in_polygon(blade, cone):
			printerr("FAIL attack_aim_mouse %s cone misses the blade at %s" % [direction, blade])
			fail += 1
		await wait_swing.call()

	# Right-click cancels: no swing.
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), true)
	mouse.call(MOUSE_BUTTON_RIGHT, at.call(Vector2(60, 0)), true)
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), false)
	if aim.aiming or player.isAttacking:
		printerr("FAIL attack_aim_mouse right-click did not cancel (aiming %s, attacking %s)" % [aim.aiming, player.isAttacking])
		fail += 1
	# A touch's emulated mouse press never aims.
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), true, InputEvent.DEVICE_ID_EMULATION)
	if aim.aiming:
		printerr("FAIL attack_aim_mouse a mouse event made from a touch aimed")
		fail += 1
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), false, InputEvent.DEVICE_ID_EMULATION)
	# A click on the attack button (HUD) does not aim.
	var button: TouchScreenButton = scene.get_node("CanvasLayer1/TouchScreenButton")
	var on_button := button.get_global_transform_with_canvas() * (button.shape.get_rect().get_center())
	mouse.call(MOUSE_BUTTON_LEFT, on_button, true)
	if aim.aiming:
		printerr("FAIL attack_aim_mouse a click on the attack button aimed")
		fail += 1
	mouse.call(MOUSE_BUTTON_LEFT, on_button, false)
	await wait_swing.call()
	# Interact mode: clicks cut trees, not aim; switching modes mid-aim cancels.
	var interaction: Interaction = scene.get_node("World/Interaction")
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), true)
	interaction.set_mode(Interaction.Mode.INTERACT)
	await process_frame
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), false)
	if aim.aiming or player.isAttacking:
		printerr("FAIL attack_aim_mouse switching to interact mode did not cancel the aim")
		fail += 1
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), true)
	if aim.aiming:
		printerr("FAIL attack_aim_mouse aimed in interact mode")
		fail += 1
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), false)
	interaction.set_mode(Interaction.Mode.COMBAT)
	# An unknown direction from the RPC swings in the facing direction.
	player.lastAnimDirection = "Left"
	player.attack_animation("Sideways")
	if player.lastAnimDirection != "Left" or player.animations.current_animation != "attackLeft":
		printerr("FAIL attack_aim_mouse unknown direction swung %s" % player.animations.current_animation)
		fail += 1
	await wait_swing.call()
	# A dead player does not aim.
	player.health.take_damage(player.health.health)
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), true)
	if aim.aiming:
		printerr("FAIL attack_aim_mouse a dead player aimed")
		fail += 1
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(60, 0)), false)
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_attack_aim_mouse")
	return fail


func _test_attack_aim_touch() -> int:
	## Touch aim (#231): a finger on the attack button that drags past the
	## dead zone shows the cone the way it is from the button's centre, snapped
	## to the four swings, and lifting swings that way. A tap, or a drag that
	## stays in the dead zone, swings the way the hero faces. Dragging back
	## into the dead zone cancels (lifting there does not swing); dragging out
	## again aims again. The finger is tracked by index, so the move stick can
	## be held meanwhile. The cone's look and length come from its style.
	print("-- test_attack_aim_touch")
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
	var joystick = scene.get_node("CanvasLayer1/player_joystick")
	if button != scene.get_node("CanvasLayer1/TouchScreenButton"):
		printerr("FAIL attack_aim_touch the attack button is not found by its group")
		scene.queue_free()
		await process_frame
		return fail + 1
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
	var wait_swing := func() -> void:
		var until := Time.get_ticks_msec() + 3000
		while player.isAttacking and Time.get_ticks_msec() < until:
			await process_frame
	var dz := AttackAim.TOUCH_DEAD_ZONE

	# A tap swings the way the hero faces, on lift, with no cone.
	player.lastAnimDirection = "Left"
	touch.call(1, c, true)
	if aim.aiming or player.isAttacking:
		printerr("FAIL attack_aim_touch a finger landing on the button aimed or swung")
		fail += 1
	touch.call(1, c + Vector2(1, 1), false)
	if aim.aiming or player.animations.current_animation != "attackLeft":
		printerr("FAIL attack_aim_touch tap swung %s, want attackLeft" % player.animations.current_animation)
		fail += 1
	await wait_swing.call()
	# A wobble inside the dead zone is still a tap.
	player.lastAnimDirection = "Left"
	touch.call(1, c, true)
	drag.call(1, c + Vector2(dz * 0.6, -dz * 0.6))
	if aim.aiming:
		printerr("FAIL attack_aim_touch a drag inside the dead zone aimed")
		fail += 1
	touch.call(1, c + Vector2(dz * 0.6, -dz * 0.6), false)
	if player.animations.current_animation != "attackLeft":
		printerr("FAIL attack_aim_touch a dead-zone drag swung %s, want attackLeft" % player.animations.current_animation)
		fail += 1
	await wait_swing.call()

	# Move stick held with finger 0 while finger 1 aims on the button.
	touch.call(0, joystick.global_position, true)
	drag.call(0, joystick.global_position + Vector2(0, 20))
	touch.call(1, c, true)
	drag.call(1, c + Vector2(-4, -30))
	if not aim.aiming or aim.aim_direction() != "Up" or player.isAttacking:
		printerr("FAIL attack_aim_touch drag up: aiming %s toward %s" % [aim.aiming, aim.aim_direction()])
		fail += 1
	if aim.cone_points().size() < 3:
		printerr("FAIL attack_aim_touch no cone while aiming")
		fail += 1
	drag.call(1, c + Vector2(30, 6))
	drag.call(0, joystick.global_position + Vector2(-20, 0))  # the stick finger moves; the aim stays
	if aim.aim_direction() != "Right" or joystick.ongoing_drag != 0:
		printerr("FAIL attack_aim_touch with the stick held: toward %s, stick finger %s"
				% [aim.aim_direction(), joystick.ongoing_drag])
		fail += 1
	touch.call(0, joystick.global_position, false)  # lifting the stick finger does not fire
	if not aim.aiming or player.isAttacking:
		printerr("FAIL attack_aim_touch lifting the stick finger ended the aim")
		fail += 1
	touch.call(1, c + Vector2(30, 6), false)
	if aim.aiming or player.lastAnimDirection != "Right" or player.animations.current_animation != "attackRight":
		printerr("FAIL attack_aim_touch release swung %s facing %s, want attackRight"
				% [player.animations.current_animation, player.lastAnimDirection])
		fail += 1
	await wait_swing.call()

	# Back into the dead zone cancels: the cone goes and lifting does not swing.
	touch.call(1, c, true)
	drag.call(1, c + Vector2(-30, 0))
	drag.call(1, c + Vector2(2, 1))
	if aim.aiming or aim.aim_direction() != "":
		printerr("FAIL attack_aim_touch back in the dead zone still aims %s" % aim.aim_direction())
		fail += 1
	touch.call(1, c + Vector2(2, 1), false)
	if player.isAttacking:
		printerr("FAIL attack_aim_touch a cancelled drag swung %s" % player.animations.current_animation)
		fail += 1
	# ...and dragging out again aims again.
	touch.call(1, c, true)
	drag.call(1, c + Vector2(-30, 0))
	drag.call(1, c)
	drag.call(1, c + Vector2(3, 30))
	touch.call(1, c + Vector2(3, 30), false)
	if player.animations.current_animation != "attackDown":
		printerr("FAIL attack_aim_touch re-aim after cancel swung %s, want attackDown" % player.animations.current_animation)
		fail += 1
	await wait_swing.call()
	# A finger elsewhere on the map never aims through the button.
	touch.call(2, c + Vector2(-150, -80), true)
	drag.call(2, c + Vector2(-150, -40))
	touch.call(2, c + Vector2(-150, -40), false)
	if aim.aiming or player.isAttacking:
		printerr("FAIL attack_aim_touch a map touch aimed or swung")
		fail += 1

	# The cone's length and look come from its style, swappable in one place.
	var far := 0.0
	for p in aim.cone_points():
		far = maxf(far, (p - AttackAim.ORIGIN).length())
	if not is_equal_approx(far, aim.style.range):
		printerr("FAIL attack_aim_touch cone length %s, style says %s" % [far, aim.style.range])
		fail += 1
	var longer := AimConeStyle.new()
	longer.range = 40.0
	aim.style = longer
	far = 0.0
	for p in aim.cone_points():
		far = maxf(far, (p - AttackAim.ORIGIN).length())
	if not is_equal_approx(far, 40.0):
		printerr("FAIL attack_aim_touch a swapped style did not change the cone (%s)" % far)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_attack_aim_touch")
	return fail


func _test_attack_aim_touch_guards() -> int:
	## Touch aim (#231), found in play testing: a tap on the attack button, or
	## a wobble inside its dead zone, swings only when an aim could (combat
	## mode, alive), like a drag. Losing focus or pausing the app forgets the
	## finger on the button and drops its aim, so a lift that never arrives
	## cannot leave the button stuck: the next finger is tracked again.
	print("-- test_attack_aim_touch_guards")
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
	var c: Vector2 = aim.attack_button().aim_center()
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
	var wobble := Vector2(AttackAim.TOUCH_DEAD_ZONE * 0.5, 0)

	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_mode(Interaction.Mode.INTERACT)
	touch.call(1, c, true)
	touch.call(1, c, false)
	touch.call(1, c, true)
	drag.call(1, c + wobble)
	touch.call(1, c + wobble, false)
	if player.isAttacking:
		printerr("FAIL attack_aim_touch_guards a tap swung in interact mode")
		fail += 1
	interaction.set_mode(Interaction.Mode.COMBAT)

	for what in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		touch.call(1, c, true)
		drag.call(1, c + Vector2(30, 0))
		aim.notification(what)
		if aim.aiming or aim.touch_state() != AttackAim.TOUCH_IDLE:
			printerr("FAIL attack_aim_touch_guards notification %d kept the finger (state %d, aiming %s)"
					% [what, aim.touch_state(), aim.aiming])
			fail += 1
		touch.call(1, c + Vector2(30, 0), false)  # a late lift does nothing
		touch.call(3, c, true)  # a new finger on the button is tracked again
		drag.call(3, c + Vector2(0, -30))
		if aim.aim_direction() != "Up" or not aim.aiming or player.isAttacking:
			printerr("FAIL attack_aim_touch_guards after notification %d: aiming %s toward %s, attacking %s"
					% [what, aim.aiming, aim.aim_direction(), player.isAttacking])
			fail += 1
		aim.cancel()
		touch.call(3, c, false)

	player.health.take_damage(player.health.health)
	touch.call(1, c, true)
	touch.call(1, c, false)
	if player.isAttacking:
		printerr("FAIL attack_aim_touch_guards a dead player's tap swung")
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_attack_aim_touch_guards")
	return fail
