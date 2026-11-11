extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## Save two worlds from the main menu. The second cuts the nearest plant.
## The list shows both. Loading each shows the plant, then the stump.

const WORLDS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/WorldsButton"
const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"
const LIST := "CanvasLayer2/WorldsPanel/Margin/VBox/List"
const NEW_WORLD := "CanvasLayer2/WorldsPanel/Margin/VBox/Buttons/NewWorld"
const LOAD := "CanvasLayer2/WorldsPanel/Margin/VBox/Buttons/Load"

var _cut := Vector2i.ZERO


func run() -> void:
	step("start")
	if not await start_game() or not await _save_and_leave():
		done(false)
		return
	step("world-b")
	if not await _open_worlds():
		done(false)
		return
	await click(NEW_WORLD)
	if not await wait_until(func() -> bool: return hero() != null, START_TIMEOUT_S):
		printerr("saved worlds: the second world did not start")
		done(false)
		return
	_cut = _nearest_plant()
	if _cut == Vector2i.ZERO:
		printerr("saved worlds: no plant within chop reach of %s" % hero().global_position)
		done(false)
		return
	if not await _chop(_cut) or not await _save_and_leave():
		done(false)
		return
	step("list")
	if not await _open_worlds():
		done(false)
		return
	var list: ItemList = current_scene.get_node(LIST)
	if list.item_count < 2:
		printerr("saved worlds: the list has %d rows" % list.item_count)
		done(false)
		return
	await snapshot("list")
	# Newest first: row 0 is the cut world, row 1 is the first save.
	step("load-a")
	if not await _load_row(1, "loaded-a", true):
		done(false)
		return
	step("load-b")
	if not await _leave() or not await _open_worlds() or not await _load_row(0, "loaded-b", false):
		done(false)
		return
	done(true)


func _save_and_leave() -> bool:
	if not await menu_save():
		printerr("saved worlds: Save did not open")
		return false
	return await _leave()


func _leave() -> bool:
	await click(MENU_BUTTON)
	var panel: Control = current_scene.get_node(MENU_PANEL)
	if not await wait_until(func() -> bool: return panel.is_visible_in_tree(), 5.0):
		printerr("saved worlds: the menu did not open")
		return false
	await click(MAIN_MENU_BUTTON)
	return await wait_until(func() -> bool:
		return current_scene != null and current_scene.has_node(WORLDS) and hero() == null, 15.0)


func _open_worlds() -> bool:
	await click(WORLDS)
	return await wait_until(func() -> bool:
		return current_scene.has_node(LIST) and current_scene.get_node(LIST).is_visible_in_tree(), 5.0)


func _load_row(index: int, shot: String, plant_stands: bool) -> bool:
	var list: ItemList = current_scene.get_node(LIST)
	if not await _click_item(list, index):
		return false
	await click(LOAD)
	if not await wait_until(func() -> bool: return hero() != null, START_TIMEOUT_S):
		printerr("saved worlds: %s did not start" % shot)
		return false
	await snapshot(shot)
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var standing: bool = map.choppable(_cut) != null
	if standing != plant_stands:
		printerr("saved worlds: %s plant at %s standing=%s, want %s" % [shot, _cut, standing, plant_stands])
		return false
	print("saved worlds: %s plant standing=%s" % [shot, standing])
	return true


func _click_item(list: ItemList, index: int) -> bool:
	for _i in 10:
		if list.get_item_rect(index).size.y > 1.0:
			break
		await process_frame
	var rect := list.get_item_rect(index)
	if rect.size.y <= 1.0:
		printerr("saved worlds: row %d has no rect" % index)
		return false
	await _click_at(list, rect.position + rect.size * 0.5)
	return list.get_selected_items().has(index)


func _click_at(item: CanvasItem, local: Vector2) -> void:
	var at := to_window(item, local)
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
		await process_frame


func _nearest_plant() -> Vector2i:
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var origin: Vector2i = map.local_to_map(map.to_local(hero().global_position))
	var best := Vector2i.ZERO
	var best_d := INF
	for y in range(-16, 17):
		for x in range(-16, 17):
			var cell := origin + Vector2i(x, y)
			if map.choppable(cell) == null:
				continue
			var d: float = hero().global_position.distance_to(map.to_global(map.map_to_local(cell)))
			if d < best_d and d <= 240.0:
				best = cell
				best_d = d
	return best if best_d < INF else Vector2i.ZERO


func _chop(cell: Vector2i) -> bool:
	await click(MODE_BUTTON)
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var delta: Vector2 = map.to_global(map.map_to_local(cell)) - hero().global_position
	var reach: Vector2 = delta.normalized() * minf(delta.length() + 20.0, 240.0)
	var button: CanvasItem = current_scene.get_node("CanvasLayer1/TouchScreenButton")
	var origin := to_window(button, button._shape_center())
	var here := to_window(hero(), Vector2.ZERO)
	var there := to_window(hero(), hero().to_local(hero().global_position + reach))
	var end := origin + (there - here)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = origin
	Input.parse_input_event(press)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = end
	drag.relative = end - origin
	Input.parse_input_event(drag)
	await process_frame
	var lift := InputEventScreenTouch.new()
	lift.index = 0
	lift.pressed = false
	lift.position = end
	Input.parse_input_event(lift)
	await process_frame
	var ok := await wait_until(func() -> bool: return map.choppable(cell) == null, 6.0)
	if not ok:
		printerr("saved worlds: the plant at %s was not cut" % cell)
	return ok
