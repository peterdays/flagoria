extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 7
## Pick a flower in interact mode, save, reload, and check it stays gone.

const WORLDS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/WorldsButton"
const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"
const STATUS := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/Status"
const LIST := "CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List"
const LOAD := "CanvasLayer2/WorldsPanel/Margin/VBox/Buttons/Load"
const ATTACK := "CanvasLayer1/TouchScreenButton"
const DECOR := 2


func run() -> void:
	step("play")
	if not await start_game():
		done(false)
		return
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	map.set_process(false)
	var flower := _flower_in_reach(map)
	if flower == Vector2i.ZERO:
		printerr("object removals: no flower near the hero")
		done(false)
		return
	map.generate_chunk(map.map_to_local(flower))
	if map.get_cell_atlas_coords(DECOR, flower) != TileCatalog.FLOWER:
		printerr("object removals: %s is not a flower" % flower)
		done(false)
		return
	await snapshot("before_pick")
	await _face_cell(map, flower)
	if not await _pick_flower(map, flower):
		done(false)
		return
	map.generate_chunk(map.map_to_local(flower))
	if map.get_cell_source_id(DECOR, flower) != -1:
		printerr("object removals: decor still drawn at %s" % flower)
		done(false)
		return
	await snapshot("picked")

	step("save")
	if not await menu_save():
		done(false)
		return
	var status: Label = current_scene.get_node(STATUS)
	if not await wait_until(func() -> bool: return status.text.begins_with("Saved:"), 5.0):
		printerr("object removals: save status '%s'" % status.text)
		done(false)
		return
	if not await _leave_and_load():
		done(false)
		return
	map = current_scene.get_node(WORLD_MAP)
	map.generate_chunk(map.map_to_local(flower))
	var ok: bool = map.get_cell_source_id(DECOR, flower) == -1
	await snapshot("loaded")
	await _phone_portrait()
	await snapshot("loaded-phone")
	if ok:
		print("object removals: flower %s stayed gone after reload" % flower)
	done(ok)


func _flower_in_reach(map: TileMap) -> Vector2i:
	## A ground flower two cells north of the hero, on grass, in chop reach.
	var origin: Vector2i = map.local_to_map(map.to_local(hero().global_position))
	var flower := origin + Vector2i(0, -2)
	map.set_cell(0, flower, TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	map.erase_cell(1, flower)
	map.set_cell(DECOR, flower, TileCatalog.SOURCE_ID, TileCatalog.FLOWER)
	return flower


func _face_cell(map: TileMap, cell: Vector2i) -> void:
	var delta: Vector2 = map.to_global(map.map_to_local(cell)) - hero().global_position
	if absf(delta.x) > absf(delta.y):
		await hold("ui_right" if delta.x > 0 else "ui_left", 0.15)
	else:
		await hold("ui_down" if delta.y > 0 else "ui_up", 0.15)


func _pick_flower(map: TileMap, flower: Vector2i) -> bool:
	await toggle_mode()
	var it: Node = current_scene.get_node("World/Interaction")
	if not await wait_until(func() -> bool: return it.mode == 1, 2.0):
		printerr("object removals: interact mode did not activate")
		return false
	var aim := map.to_global(map.map_to_local(flower)) - hero().global_position
	await _drag_from_button(_window_delta(aim), "")
	var ok := await wait_until(func() -> bool: return map.get_cell_source_id(DECOR, flower) == -1, 3.0)
	if not ok:
		printerr("object removals: flower at %s not picked" % flower)
	return ok


func _leave_and_load() -> bool:
	await click(MENU_BUTTON)
	var panel: Control = current_scene.get_node(MENU_PANEL)
	if not await wait_until(func() -> bool: return panel.is_visible_in_tree(), 5.0):
		return false
	await click(MAIN_MENU_BUTTON)
	if not await wait_until(func() -> bool:
			return current_scene.has_node(WORLDS) and hero() == null, 15.0):
		return false
	await click(WORLDS)
	var list: ItemList = current_scene.get_node(LIST)
	if not await wait_until(func() -> bool: return list.item_count > 0, 5.0):
		return false
	await click_at_list(list, 0)
	await click(LOAD)
	return await wait_until(func() -> bool: return hero() != null, START_TIMEOUT_S)


func click_at_list(list: ItemList, index: int) -> void:
	var rect := list.get_item_rect(index)
	await _click_at(list, rect.position + rect.size * 0.5)


func _phone_portrait() -> void:
	var win := current_scene.get_window()
	win.size = Vector2i(360, 640)
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	await process_frame


func _button_window() -> Vector2:
	var button: CanvasItem = current_scene.get_node(ATTACK)
	return to_window(button, button._shape_center())


func _window_delta(world_delta: Vector2) -> Vector2:
	var here := to_window(hero(), Vector2.ZERO)
	var there := to_window(hero(), hero().to_local(hero().global_position + world_delta))
	return there - here


func _drag_from_button(window_delta: Vector2, aim_shot: String) -> void:
	var origin := _button_window()
	var end_pos := origin + window_delta
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = origin
	Input.parse_input_event(press)
	await process_frame
	await process_frame
	if window_delta.length() > Interaction.DRAG_START:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = end_pos
		drag.relative = window_delta
		Input.parse_input_event(drag)
		await process_frame
		await process_frame
	var lift := InputEventScreenTouch.new()
	lift.index = 0
	lift.pressed = false
	lift.position = end_pos
	Input.parse_input_event(lift)
	await process_frame
	await process_frame


func _click_at(item: CanvasItem, local: Vector2) -> void:
	var at := to_window(item, local)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await process_frame
		await process_frame