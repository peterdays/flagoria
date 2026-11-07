extends "res://tests/helpers/test_helpers.gd"
## Touch collapse, reopen and the parchment full map (part of #247).


func _test_parchment_map() -> int:
	## Header buttons collapse and reopen the wood panel. Maximize opens the
	## parchment: a drag pans it, the hero does not move or attack, the wheel
	## does not zoom, a hit or Esc or the close control returns to the panel.
	print("-- test_parchment_map")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	await process_frame
	var panel: MinimapPanel = scene.get_node("CanvasLayer1/MinimapPanel")
	panel.set_physics_process(false)
	scene.add_player(scene.multiplayer.get_unique_id())
	await process_frame
	panel.tick()
	panel.tick()
	var collapse: Control = panel.get_node("CollapseButton")
	var maximize: Control = panel.get_node("MaximizeButton")
	var reopen: Control = scene.get_node("CanvasLayer1/MapReopen")
	var parchment: ParchmentMap = scene.get_node("CanvasLayer1/ParchmentMap")
	var player: Node2D = scene.get_node("World/%d" % scene.multiplayer.get_unique_id())
	if not panel.visible or reopen.visible or parchment.is_open():
		printerr("FAIL parchment_map start visible panel %s reopen %s map %s"
				% [panel.visible, reopen.visible, parchment.is_open()])
		fail += 1
	var header := Rect2(Vector2.ZERO, Vector2(panel.size.x, 16))
	if collapse.size.x < 16 or collapse.size.y < 12 or maximize.size.x < 16 \
			or not header.encloses(Rect2(collapse.position, collapse.size)) \
			or not header.encloses(Rect2(maximize.position, maximize.size)) \
			or reopen.size.x < 44 or reopen.size.y < 20:
		printerr("FAIL parchment_map controls collapse %s at %s, maximize %s at %s, reopen %s"
				% [collapse.size, collapse.position, maximize.size, maximize.position, reopen.size])
		fail += 1
	_tap(collapse)
	if panel.visible or not reopen.visible:
		printerr("FAIL parchment_map collapse left panel %s reopen %s" % [panel.visible, reopen.visible])
		fail += 1
	_tap(reopen)
	if not panel.visible or reopen.visible:
		printerr("FAIL parchment_map reopen left panel %s reopen %s" % [panel.visible, reopen.visible])
		fail += 1
	_tap(maximize)
	if not parchment.is_open() or panel.visible or reopen.visible:
		printerr("FAIL parchment_map maximize open %s panel %s reopen %s"
				% [parchment.is_open(), panel.visible, reopen.visible])
		fail += 1
	var before := parchment.pan
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = parchment.size * 0.5
	parchment._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = press.position + Vector2(40, -16)
	motion.relative = Vector2(40, -16)
	parchment._gui_input(motion)
	if parchment.pan.distance_to(before) < 10.0:
		printerr("FAIL parchment_map drag did not pan (%s)" % parchment.pan)
		fail += 1
	var stuck := player.position
	Input.action_press("ui_right")
	for _i in 12:
		await physics_frame
	Input.action_release("ui_right")
	if player.position.distance_to(stuck) >= 1.0:
		printerr("FAIL parchment_map hero moved while the map was open")
		fail += 1
	Input.action_press("attack")
	await physics_frame
	Input.action_release("attack")
	await physics_frame
	if player.isAttacking:
		printerr("FAIL parchment_map hero attacked while the map was open")
		fail += 1
	var zoom = player.get_node("Camera2D/MapZoom")
	var factor: float = zoom.factor
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(200, 100)
	scene.get_viewport().push_input(wheel, true)
	await process_frame
	if not is_equal_approx(zoom.factor, factor):
		printerr("FAIL parchment_map wheel zoomed the camera (%s -> %s)" % [factor, zoom.factor])
		fail += 1
	var health: PlayerHealth = player.get_node("Health")
	if not health.take_damage(1):
		printerr("FAIL parchment_map damage did not land")
		fail += 1
	for _i in 5:
		await process_frame
	if parchment.is_open() or not panel.visible:
		printerr("FAIL parchment_map still open after damage (open %s panel %s)"
				% [parchment.is_open(), panel.visible])
		fail += 1
	_tap(maximize)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	parchment._input(esc)
	if parchment.is_open() or not panel.visible:
		printerr("FAIL parchment_map Esc left it open %s panel %s" % [parchment.is_open(), panel.visible])
		fail += 1
	_tap(maximize)
	_tap(parchment.get_node("CloseButton"))
	if parchment.is_open() or not panel.visible or not is_equal_approx(zoom.factor, factor):
		printerr("FAIL parchment_map close open %s panel %s zoom %s"
				% [parchment.is_open(), panel.visible, zoom.factor])
		fail += 1
	_tap(parchment.get_node("RecentreButton"))
	# Recentre is on the sheet; the sheet is closed, so the tap must not open it.
	if parchment.is_open():
		printerr("FAIL parchment_map recentre opened a closed map")
		fail += 1
	_tap(maximize)
	parchment.pan = Vector2(30, 30)
	_tap(parchment.get_node("RecentreButton"))
	if parchment.pan != Vector2.ZERO:
		printerr("FAIL parchment_map recentre left pan %s" % parchment.pan)
		fail += 1
	parchment.hide_map()
	panel.apply_chrome()
	wheel.pressed = true
	scene.get_viewport().push_input(wheel, true)
	await process_frame
	if not zoom.factor > factor:
		printerr("FAIL parchment_map wheel did nothing after close (%s)" % zoom.factor)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_parchment_map")
	return fail


func _tap(control: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = control.size * 0.5
	control._gui_input(ev)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = ev.position
	control._gui_input(up)
