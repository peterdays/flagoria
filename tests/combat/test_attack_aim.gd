extends "res://tests/helpers/test_helpers.gd"
## Attack aim by mouse and touch (Scripts/attack_aim.gd).


func _test_attack_aim_mouse() -> int:
	## Mouse aim (#231): holding the left button on the map in combat mode
	## shows the cone toward the cursor, snapped to the four swing directions,
	## and releasing swings that way. The cone covers the sword's hitbox at
	## mid-swing in every direction. Right-click and opening the in-game menu
	## cancel; mouse events made from touches, clicks on the HUD, interact
	## mode, an open in-game menu and a dead player never aim; an unknown RPC
	## direction swings in the facing direction.
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

	# Opening the in-game menu mid-aim cancels: the release does not swing,
	# and a click while it is open does not aim.
	var game_menu = scene.get_node("CanvasLayer1/InGameMenu")
	player.lastAnimDirection = "Down"
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(-60, 5)), true)
	var aimed_before: bool = aim.aiming
	game_menu.open()
	await process_frame
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(-60, 5)), false)
	if not aimed_before or aim.aiming or player.isAttacking:
		printerr("FAIL attack_aim_mouse opening the in-game menu did not cancel the aim (aimed %s, aiming %s, attacking %s)"
				% [aimed_before, aim.aiming, player.isAttacking])
		fail += 1
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(-60, 5)), true)
	if aim.aiming:
		printerr("FAIL attack_aim_mouse aimed with the in-game menu open")
		fail += 1
	mouse.call(MOUSE_BUTTON_LEFT, at.call(Vector2(-60, 5)), false)
	game_menu.close()
	await wait_swing.call()

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

	# Off-axis aims swing at the exact angle, the cone with them; the sprite
	# keeps the nearest four-way facing.
	var minimap = scene.get_node("CanvasLayer1/MinimapPanel")
	minimap.shown = false  # the open minimap is HUD right of the hero
	minimap.visible = false
	var four := await _four_way_blades(player)
	for deg in OFF_AXIS_DEGREES:
		var angle := deg_to_rad(deg)
		var spot: Vector2 = at.call(AttackAim.ORIGIN + Vector2.from_angle(angle) * 20.0)
		mouse.call(MOUSE_BUTTON_LEFT, spot, true)
		fail += _check_cone_angle("attack_aim_mouse %s deg" % deg, aim, angle)
		mouse.call(MOUSE_BUTTON_LEFT, spot, false)
		fail += _check_turned_swing("attack_aim_mouse %s deg" % deg, player, angle, four)
		await wait_swing.call()

	# The RPC's angle is checked on every peer: one that is not finite or not
	# within 45 degrees of the direction swings the facing direction, untilted.
	for bad in [["Right", INF], ["Right", PI], ["Right", deg_to_rad(50.0)], ["Up", -INF], ["Sideways", 0.2]]:
		player.lastAnimDirection = "Left"
		player.attack_animation(bad[0], bad[1])
		if player.lastAnimDirection != "Left" or player.animations.current_animation != "attackLeft" \
				or player.swing_turn != 0.0:
			printerr("FAIL attack_aim_mouse bad angle %s swung %s, turn %s"
					% [bad, player.animations.current_animation, player.swing_turn])
			fail += 1
		await wait_swing.call()
	# No angle (Space, older callers) keeps the four-way swing.
	player.attack_animation("Up")
	if player.animations.current_animation != "attackUp" or player.swing_turn != 0.0:
		printerr("FAIL attack_aim_mouse a four-way swing turned %s" % player.swing_turn)
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
	## be held meanwhile. A second touch off the move stick, or opening the
	## in-game menu, cancels the aim. The cone's look and length come from its
	## style.
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
	# Off-axis drags swing at the exact angle from the button's centre.
	var four := await _four_way_blades(player)
	for deg in OFF_AXIS_DEGREES:
		var angle := deg_to_rad(deg)
		touch.call(1, c, true)
		drag.call(1, c + Vector2.from_angle(angle) * 30.0)
		fail += _check_cone_angle("attack_aim_touch %s deg" % deg, aim, angle)
		touch.call(1, c + Vector2.from_angle(angle) * 30.0, false)
		fail += _check_turned_swing("attack_aim_touch %s deg" % deg, player, angle, four)
		await wait_swing.call()
	# A second touch off the move stick cancels an aim: the aiming finger is
	# let go, so its drags and its lift do not swing. A touch on the stick
	# does not cancel.
	touch.call(1, c, true)
	drag.call(1, c + Vector2(-30, 0))
	touch.call(0, joystick.global_position, true)
	var kept: bool = aim.aiming
	touch.call(0, joystick.global_position, false)
	touch.call(2, c + Vector2(-150, -80), true)
	if not kept or aim.aiming:
		printerr("FAIL attack_aim_touch second touch: aim kept on the stick %s, after a map touch %s"
				% [kept, aim.aiming])
		fail += 1
	touch.call(2, c + Vector2(-150, -80), false)
	drag.call(1, c + Vector2(0, -30))
	touch.call(1, c + Vector2(0, -30), false)
	if aim.aiming or player.isAttacking:
		printerr("FAIL attack_aim_touch a finger cancelled by a second touch aimed or swung %s"
				% player.animations.current_animation)
		fail += 1
	await wait_swing.call()
	# Opening the in-game menu cancels a touch aim: lifting does not swing.
	var game_menu = scene.get_node("CanvasLayer1/InGameMenu")
	touch.call(1, c, true)
	drag.call(1, c + Vector2(-30, 0))
	var aimed_before: bool = aim.aiming
	game_menu.open()
	await process_frame
	drag.call(1, c + Vector2(-32, 0))
	touch.call(1, c + Vector2(-32, 0), false)
	if not aimed_before or aim.aiming or player.isAttacking:
		printerr("FAIL attack_aim_touch opening the in-game menu did not cancel the aim (aimed %s, aiming %s, attacking %s)"
				% [aimed_before, aim.aiming, player.isAttacking])
		fail += 1
	game_menu.close()
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


