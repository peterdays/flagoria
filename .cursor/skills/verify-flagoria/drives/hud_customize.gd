extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## Customize HUD from the in-game menu: default layout, edit mode, move attack,
## save, reload, overlap rejection, reset.
## bin/launch.sh drives/hud_customize.gd --display --seed 49

const CUSTOMIZE_BTN := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/CustomizeHud"
const ATTACK := "CanvasLayer1/TouchScreenButton"
const MAP := "CanvasLayer1/MinimapButton"
const EDIT_BAR := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar"
const DONE := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar/Margin/VBox/Row/Done"
const SAVE := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar/Margin/VBox/Row/Save"
const RESET := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar/Margin/VBox/Row/Reset"
const SIZE_SLIDER := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar/Margin/VBox/Row/SizeSlider"


func _hud_layout() -> Node:
	return root.get_node("HudLayout")


func _tap(at: Vector2) -> void:
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = at
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await process_frame


func _edit_bar_rect() -> Rect2:
	return (current_scene.get_node(EDIT_BAR) as Control).get_global_rect()


func _controls_clear_of_bar(layer: CanvasLayer, ids: Array) -> bool:
	var bar := _edit_bar_rect().grow(2.0)
	for id in ids:
		var rect: Rect2 = _hud_layout().control_hit_rect(id, layer)
		if rect.size != Vector2.ZERO and bar.intersects(rect):
			return false
	return true


func _tap_control(layer: CanvasLayer, id: String) -> void:
	var node_path: String = _hud_layout().PATHS[id] if _hud_layout().PATHS.has(id) else ""
	if id == "attack":
		node_path = "TouchScreenButton"
	var node = layer.get_node_or_null(node_path)
	if node == null:
		return
	var size := Vector2(48, 48)
	if id == "attack":
		var btn := node as TouchScreenButton
		size = btn.texture_normal.get_size() * btn.scale * 0.5 if btn.texture_normal else size
	elif node is Control:
		size = (node as Control).size * 0.5
	await _tap(to_window(node, size))


func run() -> void:
	if not await start_game():
		return
	var layer := current_scene.get_node("CanvasLayer1") as CanvasLayer
	var attack := current_scene.get_node(ATTACK) as TouchScreenButton
	var map_btn := current_scene.get_node(MAP) as Control
	var ok := attack != null and attack.texture_normal != null and map_btn != null
	step("default-layout")
	await snapshot("default-layout")
	var default_pos := attack.global_position
	var default_map := map_btn.global_position

	step("edit-mode")
	await click(MENU_BUTTON)
	await click(CUSTOMIZE_BTN)
	await process_frame
	ok = ok and current_scene.get_node("CanvasLayer1/InGameMenu/HudLayoutEdit").visible
	ok = ok and _controls_clear_of_bar(layer, ["map", "buildings", "mode"])
	var attack_at := to_window(attack, attack.texture_normal.get_size() * attack.scale * 0.5)
	await _tap(attack_at)
	await process_frame
	ok = ok and (current_scene.get_node(SIZE_SLIDER) as HSlider).editable
	await snapshot("edit-mode")

	step("moved-control")
	_hud_layout().try_place("attack", 0.62, 0.58, 1.35, layer)
	await process_frame
	ok = ok and attack.global_position.distance_to(default_pos) > 12.0
	await _tap_control(layer, "map")
	await process_frame
	_hud_layout().try_place("map", 0.52, 0.38, 1.15, layer)
	for _i in 16:
		await process_frame
	ok = ok and map_btn.global_position.distance_to(default_map) > 10.0
	ok = ok and _controls_clear_of_bar(layer, ["map", "buildings", "mode", "attack"])
	await snapshot("moved-control")

	step("no-overlap")
	var mode: Control = current_scene.get_node("CanvasLayer1/ModeButton")
	attack_at = to_window(attack, attack.texture_normal.get_size() * attack.scale * 0.5)
	await _tap(attack_at)
	var blocked: bool = not _hud_layout().try_place(
			"attack", mode.global_position.x / layer.get_viewport().get_visible_rect().size.x,
			mode.global_position.y / layer.get_viewport().get_visible_rect().size.y, 1.0, layer)
	await process_frame
	ok = ok and blocked
	await snapshot("no-overlap")

	step("after-save-restart")
	var saved_pos := attack.global_position
	await click(SAVE)
	_hud_layout().save_to_disk()
	await click(DONE)
	if change_scene_to_file(MAIN) != OK:
		done(false)
		return
	await wait_until(func() -> bool: return current_scene != null and current_scene.has_node(HOST_BUTTON), START_TIMEOUT_S)
	await click(HOST_BUTTON)
	await wait_until(func() -> bool: return hero() != null, START_TIMEOUT_S)
	layer = current_scene.get_node("CanvasLayer1") as CanvasLayer
	attack = current_scene.get_node(ATTACK) as TouchScreenButton
	map_btn = current_scene.get_node(MAP) as Control
	_hud_layout().load_from_disk()
	_hud_layout().apply(layer)
	await process_frame
	await process_frame
	ok = ok and _hud_layout().uses_custom() and attack.global_position.distance_to(saved_pos) < 8.0
	await snapshot("after-save-restart")

	step("reset-layout")
	await click(MENU_BUTTON)
	await click(CUSTOMIZE_BTN)
	await process_frame
	(current_scene.get_node(RESET) as Button).pressed.emit()
	_hud_layout().reset_to_defaults()
	(layer.get_node("HudToolRow") as HudToolRow)._layout()
	_hud_layout().edit_begin(layer)
	var editor := current_scene.get_node("CanvasLayer1/InGameMenu/HudLayoutEdit")
	if editor.has_method("relayout_bar"):
		await editor.relayout_bar()
	await snapshot("reset-layout")
	await click(DONE)
	for _i in 2:
		await process_frame
	var row := layer.get_node("HudToolRow") as HudToolRow
	row._layout()
	await process_frame
	ok = ok and not _hud_layout().uses_custom()
	ok = ok and attack.global_position.distance_to(default_pos) < 16.0
	ok = ok and map_btn.global_position.distance_to(default_map) < 16.0
	done(ok)
