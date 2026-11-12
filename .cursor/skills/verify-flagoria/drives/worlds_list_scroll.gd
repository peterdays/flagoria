extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --display
## Worlds list scroll evidence at 1280x720 and 2400x1080 with touch drag.

const WORLDS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/WorldsButton"
const SCROLL := "CanvasLayer2/WorldsPanel/Margin/VBox/Scroll"
const LIST := SCROLL + "/List"
const SAVE_COUNT := 14
const WORLDS_BACK := "CanvasLayer2/WorldsPanel/Margin/VBox/Back"


func run() -> void:
	if not await _seed_saves():
		done(false)
		return
	if change_scene_to_file(MAIN) != OK:
		done(false)
		return
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(WORLDS), START_TIMEOUT_S):
		done(false)
		return
	for spec in [{"name": "720", "size": Vector2i(1280, 720)}, {"name": "1080", "size": Vector2i(2400, 1080)}]:
		step("scroll-%s" % spec["name"])
		if not await _capture_scroll(spec["name"], spec["size"]):
			done(false)
			return
	done(true)


func _seed_saves() -> bool:
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	for i in SAVE_COUNT:
		var params := MapGenParams.make_defaults()
		params.ensure_seeds()
		params.altitude_seed = 5000 + i
		var saved := MapSave.save_world(WorldSave.new(params), "drive-scroll-%02d" % i)
		if saved["error"] != "":
			printerr("worlds_list_scroll drive: save %s" % saved["error"])
			return false
	await process_frame
	return true


func _capture_scroll(label: String, size: Vector2i) -> bool:
	if current_scene.has_node(SCROLL) and current_scene.get_node(SCROLL).is_visible_in_tree():
		await click(WORLDS_BACK)
		await process_frame
	root.size = size
	var vp: Viewport = current_scene.get_viewport()
	vp.size = size
	await process_frame
	await process_frame
	await click(WORLDS)
	var scroll: ScrollContainer = current_scene.get_node(SCROLL)
	if not await wait_until(func() -> bool: return scroll.is_visible_in_tree(), 5.0):
		printerr("worlds_list_scroll drive: scroll box not visible")
		return false
	var list: ItemList = current_scene.get_node(LIST)
	if list.item_count < SAVE_COUNT:
		printerr("worlds_list_scroll drive: %d rows" % list.item_count)
		return false
	await snapshot("%s-top" % label)
	scroll.scroll_vertical = 0
	await process_frame
	if not await _drag_scroll(scroll):
		printerr("worlds_list_scroll drive: drag did not scroll at %s" % label)
		return false
	await snapshot("%s-scrolled" % label)
	var pick := mini(8, list.item_count - 1)
	scroll.scroll_vertical = int(list.get_item_rect(pick).position.y)
	await process_frame
	var rect := list.get_item_rect(pick)
	var at := to_window(list, rect.position + rect.size * 0.5)
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
	if not list.get_selected_items().has(pick):
		printerr("worlds_list_scroll drive: tap did not select row %d at %s" % [pick, label])
		return false
	await click(WORLDS_BACK)
	return true


func _drag_scroll(scroll: ScrollContainer) -> bool:
	var before := scroll.scroll_vertical
	var start := to_window(scroll, Vector2(scroll.size.x * 0.5, scroll.size.y * 0.8))
	var end := to_window(scroll, Vector2(scroll.size.x * 0.5, scroll.size.y * 0.2))
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
