extends "res://tests/helpers/test_helpers.gd"
## Per-device HUD layout: save, load, clamp, overlap rejection, Reset.


func _hud() -> Node:
	return root.get_node("HudLayout")


func _test_hud_layout_round_trip() -> int:
	print("-- test_hud_layout_round_trip")
	var fail := 0
	var path := "user://test_hud_layout.cfg"
	_hud().save_path = path
	_hud().reset_to_defaults()
	var scene = await _play_scene()
	var layer: CanvasLayer = scene.get_node("CanvasLayer1")
	await process_frame
	_hud().edit_begin(layer)
	_hud().save_to_disk()
	_hud().edit_end()
	_hud().forget_memory()
	_hud().load_from_disk()
	if not _hud().uses_custom():
		printerr("FAIL hud_layout_round_trip: load did not restore custom layout")
		fail += 1
	_hud().apply(layer)
	await process_frame
	for id in ["joystick", "attack", "run", "buildings", "map", "mode"]:
		if _hud().get_entry(id).is_empty():
			printerr("FAIL hud_layout_round_trip: missing %s after load" % id)
			fail += 1
	_hud().reset_to_defaults()
	DirAccess.remove_absolute(path)
	_hud().save_path = "user://hud_layout.cfg"
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_hud_layout_round_trip")
	return fail


func _test_hud_layout_clamp_overlap() -> int:
	print("-- test_hud_layout_clamp_overlap")
	var fail := 0
	_hud().reset_to_defaults()
	var scene = await _play_scene()
	var layer: CanvasLayer = scene.get_node("CanvasLayer1")
	await process_frame
	_hud().edit_begin(layer)
	var view := layer.get_viewport().get_visible_rect().size
	if not _hud().try_place("attack", -0.5, 0.5, 1.0, layer):
		printerr("FAIL hud_layout_clamp: clamped place failed")
		fail += 1
	var rect: Rect2 = _hud().control_hit_rect("attack", layer)
	if rect.position.x < _hud().SIDE - 0.5:
		printerr("FAIL hud_layout_clamp: attack still off-screen %s" % rect)
		fail += 1
	var mode: Dictionary = _hud().get_entry("mode")
	if mode.is_empty():
		printerr("FAIL hud_layout_overlap: no mode entry")
		fail += 1
	else:
		var placed: bool = _hud().try_place("attack", float(mode.get("x")), float(mode.get("y")), 1.0, layer)
		if placed:
			printerr("FAIL hud_layout_overlap: attack overlaps mode")
			fail += 1
	_hud().reset_to_defaults()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_hud_layout_clamp_overlap")
	return fail


func _test_hud_layout_reset() -> int:
	print("-- test_hud_layout_reset")
	var fail := 0
	_hud().reset_to_defaults()
	var scene = await _play_scene()
	var layer: CanvasLayer = scene.get_node("CanvasLayer1")
	await process_frame
	var before: Rect2 = _hud().control_hit_rect("attack", layer)
	_hud().edit_begin(layer)
	_hud().try_place("attack", 0.7, 0.3, 1.25, layer)
	_hud().save_to_disk()
	var moved: Rect2 = _hud().control_hit_rect("attack", layer)
	if before.position.distance_to(moved.position) < 5.0:
		printerr("FAIL hud_layout_reset: attack did not move before reset")
		fail += 1
	_hud().reset_to_defaults()
	await process_frame
	await process_frame
	var row := layer.get_node("HudToolRow") as HudToolRow
	row._layout()
	await process_frame
	var after: Rect2 = _hud().control_hit_rect("attack", layer)
	if not _hud().uses_custom() and before.position.distance_to(after.position) > 8.0:
		printerr("FAIL hud_layout_reset: attack %s want near %s" % [after.position, before.position])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_hud_layout_reset")
	return fail


func _play_scene() -> Node:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(49, 0.003)
	world.apply_map_params(scene.world_params)
	await process_frame
	scene.add_player(scene.multiplayer.get_unique_id())
	await process_frame
	await process_frame
	return scene
