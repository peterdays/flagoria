extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --display
## Opens Worlds, shows the rename field, and renames one seeded save.

const WORLDS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/WorldsButton"
const LIST := "CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List"
const RENAME := "CanvasLayer2/WorldsPanel/Margin/VBox/Buttons/Rename"
const RENAME_FIELD := "CanvasLayer2/WorldsPanel/Margin/VBox/Rename/Name"
const RENAME_CONFIRM := "CanvasLayer2/WorldsPanel/Margin/VBox/Rename/Confirm"


func run() -> void:
	if not await _seed_save():
		done(false)
		return
	if change_scene_to_file(MAIN) != OK:
		done(false)
		return
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(WORLDS), START_TIMEOUT_S):
		done(false)
		return
	step("rename-field")
	if not await _open_rename():
		done(false)
		return
	await snapshot("rename-field")
	step("rename-done")
	var field: LineEdit = current_scene.get_node(RENAME_FIELD)
	field.text = "drive-renamed"
	await click(RENAME_CONFIRM)
	await process_frame
	var list: ItemList = current_scene.get_node(LIST)
	if _row_named(list, "drive-renamed") < 0:
		printerr("worlds_rename: list missing drive-renamed")
		done(false)
		return
	await snapshot("rename-done")
	done(true)


func _seed_save() -> bool:
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	for name in ["drive-renamed", "drive-rename-src"]:
		var path := MapSave.path_for(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	params.altitude_seed = 484_484
	var saved := MapSave.save_world(WorldSave.new(params), "drive-rename-src")
	if saved["error"] != "":
		printerr("worlds_rename: save %s" % saved["error"])
		return false
	await process_frame
	return true


func _open_rename() -> bool:
	await click(WORLDS)
	var list: ItemList = current_scene.get_node(LIST)
	if not await wait_until(func() -> bool: return list.is_visible_in_tree(), 5.0):
		printerr("worlds_rename: worlds list not visible")
		return false
	var row := _row_named(list, "drive-rename-src")
	if row < 0:
		printerr("worlds_rename: source save missing")
		return false
	if not await _click_item(list, row):
		return false
	await click(RENAME)
	return await wait_until(func() -> bool:
		return current_scene.get_node(RENAME_FIELD).is_visible_in_tree(), 5.0)


func _row_named(list: ItemList, save_name: String) -> int:
	for i in list.item_count:
		if str(list.get_item_metadata(i)) == save_name:
			return i
	return -1


func _click_item(list: ItemList, index: int) -> bool:
	var rect := list.get_item_rect(index)
	var at := to_window(list, rect.position + rect.size * 0.5)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await process_frame
	return list.get_selected_items().has(index)
