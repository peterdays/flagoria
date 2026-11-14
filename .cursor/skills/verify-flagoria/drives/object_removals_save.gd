extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 7
## Pick a flower and destroy stones, save, reload; evidence zooms on the hero.

const WORLDS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/WorldsButton"
const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"
const STATUS := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/Status"
const LIST := "CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List"
const LOAD := "CanvasLayer2/WorldsPanel/Margin/VBox/Buttons/Load"
const ATTACK := "CanvasLayer1/TouchScreenButton"
const DECOR := 2
const PHONE_W := 854
const PHONE_H := 480


func run() -> void:
	step("play")
	if not await start_game():
		done(false)
		return
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var spots := _demo_spots(map)
	var flower: Vector2i = spots["flower"]
	var stone: Vector2i = spots["stone"]
	_staged_decor(map, flower, stone)
	await _stand_between(map, flower, stone)
	var points: Node = root.get_node_or_null("Points")
	var score_before := int(points.total_of(1)) if points else 0
	print("object removals: castle %s score %d" % [_castle_line(map), score_before])
	await snapshot("01-before")
	await _snapshot_zoom("01-before-zoom", flower, stone)

	if not await _pick_flower(map, flower):
		done(false)
		return
	if not await _destroy_stone(map, stone):
		done(false)
		return
	if map.get_cell_source_id(DECOR, flower) != -1 or map.get_cell_source_id(DECOR, stone) != -1:
		printerr("object removals: decor still drawn flower %s stone %s" % [flower, stone])
		done(false)
		return
	await snapshot("02-after")
	await _snapshot_zoom("02-after-zoom", flower, stone)

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
	map.generate_chunk(map.map_to_local(stone))
	await _stand_between(map, flower, stone)
	var score_after := int(points.total_of(1)) if points else 0
	print("object removals: loaded castle %s score %d" % [_castle_line(map), score_after])
	var ok: bool = map.get_cell_source_id(DECOR, flower) == -1 \
			and map.get_cell_source_id(DECOR, stone) == -1
	await snapshot("03-loaded")
	await _snapshot_zoom("03-loaded-zoom", flower, stone)
	await _phone_landscape()
	await snapshot("04-loaded-phone")
	if ok:
		print("object removals: flower %s stone %s stayed gone (score %d -> %d)"
				% [flower, stone, score_before, score_after])
	done(ok)


func _demo_spots(map: TileMap) -> Dictionary:
	## Grass south of the gate: flower west, stone east, hero between.
	var front: Vector2i = map.local_to_map(map.to_local(hero().global_position))
	var base := front + Vector2i(0, 3)
	return {"flower": base + Vector2i(-1, 0), "stone": base + Vector2i(1, 0)}


func _staged_decor(map: TileMap, flower: Vector2i, stone: Vector2i) -> void:
	for cell in [flower, stone, flower + Vector2i(0, 1), stone + Vector2i(0, 1)]:
		map.set_cell(0, cell, TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
		map.erase_cell(1, cell)
		map.erase_cell(DECOR, cell)
	map.set_cell(DECOR, flower, TileCatalog.SOURCE_ID, TileCatalog.FLOWER)
	map.set_cell(DECOR, stone, TileCatalog.SOURCE_ID, TileCatalog.STONES)
	map.generate_chunk(map.map_to_local(flower))
	map.generate_chunk(map.map_to_local(stone))


func _stand_between(map: TileMap, flower: Vector2i, stone: Vector2i) -> void:
	var mid := Vector2i((flower.x + stone.x) / 2, (flower.y + stone.y) / 2)
	hero().global_position = map.to_global(map.map_to_local(mid))
	for i in 6:
		await process_frame


func _castle_line(map: TileMap) -> String:
	for id in map.placed_structures():
		var entry: Dictionary = map.placed_structures()[id]
		if entry.get("name") == "castle":
			var anchor: Vector2i = entry["anchor"]
			var flag := map.get_cell_atlas_coords(1, anchor + Vector2i(0, -1))
			return "owner=%d flag_atlas=%s" % [int(entry["owner"]), flag]
	return "no castle"


func _pick_flower(map: TileMap, flower: Vector2i) -> bool:
	await toggle_mode()
	var it: Node = current_scene.get_node("World/Interaction")
	if not await wait_until(func() -> bool: return it.mode == 1, 2.0):
		printerr("object removals: interact mode did not activate")
		return false
	var delta := _button_drag_toward(it, flower, 80.0)
	if delta == Vector2.ZERO:
		printerr("object removals: no chop drag toward flower %s" % flower)
		return false
	await _drag_from_button(delta, "")
	var ok := await wait_until(func() -> bool: return map.get_cell_source_id(DECOR, flower) == -1, 3.0)
	if not ok:
		printerr("object removals: flower at %s not picked" % flower)
	return ok


func _destroy_stone(map: TileMap, stone: Vector2i) -> bool:
	await toggle_mode()
	var it: Node = current_scene.get_node("World/Interaction")
	if not await wait_until(func() -> bool: return it.mode == 0, 2.0):
		printerr("object removals: combat mode did not activate")
		return false
	var hero_cell := map.local_to_map(map.to_local(hero().global_position))
	if stone.x > hero_cell.x:
		await hold("ui_right", 10)
	elif stone.x < hero_cell.x:
		await hold("ui_left", 10)
	elif stone.y < hero_cell.y:
		await hold("ui_up", 10)
	else:
		await hold("ui_down", 10)
	await tap("attack")
	if not await wait_until(func() -> bool: return hero().isAttacking, 1.0):
		printerr("object removals: combat swing did not start at %s" % stone)
		return false
	await wait_until(func() -> bool: return not hero().isAttacking, 2.0)
	var ok := map.get_cell_source_id(DECOR, stone) == -1
	if not ok:
		printerr("object removals: stone at %s not destroyed" % stone)
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


func _phone_landscape() -> void:
	var win := current_scene.get_window()
	win.size = Vector2i(PHONE_W, PHONE_H)
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(PHONE_W, PHONE_H))
	for i in 10:
		await process_frame


