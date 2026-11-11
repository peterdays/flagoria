extends "res://tests/helpers/test_helpers.gd"
## The Worlds list scrolls when more saves exist than fit; touch drag and wheel
## move it without loading a world.


const SCROLL := "CanvasLayer2/WorldsPanel/Margin/VBox/Scroll"
const LIST := SCROLL + "/List"
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(2400, 1080)]
const SAVE_COUNT := 14


func _test_worlds_list_scroll() -> int:
	print("-- test_worlds_list_scroll")
	var fail := 0
	var paths: PackedStringArray = []
	for i in SAVE_COUNT:
		var name := "scroll-%02d" % i
		var params := MapGenParams.make_defaults()
		params.ensure_seeds()
		params.altitude_seed = 1000 + i
		var saved := MapSave.save_world(WorldSave.new(params), name)
		if saved["error"] != "":
			printerr("FAIL worlds_list_scroll: save %s" % saved["error"])
			fail += 1
			continue
		paths.append(saved["path"])
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	var vp: Viewport = scene.get_viewport()
	for size in VIEWPORTS:
		vp.size = size
		root.size = size
		await process_frame
		await process_frame
		menu._on_worlds_pressed()
		await process_frame
		await process_frame
		fail += await _check_scroll_at_size(scene, vp, size)
		menu._on_worlds_back_pressed()
		await process_frame
	scene.queue_free()
	await process_frame
	for path in paths:
		DirAccess.remove_absolute(path)
	if fail == 0:
		print("PASS test_worlds_list_scroll")
	return fail


func _check_scroll_at_size(scene, vp: Viewport, size: Vector2i) -> int:
	var fail := 0
	var scroll: ScrollContainer = scene.get_node(SCROLL)
	var list: ItemList = scene.get_node(LIST)
	if list.item_count < SAVE_COUNT:
		printerr("FAIL worlds_list_scroll %s: list has %d rows" % [size, list.item_count])
		return 1
	var view_h := scroll.size.y
	var content_h := list.size.y
	if content_h <= view_h + 1.0:
		printerr("FAIL worlds_list_scroll %s: list height %.1f fits box %.1f" % [size, content_h, view_h])
		fail += 1
		return fail
	scroll.scroll_vertical = 0
	await process_frame
	var before := scroll.scroll_vertical
	if not await _wheel(vp, scroll, true):
		printerr("FAIL worlds_list_scroll %s: wheel did not scroll down" % size)
		fail += 1
	if scroll.scroll_vertical <= before:
		printerr("FAIL worlds_list_scroll %s: wheel left scroll at %d" % [size, scroll.scroll_vertical])
		fail += 1
	scroll.scroll_vertical = 0
	await process_frame
	before = scroll.scroll_vertical
	var drag_start := _to_window(scroll, Vector2(scroll.size.x * 0.5, scroll.size.y * 0.75))
	var drag_end := _to_window(scroll, Vector2(scroll.size.x * 0.5, scroll.size.y * 0.25))
	if not await _touch_drag_scroll(vp, scroll, drag_start, drag_end):
		printerr("FAIL worlds_list_scroll %s: touch drag did not scroll" % size)
		fail += 1
	if scroll.scroll_vertical <= before:
		printerr("FAIL worlds_list_scroll %s: drag left scroll at %d" % [size, scroll.scroll_vertical])
		fail += 1
	var pick := mini(8, list.item_count - 1)
	scroll.scroll_vertical = int(list.get_item_rect(pick).position.y)
	await process_frame
	await process_frame
	var rect := list.get_item_rect(pick)
	var tap_at := _to_window(list, rect.position + rect.size * 0.5)
	var world: Node = scene.get_node("World")
	if not await _tap(vp, tap_at):
		printerr("FAIL worlds_list_scroll %s: tap on row %d failed" % [size, pick])
		fail += 1
	elif not list.get_selected_items().has(pick):
		printerr("FAIL worlds_list_scroll %s: tap did not select row %d" % [size, pick])
		fail += 1
	elif scene.save_name != "":
		printerr("FAIL worlds_list_scroll %s: tap started a match" % size)
		fail += 1
	return fail


func _to_window(item: CanvasItem, local: Vector2) -> Vector2:
	return root.get_final_transform() * (item.get_global_transform_with_canvas() * local)


func _wheel(_vp: Viewport, scroll: ScrollContainer, down: bool) -> bool:
	var at := _to_window(scroll, scroll.size * 0.5)
	var before := scroll.scroll_vertical
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	ev.position = at
	ev.global_position = at
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	return scroll.scroll_vertical != before


func _touch_drag_scroll(_vp: Viewport, scroll: ScrollContainer, start: Vector2, end: Vector2) -> bool:
	var before := scroll.scroll_vertical
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = start
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	var prev := start
	for i in range(1, 12):
		var pos := start.lerp(end, float(i) / 11.0)
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = pos
		drag.relative = pos - prev
		prev = pos
		Input.parse_input_event(drag)
		await process_frame
	touch.pressed = false
	touch.position = end
	Input.parse_input_event(touch)
	await process_frame
	return scroll.scroll_vertical > before


func _tap(_vp: Viewport, at: Vector2) -> bool:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await process_frame
	return true
