extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 42
## Wood panel collapse, reopen and the parchment full map.
## bin/launch.sh drives/explored_map.gd --display --seed 42

const COLLAPSE := "CanvasLayer1/MinimapPanel/CollapseButton"
const MAXIMIZE := "CanvasLayer1/MinimapPanel/MaximizeButton"
const MAP_BUTTON := "CanvasLayer1/MinimapButton"
const PARCHMENT := "CanvasLayer1/ParchmentMap"
const CLOSE := "CanvasLayer1/ParchmentMap/CloseButton"
const WALK := ["ui_right", "ui_left", "ui_up", "ui_down"]


func run() -> void:
	if not await start_game():
		return
	var panel: MinimapPanel = current_scene.get_node(MINIMAP)
	var parchment: ParchmentMap = current_scene.get_node(PARCHMENT)
	var ok := await wait_until(func() -> bool:
		var button := current_scene.get_node_or_null(MAP_BUTTON) as Control
		return button != null and button.visible and not panel.visible
	, 5.0)
	step("open")
	await click(MAP_BUTTON)
	ok = ok and await wait_until(func() -> bool: return panel.visible, 2.0)
	await snapshot("open-landscape")
	print("explored_map: panel %s" % panel.visible)

	step("collapse")
	await click(COLLAPSE)
	ok = ok and await wait_until(func() -> bool:
		return not panel.visible and current_scene.get_node_or_null("CanvasLayer1/MapReopen") == null
	, 2.0)
	await snapshot("collapsed-landscape")
	print("explored_map: collapsed panel %s" % panel.visible)

	step("reopen")
	await click(MAP_BUTTON)
	ok = ok and await wait_until(func() -> bool: return panel.visible, 2.0)
	await snapshot("reopened-landscape")

	step("parchment")
	await click(MAXIMIZE)
	ok = ok and await wait_until(func() -> bool: return parchment.is_open() and not panel.visible, 2.0)
	await snapshot("parchment-landscape")
	print("explored_map: parchment %s pan %s" % [parchment.is_open(), parchment.pan])

	step("pan")
	var pan_before := parchment.pan
	await _drag(PARCHMENT, Vector2(80, -40))
	print("explored_map: pan %s -> %s" % [pan_before, parchment.pan])
	ok = ok and parchment.pan.distance_to(pan_before) >= 10.0
	await snapshot("panned-landscape")

	step("parchment-zoom")
	ok = ok and await _resize(360, 640)
	ok = ok and await wait_until(func() -> bool: return parchment.is_open(), 2.0)
	ok = ok and is_equal_approx(float(parchment.cell_px), float(parchment.DEFAULT_CELL_PX))
	await snapshot("parchment-zoom-default-phone")
	await _wheel(parchment, Vector2(180, 320), false)
	ok = ok and parchment.cell_px == parchment.min_cell_px()
	await snapshot("parchment-zoom-min-phone")
	for _i in 24:
		await _wheel(parchment, Vector2(180, 320), true)
	ok = ok and parchment.cell_px == parchment.MAX_CELL_PX
	await snapshot("parchment-zoom-max-phone")
	await _drag(PARCHMENT, Vector2(40, 30))
	await click("CanvasLayer1/ParchmentMap/RecentreButton")
	ok = ok and parchment.pan == Vector2.ZERO and parchment.cell_px == parchment.MAX_CELL_PX
	await snapshot("parchment-recentred-phone")
	print("explored_map: zoom default %s min %s max %s px %s"
			% [parchment.DEFAULT_CELL_PX, parchment.min_cell_px(), parchment.MAX_CELL_PX, parchment.cell_px])

	step("input-blocked")
	var stuck := hero().position
	for action in WALK:
		await hold(action, 8)
	await tap("attack")
	await physics_frame
	var blocked: bool = hero().position.distance_to(stuck) < 1.0 and not hero().isAttacking
	print("explored_map: blocked %s attacking %s" % [blocked, hero().isAttacking])
	ok = ok and blocked

	step("close")
	await click(CLOSE)
	ok = ok and await wait_until(func() -> bool: return not parchment.is_open() and panel.visible, 2.0)
	var menu: Control = current_scene.get_node(MENU_PANEL)
	print("explored_map: closed panel %s map %s menu %s" % [panel.visible, parchment.is_open(), menu.visible])
	ok = ok and not menu.visible
	await snapshot("closed-landscape")

	step("input-restored")
	var moved := false
	for action in WALK:
		var at := hero().position
		await hold(action, 18)
		if hero().position.distance_to(at) >= 1.0:
			moved = true
			break
	print("explored_map: moved after close %s" % moved)
	ok = ok and moved

	step("phone-landscape")
	ok = ok and await _resize(854, 480)
	await click(COLLAPSE)
	ok = ok and await wait_until(func() -> bool: return not panel.visible, 2.0)
	await snapshot("collapsed-phone-landscape")
	await click(MAP_BUTTON)
	await click(MAXIMIZE)
	ok = ok and await wait_until(func() -> bool: return parchment.is_open(), 2.0)
	await _drag(PARCHMENT, Vector2(48, 24))
	await snapshot("parchment-phone-landscape")
	await click(CLOSE)
	ok = ok and await wait_until(func() -> bool: return panel.visible and not parchment.is_open(), 2.0)
	print("explored_map: phone landscape window %s panel %s" % [DisplayServer.window_get_size(), panel.visible])

	step("phone-portrait")
	ok = ok and await _resize(360, 640)
	ok = ok and _inside(panel) and _inside(panel.get_node("CollapseButton")) and _inside(panel.get_node("MaximizeButton"))
	await snapshot("open-phone-portrait")
	await click(COLLAPSE)
	var map_button: Control = current_scene.get_node(MAP_BUTTON)
	ok = ok and await wait_until(func() -> bool: return not panel.visible, 2.0)
	ok = ok and _inside(map_button)
	await snapshot("collapsed-phone-portrait")
	await click(MAP_BUTTON)
	await click(MAXIMIZE)
	ok = ok and await wait_until(func() -> bool: return parchment.is_open(), 2.0)
	ok = ok and _inside(parchment.get_node("CloseButton"))
	await snapshot("parchment-phone-portrait")
	await click(CLOSE)
	ok = ok and await wait_until(func() -> bool: return panel.visible, 2.0)
	print("explored_map: phone portrait window %s ok so far %s" % [DisplayServer.window_get_size(), ok])

	done(ok)


func _drag(path: String, delta: Vector2) -> void:
	var control: Control = current_scene.get_node(path)
	var at := to_window(control, control.size * 0.5)
	var events: Array[InputEvent] = []
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	events.append(move)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	events.append(press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = at + delta
	motion.global_position = at + delta
	motion.relative = delta
	events.append(motion)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = at + delta
	release.global_position = at + delta
	events.append(release)
	for event in events:
		Input.parse_input_event(event)
		await process_frame
		await process_frame


func _resize(width: int, height: int) -> bool:
	root.size = Vector2i(width, height)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(width, height))
	for _i in 10:
		await process_frame
	var got := DisplayServer.window_get_size()
	print("explored_map: window %s (asked %dx%d)" % [got, width, height])
	return got.x == width and got.y == height


func _wheel(parchment: ParchmentMap, at: Vector2, up: bool) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	press.pressed = true
	press.position = at
	parchment._gui_input(press)
	await process_frame


func _inside(control: Control) -> bool:
	var view := current_scene.get_viewport().get_visible_rect()
	var rect := control.get_global_rect()
	var inside := view.encloses(rect)
	if not inside:
		print("explored_map: %s rect %s outside %s" % [control.name, rect, view])
	return inside