const OFF_AXIS_DEGREES := [30.0, -60.0, 160.0, 115.0]  ## one per four-way direction


func _blade(player) -> Vector2:
	## The sword's hitbox mid-swing, from the cone's apex, in the player's space.
	player.animations.seek(0.1, true)
	return player.to_local(player.sword_shape.global_position) - AttackAim.ORIGIN


func _four_way_blades(player) -> Dictionary:
	## Each direction's four-way swing: its blade mid-swing.
	var blades := {}
	for direction in AttackAim.DIRECTIONS:
		player.attack_animation(direction)
		blades[direction] = _blade(player)
		while player.isAttacking:
			await process_frame
	return blades


func _check_cone_angle(what: String, aim: AttackAim, angle: float) -> int:
	## While aiming, the cone's middle points along `angle`.
	var cone := aim.cone_points()
	var mid: Vector2 = cone[1 + AttackAim.ARC_POINTS / 2] - AttackAim.ORIGIN
	if not aim.aiming or absf(angle_difference(mid.angle(), angle)) > 0.01 \
			or absf(angle_difference(aim.aim_angle(), angle)) > 0.01:
		printerr("FAIL %s cone at %s, aim %s (aiming %s)"
				% [what, rad_to_deg(mid.angle()), rad_to_deg(aim.aim_angle()), aim.aiming])
		return 1
	return 0


