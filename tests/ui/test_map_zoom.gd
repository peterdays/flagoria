extends "res://tests/helpers/test_helpers.gd"
## Pinch and wheel zoom on the player camera (Scripts/map_zoom.gd).


func _test_map_zoom() -> int:
	## Pinch zoom on the local player's camera: two map touches zoom in and out
	## within the clamp, touches that start on the joystick or attack button
	## never pinch (and a pinch never moves the player), a double-tap on the map
	## resets to the default, desktop wheel/Ctrl keys work, and a remote
	## player's camera gets no zoom handler.
	print("-- test_map_zoom")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	# In play: menu hidden, HUD shown, and the menu's input handling paused.
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world: Node = scene.get_node("World")
	var local = load("res://Player/character_body_2d.tscn").instantiate()
	local.name = str(scene.multiplayer.get_unique_id())  # this peer's player
	world.add_child(local)
	var remote = load("res://Player/character_body_2d.tscn").instantiate()
	remote.name = str(scene.multiplayer.get_unique_id() + 1)
	world.add_child(remote)
	await process_frame
	var camera: Camera2D = local.get_node("Camera2D")
	var zoom = camera.get_node_or_null("MapZoom")
	if zoom == null:
		printerr("FAIL map_zoom local camera has no MapZoom")
		scene.queue_free()
		return 1
	if remote.get_node("Camera2D").get_node_or_null("MapZoom") != null:
		printerr("FAIL map_zoom remote player's camera got a MapZoom")
		fail += 1
	var default_zoom: Vector2 = camera.zoom
	var joystick = scene.get_node("CanvasLayer1/player_joystick")
	var attack: TouchScreenButton = scene.get_node("CanvasLayer1/TouchScreenButton")
	var attack_center: Vector2 = attack.get_global_transform() * (attack.texture_normal.get_size() / 2.0)
	var vp: Viewport = scene.get_viewport()
	var touch := func(index: int, pos: Vector2, pressed: bool, double := false) -> void:
		var e := InputEventScreenTouch.new()
		e.index = index
		e.position = pos
		e.pressed = pressed
		e.double_tap = double
		vp.push_input(e, true)
	var drag := func(index: int, pos: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = pos
		vp.push_input(e, true)
	var factor := func() -> float:
		return camera.zoom.x / default_zoom.x

	# Fingers apart on the open map: zoom in, clamped at MAX_FACTOR.
	touch.call(0, Vector2(200, 120), true)
	touch.call(1, Vector2(260, 120), true)
	drag.call(1, Vector2(290, 120))
	if not factor.call() > 1.0:
		printerr("FAIL map_zoom pinch out did not zoom in (%s)" % factor.call())
		fail += 1
	drag.call(1, Vector2(470, 120))
	drag.call(0, Vector2(10, 120))
	if not is_equal_approx(factor.call(), zoom.MAX_FACTOR):
		printerr("FAIL map_zoom zoom in not clamped (%s)" % factor.call())
		fail += 1
	# Fingers together: zoom out, clamped at MIN_FACTOR.
	drag.call(0, Vector2(230, 120))
	drag.call(1, Vector2(240, 120))
	drag.call(1, Vector2(231, 120))
	if not is_equal_approx(factor.call(), zoom.MIN_FACTOR):
		printerr("FAIL map_zoom zoom out not clamped (%s)" % factor.call())
		fail += 1
	touch.call(0, Vector2(230, 120), false)
	touch.call(1, Vector2(231, 120), false)

	# Double-tap on the open map: back to the default.
	touch.call(0, Vector2(240, 100), true, true)
	touch.call(0, Vector2(240, 100), false)
	if camera.zoom != default_zoom or not zoom.is_default():
		printerr("FAIL map_zoom double-tap did not reset (%s)" % camera.zoom)
		fail += 1

	# One finger on the joystick and one on the attack button never pinch.
	for start in [joystick.global_position, attack_center]:
		touch.call(0, start, true)
		touch.call(1, Vector2(240, 120), true)
		drag.call(1, Vector2(300, 60))
		drag.call(0, start + Vector2(-10, 10))
		if camera.zoom != default_zoom:
			printerr("FAIL map_zoom HUD touch at %s joined a pinch (%s)" % [start, camera.zoom])
			fail += 1
		touch.call(0, start, false)
		touch.call(1, Vector2(300, 60), false)
		zoom.reset()
	if not zoom.starts_on_hud(joystick.global_position) or not zoom.starts_on_hud(attack_center) \
			or zoom.starts_on_hud(Vector2(240, 120)):
		printerr("FAIL map_zoom HUD hit test (joystick, attack, map)")
		fail += 1

	# A pinch whose finger slides over the joystick does not move the player.
	joystick.ongoing_drag = -1
	local.velocity = Vector2.ZERO
	touch.call(2, Vector2(160, 160), true)
	touch.call(3, Vector2(240, 120), true)
	drag.call(2, joystick.global_position + Vector2(10, 0))
	if joystick.ongoing_drag != -1 or local.velocity != Vector2.ZERO:
		printerr("FAIL map_zoom pinch finger grabbed the joystick (drag %s, v %s)" % [joystick.ongoing_drag, local.velocity])
		fail += 1
	touch.call(2, joystick.global_position, false)
	touch.call(3, Vector2(240, 120), false)
	zoom.reset()

	# Desktop: wheel and Ctrl +/- zoom, Ctrl 0 resets.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	vp.push_input(wheel, true)
	var zoomed_in: float = factor.call()
	var key := InputEventKey.new()
	key.pressed = true
	key.ctrl_pressed = true
	key.keycode = KEY_MINUS
	vp.push_input(key, true)
	vp.push_input(key, true)
	var zoomed_out: float = factor.call()
	key.keycode = KEY_0
	vp.push_input(key, true)
	if not (zoomed_in > 1.0 and zoomed_out < 1.0 and camera.zoom == default_zoom):
		printerr("FAIL map_zoom desktop wheel/keys (in %s, out %s, reset %s)" % [zoomed_in, zoomed_out, camera.zoom])
		fail += 1

	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_map_zoom")
	return fail
