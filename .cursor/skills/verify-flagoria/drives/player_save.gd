extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## Walk, chop the nearest plant, save, leave, and load that world.
## before_save and loaded show the same spot and the same wood.

const WORLDS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/WorldsButton"
const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"
const STATUS := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/Status"
const LIST := "CanvasLayer2/WorldsPanel/Margin/VBox/List"
const LOAD := "CanvasLayer2/WorldsPanel/Margin/VBox/Buttons/Load"


func run() -> void:
	step("play")
	if not await start_game():
		done(false)
		return
	var origin := hero().global_position
	# Seed 49 puts a plant next to the spawn. Chop that before walking away.
	var cell := _nearest_plant()
	if cell == Vector2i.ZERO or not await _chop(cell):
		done(false)
		return
	await hold("ui_right", 40)
	await hold("ui_up", 25)
	if hero().global_position.distance_to(origin) < 24.0:
		await hold("ui_left", 40)
		await hold("ui_down", 25)
	var wood: int = current_scene.get_node(INVENTORY).count_of(Inventory.WOOD)
	if wood < 1 or hero().global_position.distance_to(origin) < 24.0:
		printerr("player save: wood %s moved %s" % [wood, hero().global_position.distance_to(origin)])
		done(false)
		return
	var before := _progress()
	await snapshot("before_save")

	step("save")
	if not await menu_save():
		printerr("player save: Save did not open")
		done(false)
		return
	var status: Label = current_scene.get_node(STATUS)
	if not await wait_until(func() -> bool: return status.text.begins_with("Saved:"), 5.0):
		printerr("player save: status '%s'" % status.text)
		done(false)
		return
	await snapshot("saved")
	if not await _leave() or not await _open_worlds():
		done(false)
		return

	step("load")
	var list: ItemList = current_scene.get_node(LIST)
	if list.item_count < 1 or not await _click_item(list, 0):
		printerr("player save: the list has %d rows" % list.item_count)
		done(false)
		return
	await click(LOAD)
	if not await wait_until(func() -> bool: return hero() != null, START_TIMEOUT_S):
		printerr("player save: the loaded world did not start")
		done(false)
		return
	var panel: Control = current_scene.get_node(MINIMAP)
	if not await wait_until(func() -> bool: return panel.visible, 5.0):
		printerr("player save: the chart did not show")
		done(false)
		return
	await snapshot("loaded")
	var after := _progress()
	var spot_ok: bool = Vector2(before["x"], before["y"]).distance_to(Vector2(after["x"], after["y"])) <= 48.0
	var ok: bool = spot_ok and after["wood"] == before["wood"] and after["health"] == before["health"] \
			and after["score"] == before["score"] and after["chart"] >= before["chart"] and before["chart"] > 0
	if not ok:
		printerr("player save: before %s after %s" % [before, after])
	else:
		print("player save: back at %s wood %s chart %s" % [Vector2(after["x"], after["y"]), after["wood"], after["chart"]])
	done(ok)


func _progress() -> Dictionary:
	var h := hero()
	return {
		"x": h.global_position.x,
		"y": h.global_position.y,
		"health": h.health.health,
		"wood": current_scene.get_node(INVENTORY).count_of(Inventory.WOOD),
		"score": current_scene.get_node("Points").total_of(int(str(h.name))),
		"chart": current_scene.get_node(MINIMAP).explored.explored_count(),
	}


func _leave() -> bool:
	await click(MENU_BUTTON)
	var panel: Control = current_scene.get_node(MENU_PANEL)
	if not await wait_until(func() -> bool: return panel.is_visible_in_tree(), 5.0):
		printerr("player save: the menu did not open")
		return false
	await click(MAIN_MENU_BUTTON)
	return await wait_until(func() -> bool:
		return current_scene != null and current_scene.has_node(WORLDS) and hero() == null, 15.0)


func _open_worlds() -> bool:
	await click(WORLDS)
	return await wait_until(func() -> bool:
		return current_scene.has_node(LIST) and current_scene.get_node(LIST).is_visible_in_tree(), 5.0)


func _click_item(list: ItemList, index: int) -> bool:
	for _i in 10:
		if list.get_item_rect(index).size.y > 1.0:
			break
		await process_frame
	var rect := list.get_item_rect(index)
	if rect.size.y <= 1.0:
		printerr("player save: row %d has no rect" % index)
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
		printerr("player save: the plant at %s was not cut" % cell)
	return ok