func _check_turned_swing(what: String, player, angle: float, four: Dictionary) -> int:
	## After the release: the sprite faces the nearest direction, and the
	## blade is that direction's four-way blade turned to `angle`.
	var direction := AttackAim.direction_name(Vector2.from_angle(angle))
	var turn := angle_difference(AttackAim.direction_vector(direction).angle(), angle)
	var blade := _blade(player)
	var want: Vector2 = four[direction].rotated(turn)
	var fail := 0
	if player.lastAnimDirection != direction or player.animations.current_animation != "attack" + direction:
		printerr("FAIL %s swung %s facing %s, want %s"
				% [what, player.animations.current_animation, player.lastAnimDirection, direction])
		fail += 1
	if blade.distance_to(want) > 0.05:
		printerr("FAIL %s blade at %s, want %s (four-way %s)" % [what, blade, want, four[direction]])
		fail += 1
	return fail


func _test_attack_angle_two_players() -> int:
	## Two peers over ENet loopback (#231 slice 3): an aimed swing at an exact
	## angle turns the same way on the server's copy, which decides hits, as
	## on the attacker's; an angle off its direction falls back to the facing
	## on the server too.
	print("-- test_attack_angle_two_players")
	var fail := 0
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL attack_angle_two_players found no free UDP port")
		return 1
	var server_root := Node.new()
	server_root.name = "AngleServer"
	root.add_child(server_root)
	var s_world := Node.new()
	s_world.name = "World"
	server_root.add_child(s_world)
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var smp := SceneMultiplayer.new()
	var cmp := SceneMultiplayer.new()
	set_multiplayer(smp, server_root.get_path())
	set_multiplayer(cmp, scene.get_path())
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	cmp.multiplayer_peer = cpeer
	if not await _client_connected(smp, cpeer):
		printerr("FAIL attack_angle_two_players client did not connect")
		fail += 1
	else:
		var copy := func(world: Node) -> CharacterBody2D:
			var p = load("res://Player/character_body_2d.tscn").instantiate()
			p.name = str(cpeer.get_unique_id())
			p.get_node("MultiplayerSynchronizer").free()
			world.add_child(p)
			p.set_physics_process(false)  # no walk facing RPCs mid-check
			return p
		var server = copy.call(s_world)
		var client = copy.call(scene.get_node("World"))
		await process_frame
		var wait_attack := func(p, on: bool) -> bool:
			var until := Time.get_ticks_msec() + 5000
			while p.isAttacking != on and Time.get_ticks_msec() < until:
				await process_frame
			return p.isAttacking == on
		var four := await _four_way_blades(client)  # local only: not sent to the server
		var angle := deg_to_rad(30.0)
		var want: Vector2 = four["Right"].rotated(angle)
		client.attack_toward("Right", angle)
		if not await wait_attack.call(server, true):
			printerr("FAIL attack_angle_two_players the server copy did not swing")
			fail += 1
		else:
			var on_server := _blade(server)
			var on_client := _blade(client)
			if server.lastAnimDirection != "Right" or absf(server.swing_turn - angle) > 0.001 \
					or on_server.distance_to(want) > 0.05 or on_client.distance_to(want) > 0.05:
				printerr("FAIL attack_angle_two_players server swung %s turned %s, blade %s; client blade %s; want %s"
						% [server.lastAnimDirection, server.swing_turn, on_server, on_client, want])
				fail += 1
		await wait_attack.call(server, false)
		await wait_attack.call(client, false)
		server.lastAnimDirection = "Down"
		client.attack_animation.rpc("Right", PI)
		if not await wait_attack.call(server, true):
			printerr("FAIL attack_angle_two_players the server copy did not get the bad angle")
			fail += 1
		elif server.animations.current_animation != "attackDown" or server.swing_turn != 0.0:
			printerr("FAIL attack_angle_two_players bad angle swung %s turned %s on the server"
					% [server.animations.current_animation, server.swing_turn])
			fail += 1
	cpeer.close()
	speer.close()
	set_multiplayer(null, scene.get_path())
	set_multiplayer(null, server_root.get_path())
	scene.queue_free()
	server_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_attack_angle_two_players")
	return fail
