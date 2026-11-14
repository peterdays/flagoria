extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 7
## Save and reload the host castle only; proof that city wall tint matches (#525).
## bin/launch.sh drives/castle_save_tint.gd --display --seed 7

const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"


func run() -> void:
	step("start")
	if not await start_game():
		return
	for i in 24:
		await physics_frame
	step("before_save")
	await snapshot("before_save")

	step("reload")
	var saved := []
	root.get_node("MapGen").map_saved.connect(func(path: String) -> void: saved.append(path))
	if not await menu_save() or not await wait_until(func() -> bool: return not saved.is_empty(), 5.0):
		printerr("castle_save_tint: save failed")
		done(false)
		return
	await click(MAIN_MENU_BUTTON)
	await wait_until(func() -> bool: return current_scene != null and current_scene.has_node(HOST_BUTTON), 10.0)
	var err: String = root.get_node("MapGen").load_map_inputs(saved[0])
	if err != "" or not await start_game():
		printerr("castle_save_tint: load %s" % err)
		done(false)
		return
	for i in 24:
		await physics_frame
	step("after_reload")
	await snapshot("after_reload")
	done(true)