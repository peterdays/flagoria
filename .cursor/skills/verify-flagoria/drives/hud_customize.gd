extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## Customize HUD from the in-game menu: default layout, edit mode, move attack,
## save, reload, overlap rejection, reset.
## bin/launch.sh drives/hud_customize.gd --display --seed 49

const CUSTOMIZE_BTN := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/CustomizeHud"
const ATTACK := "CanvasLayer1/TouchScreenButton"
const DONE := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar/Margin/HBox/Done"
const SAVE := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar/Margin/HBox/Save"
const RESET := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar/Margin/HBox/Reset"
const SIZE_SLIDER := "CanvasLayer1/InGameMenu/HudLayoutEdit/TopBar/Margin/HBox/SizeSlider"


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


func run() -> void:
	if not await start_game():
		return
	var layer := current_scene.get_node("CanvasLayer1") as CanvasLayer
	var attack := current_scene.get_node(ATTACK) as TouchScreenButton
	var ok := attack != null and attack.texture_normal != null
	step("default-layout")
	await snapshot("default-layout")
	var default_pos := attack.global_position

	step("edit-mode")
	await click(MENU_BUTTON)
	await click(CUSTOMIZE_BTN)
	ok = ok and current_scene.get_node("CanvasLayer1/InGameMenu/HudLayoutEdit").visible
	var attack_at := to_window(attack, attack.texture_normal.get_size() * attack.scale * 0.5)
	await _tap(attack_at)
	await process_frame
	ok = ok and (current_scene.get_node(SIZE_SLIDER) as HSlider).editable
	await snapshot("edit-mode")

	step("moved-control")
	_hud_layout().try_place("attack", 0.62, 0.58, 1.35, layer)
	await process_frame
	await process_frame
	ok = ok and attack.global_position.distance_to(default_pos) > 12.0
	await snapshot("moved-control")

	step("no-overlap")
	var mode: Control = current_scene.get_node("CanvasLayer1/ModeButton")
	attack_at = to_window(attack, attack.texture_normal.get_size() * attack.scale * 0.5)
	await _tap(attack_at)
	var blocked: bool = not _hud_layout().try_place(
			"attack", mode.global_position.x / layer.get_viewport().get_visible_rect().size.x,
			mode.global_position.y / layer.get_viewport().get_visible_rect().size.y, 1.0, layer)
	await process_frame
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
	_hud_layout().load_from_disk()
	_hud_layout().apply(layer)
	await process_frame
	await process_frame
	ok = ok and _hud_layout().uses_custom() and attack.global_position.distance_to(saved_pos) < 8.0
	await snapshot("after-save-restart")

	step("reset-layout")
	await click(MENU_BUTTON)
	await click(CUSTOMIZE_BTN)
	await click(RESET)
	for _i in 4:
		await create_timer(0.0, true).timeout
	ok = ok and blocked and not _hud_layout().uses_custom()
	await click(DONE)
	for _i in 2:
		await process_frame
	var row := layer.get_node("HudToolRow") as HudToolRow
	row._layout()
	await process_frame
	ok = ok and attack.global_position.distance_to(default_pos) < 16.0
	await snapshot("reset-layout")
	done(ok)