func _snapshot_zoom(label: String, flower: Vector2i, stone: Vector2i) -> void:
	var dir := OS.get_environment("VERIFY_EVIDENCE_DIR")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var mid := Vector2i((flower.x + stone.x) / 2, (flower.y + stone.y) / 2)
	var canvas := map.get_global_transform_with_canvas() * map.map_to_local(mid)
	var vp := current_scene.get_viewport()
	var img_size := root.get_texture().get_size()
	var vis := vp.get_visible_rect().size
	var vp_scale := Vector2(img_size.x / vis.x, img_size.y / vis.y)
	var screen := root.get_final_transform() * canvas
	var tile := float(map.tile_set.tile_size.x) * map.global_scale.x * vp_scale.x
	var half := int(tile * 4.0)
	var region := Rect2i(
			int(screen.x) - half, int(screen.y) - half, half * 2, half * 2)
	region = region.intersection(Rect2i(Vector2i.ZERO, img_size))
	if region.size.x < 8 or region.size.y < 8:
		printerr("object removals: zoom region empty %s" % region)
		return
	var crop := root.get_texture().get_image().get_region(region)
	var zoom := crop.duplicate()
	zoom.resize(region.size.x * 6, region.size.y * 6, Image.INTERPOLATE_NEAREST)
	var path := dir.path_join("%s.png" % label.validate_filename())
	if zoom.save_png(path) == OK:
		print("drive: zoom %s (%s)" % [path.get_file(), region])


func _button_window() -> Vector2:
	var button: CanvasItem = current_scene.get_node(ATTACK)
	return to_window(button, button._shape_center())


func _window_delta(world_delta: Vector2) -> Vector2:
	var here := to_window(hero(), Vector2.ZERO)
	var there := to_window(hero(), hero().to_local(hero().global_position + world_delta))
	return there - here


func _button_drag_toward(it: Node, cell: Vector2i, min_px: float) -> Vector2:
	var origin := hero().global_position
	var to_cell: Vector2 = it.cell_center(cell) - origin
	if to_cell.length() < 4.0:
		printerr("object removals: cell %s too close" % cell)
		return Vector2.ZERO
	var end_world: Vector2 = origin + to_cell.normalized() * minf(to_cell.length() + 20.0, Interaction.CHOP_REACH - 4.0)
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var start := _button_window()
	var end := to_window(map, map.to_local(end_world))
	var delta := end - start
	if delta.length() < maxf(min_px, Interaction.DRAG_START + 2.0):
		delta = delta.normalized() * maxf(min_px, Interaction.DRAG_START + 8.0)
	return delta


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
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = end_pos
	drag.relative = window_delta
	Input.parse_input_event(drag)
	await process_frame
	await process_frame
	if aim_shot != "":
		await snapshot(aim_shot)
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