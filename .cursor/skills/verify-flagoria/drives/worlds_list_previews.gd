extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 507
## Three saves with different seeds; the Worlds list at the phone viewport.

const WORLDS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/WorldsButton"
const LIST := "CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List"
const NAMES := ["preview-a", "preview-b", "preview-c"]
const SEEDS := [50701, 50702, 50703]


func run() -> void:
	step("phone")
	if not await _seed_saves() or not await _resize(854, 480):
		done(false)
		return
	if change_scene_to_file(MAIN) != OK:
		done(false)
		return
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(WORLDS), START_TIMEOUT_S):
		done(false)
		return
	step("list")
	if not await _open_worlds():
		done(false)
		return
	var list: ItemList = current_scene.get_node(LIST)
	if list.item_count < NAMES.size():
		printerr("worlds_list_previews: %d rows, want %d" % [list.item_count, NAMES.size()])
		done(false)
		return
	for i in NAMES.size():
		if list.get_item_icon(i) == null:
			printerr("worlds_list_previews: row %d has no preview icon" % i)
			done(false)
			return
	await snapshot("worlds-list-phone")
	done(true)


func _seed_saves() -> bool:
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	for i in NAMES.size():
		var params := MapGenParams.make_defaults()
		params.ensure_seeds()
		var seed_value: int = SEEDS[i]
		params.altitude_seed = seed_value
		params.moisture_seed = seed_value + 1
		params.temperature_seed = seed_value + 2
		params.items_seed = seed_value + 3
		params.biome_seed = seed_value + 4
		params.island_radius = 0
		params.archipelago_spacing = 64 + i * 24
		params.archipelago_world_extent = 240 + i * 100
		params.archipelago_island_radius = 36
		params.archipelago_island_count = 0
		params.water_max_alt = 0.22
		var saved := MapSave.save_world(WorldSave.new(params), NAMES[i])
		if saved["error"] != "":
			printerr("worlds_list_previews: save %s" % saved["error"])
			return false
	await process_frame
	return true


func _open_worlds() -> bool:
	await click(WORLDS)
	return await wait_until(func() -> bool:
		return current_scene.has_node(LIST) and current_scene.get_node(LIST).is_visible_in_tree(), 5.0)


func _resize(width: int, height: int) -> bool:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(width, height))
	for _i in 6:
		await process_frame
	return true