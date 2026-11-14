extends "res://tests/helpers/test_helpers.gd"
## The main menu lists every world save, loads the one that is chosen, and
## a new match saves into its own file. An older save is listed as it is.


func _test_saved_world_round_trip() -> int:
	## Save, see it on the Worlds list, load it: the hosted world is that save.
	print("-- test_saved_world_round_trip")
	var fail := 0
	var map_gen = root.get_node("/root/MapGen")
	var saved_params: MapGenParams = map_gen.params.duplicate_params()
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	params.altitude_seed = 424242
	params.water_max_alt = 0.41
	var saved := MapSave.save_world(WorldSave.new(params), "round-trip")
	if saved["error"] != "":
		printerr("FAIL saved_world_round_trip: save %s" % saved["error"])
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.host_port = _free_udp_port()
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	menu._on_worlds_pressed()
	var list: ItemList = scene.get_node("CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List")
	var row := _row_named(list, "round-trip")
	if row < 0 or not list.get_item_text(row).contains("round-trip"):
		printerr("FAIL saved_world_round_trip: list %s" % _list_text(list))
		fail += 1
	else:
		list.select(row)
		menu._on_load_world_pressed()
		await process_frame
		await process_frame
		if scene.save_name != "round-trip" or scene.world_params == null \
				or scene.world_params.altitude_seed != 424242 \
				or not is_equal_approx(scene.world_params.water_max_alt, 0.41):
			printerr("FAIL saved_world_round_trip: hosted %s seed %s water %s" % [
					scene.save_name,
					scene.world_params.altitude_seed if scene.world_params else 0,
					scene.world_params.water_max_alt if scene.world_params else 0])
			fail += 1
	_release_scene(scene)
	map_gen.params = saved_params
	map_gen.clear_loaded_world()
	map_gen.save_to_disk()
	DirAccess.remove_absolute(saved["path"])
	await process_frame
	if fail == 0:
		print("PASS test_saved_world_round_trip")
	return fail


func _test_two_worlds_stay_separate() -> int:
	## Saving the active world replaces its file and leaves the other one.
	print("-- test_two_worlds_stay_separate")
	var fail := 0
	var map_gen = root.get_node("/root/MapGen")
	var saved_params: MapGenParams = map_gen.params.duplicate_params()
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer1/InGameMenu")
	scene.get_node("CanvasLayer1").show()
	var first := _params_with_seed(111111)
	var second := _params_with_seed(222222)
	scene.world_params = first
	scene.save_name = "world-a"
	if menu.save_world()["error"] != "":
		printerr("FAIL two_worlds: first save failed")
		fail += 1
	scene.world_params = second
	scene.save_name = "world-b"
	if menu.save_world()["error"] != "":
		printerr("FAIL two_worlds: second save failed")
		fail += 1
	scene.world_params = _params_with_seed(333333)
	scene.save_name = "world-a"
	var again: Dictionary = menu.save_world()
	if again["error"] != "" or again["path"] != MapSave.path_for("world-a"):
		printerr("FAIL two_worlds: rewrite %s" % again)
		fail += 1
	var loaded_a := MapSave.load_world(MapSave.path_for("world-a"))
	var loaded_b := MapSave.load_world(MapSave.path_for("world-b"))
	if loaded_a["world"].params.altitude_seed != 333333 or loaded_b["world"].params.altitude_seed != 222222:
		printerr("FAIL two_worlds: seeds %s and %s" % [
				loaded_a["world"].params.altitude_seed, loaded_b["world"].params.altitude_seed])
		fail += 1
	var main_menu = scene.get_node("CanvasLayer2/MainMenu")
	main_menu._on_worlds_pressed()
	var list: ItemList = scene.get_node("CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List")
	if _row_named(list, "world-a") < 0 or _row_named(list, "world-b") < 0:
		printerr("FAIL two_worlds: list %s" % _list_text(list))
		fail += 1
	else:
		list.select(_row_named(list, "world-b"))
		main_menu._on_delete_world_pressed()
		main_menu._on_delete_yes_pressed()
		if _row_named(list, "world-b") >= 0 or FileAccess.file_exists(MapSave.path_for("world-b")) \
				or _row_named(list, "world-a") < 0:
			printerr("FAIL two_worlds: delete left %s" % _list_text(list))
			fail += 1
	DirAccess.remove_absolute(MapSave.path_for("world-a"))
	DirAccess.remove_absolute(MapSave.path_for("world-b"))
	map_gen.params = saved_params
	map_gen.clear_loaded_world()
	map_gen.save_to_disk()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_two_worlds_stay_separate")
	return fail


func _test_saved_world_rename_panel() -> int:
	## Rename from the Worlds panel refreshes the list, keeps selection, and
	## refuses a duplicate name; cancel leaves the file as it was.
	print("-- test_saved_world_rename_panel")
	var fail := 0
	var map_gen = root.get_node("/root/MapGen")
	var saved_params: MapGenParams = map_gen.params.duplicate_params()
	for name in ["rename-a", "rename-b"]:
		var params := _params_with_seed(100 if name == "rename-a" else 200)
		if MapSave.save_world(WorldSave.new(params), name)["error"] != "":
			printerr("FAIL saved_world_rename_panel: could not create %s" % name)
			return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	menu._on_worlds_pressed()
	var list: ItemList = scene.get_node("CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List")
	var panel: PanelContainer = scene.get_node("CanvasLayer2/WorldsPanel")
	var status: Label = panel.get_node("Margin/VBox/Status")

	list.select(_row_named(list, "rename-a"))
	menu._on_rename_world_pressed()
	var field: LineEdit = panel.get_node("Margin/VBox/Rename/Name")
	field.text = "rename-ok"
	menu._on_rename_yes_pressed()
	await process_frame
	var ok_row := _row_named(list, "rename-ok")
	if ok_row < 0 or FileAccess.file_exists(MapSave.path_for("rename-a")) \
			or not list.get_selected_items().has(ok_row):
		printerr("FAIL saved_world_rename_panel: success list=%s selected=%s" % [
				_list_text(list), list.get_selected_items()])
		fail += 1

	list.select(ok_row)
	menu._on_rename_world_pressed()
	field.text = "rename-b"
	menu._on_rename_yes_pressed()
	await process_frame
	if status.text == "" or not "already exists" in status.text \
			or not FileAccess.file_exists(MapSave.path_for("rename-ok")) \
			or _row_named(list, "rename-b") < 0:
		printerr("FAIL saved_world_rename_panel: duplicate status=%s list=%s" % [status.text, _list_text(list)])
		fail += 1
	menu._on_rename_no_pressed()

	list.select(ok_row)
	menu._on_rename_world_pressed()
	field.text = "rename-cancelled"
	menu._on_rename_no_pressed()
	await process_frame
	if FileAccess.file_exists(MapSave.path_for("rename-cancelled")) \
			or _row_named(list, "rename-cancelled") >= 0:
		printerr("FAIL saved_world_rename_panel: cancel renamed anyway")
		fail += 1

	for name in ["rename-ok", "rename-b"]:
		DirAccess.remove_absolute(MapSave.path_for(name))
	map_gen.params = saved_params
	map_gen.clear_loaded_world()
	map_gen.save_to_disk()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_saved_world_rename_panel")
	return fail


func _test_legacy_save_stays_in_the_list() -> int:
	## A save written before this menu (version 1) is listed and still loads.
	## Opening the list does not rewrite the file.
	print("-- test_legacy_save_stays_in_the_list")
	var fail := 0
	var map_gen = root.get_node("/root/MapGen")
	var saved_params: MapGenParams = map_gen.params.duplicate_params()
	var source := FileAccess.get_file_as_bytes("res://tests/fixtures/world_save_v1.json")
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	var path := MapSave.path_for("legacy-v1")
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_buffer(source)
	out.close()
	var before := FileAccess.get_file_as_bytes(path)
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.host_port = _free_udp_port()
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	menu._on_worlds_pressed()
	var list: ItemList = scene.get_node("CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List")
	var row := _row_named(list, "legacy-v1")
	if row < 0:
		printerr("FAIL legacy_save: list %s" % _list_text(list))
		fail += 1
	elif FileAccess.get_file_as_bytes(path) != before:
		printerr("FAIL legacy_save: the list rewrote the file")
		fail += 1
	else:
		list.select(row)
		menu._on_load_world_pressed()
		await process_frame
		await process_frame
		if scene.world_params == null or scene.world_params.altitude_seed != 4242 \
				or FileAccess.get_file_as_bytes(path) != before:
			printerr("FAIL legacy_save: seed %s file changed %s" % [
					scene.world_params.altitude_seed if scene.world_params else 0,
					FileAccess.get_file_as_bytes(path) != before])
			fail += 1
	_release_scene(scene)
	map_gen.params = saved_params
	map_gen.clear_loaded_world()
	map_gen.save_to_disk()
	DirAccess.remove_absolute(path)
	await process_frame
	if fail == 0:
		print("PASS test_legacy_save_stays_in_the_list")
	return fail


func _release_scene(scene) -> void:
	## Hosting replaces the tree's multiplayer peer. Put the offline peer
	## back so the next test is not left with a closed server.
	if scene.enet_peer != null:
		scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()


func _params_with_seed(seed_value: int) -> MapGenParams:
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	params.altitude_seed = seed_value
	return params


func _row_named(list: ItemList, save_name: String) -> int:
	for i in list.item_count:
		if str(list.get_item_metadata(i)) == save_name:
			return i
	return -1


func _list_text(list: ItemList) -> PackedStringArray:
	var out := PackedStringArray()
	for i in list.item_count:
		out.append(list.get_item_text(i))
	return out


func _test_world_save_preview() -> int:
	## A preview is built from generation inputs, is stable for the same seed,
	## and a save with no cached preview still lists and loads.
	print("-- test_world_save_preview")
	var fail := 0
	var map_gen = root.get_node("/root/MapGen")
	var saved_params: MapGenParams = map_gen.params.duplicate_params()
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world: TileMap = scene.get_node("World/worldMap")
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	params.altitude_seed = 507001
	params.archipelago_spacing = 80
	params.archipelago_world_extent = 320
	params.archipelago_island_radius = 36
	params.water_max_alt = 0.24
	var first := WorldSavePreview.build_image(world, params)
	var second := WorldSavePreview.build_image(world, params)
	if first.get_data() != second.get_data():
		printerr("FAIL world_save_preview: same params gave different images")
		fail += 1
	var land_frac := WorldSavePreview.land_pixel_fraction(first)
	if land_frac < WorldSavePreview.MIN_LAND_FRACTION:
		printerr("FAIL world_save_preview: land fraction %.3f below minimum" % land_frac)
		fail += 1
	var flat := Image.create(WorldSavePreview.ICON_SIZE.x, WorldSavePreview.ICON_SIZE.y, false, Image.FORMAT_RGBA8)
	flat.fill(MinimapPanel.SKY_DEEP)
	if WorldSavePreview.land_pixel_fraction(flat) >= WorldSavePreview.MIN_LAND_FRACTION:
		printerr("FAIL world_save_preview: land fraction check accepted an all-water image")
		fail += 1
	var saved := MapSave.save_world(WorldSave.new(params), "preview-fixture")
	if saved["error"] != "":
		printerr("FAIL world_save_preview: save %s" % saved["error"])
		_release_scene(scene)
		return fail + 1
	WorldSavePreview.remove("preview-fixture")
	var source := FileAccess.get_file_as_bytes("res://tests/fixtures/world_save_v1.json")
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	var legacy_path := MapSave.path_for("preview-legacy")
	FileAccess.open(legacy_path, FileAccess.WRITE).store_buffer(source)
	scene.host_port = _free_udp_port()
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	menu._on_worlds_pressed()
	var list: ItemList = scene.get_node("CanvasLayer2/WorldsPanel/Margin/VBox/Scroll/List")
	var row := _row_named(list, "preview-legacy")
	if row < 0:
		printerr("FAIL world_save_preview: legacy missing from %s" % _list_text(list))
		fail += 1
	elif list.get_item_icon(row) == null:
		printerr("FAIL world_save_preview: legacy row has no icon")
		fail += 1
	else:
		list.select(row)
		menu._on_load_world_pressed()
		await process_frame
		await process_frame
		if scene.world_params == null or scene.world_params.altitude_seed != 4242:
			printerr("FAIL world_save_preview: legacy load seed %s" % scene.world_params)
			fail += 1
	DirAccess.remove_absolute(saved["path"])
	DirAccess.remove_absolute(legacy_path)
	WorldSavePreview.remove("preview-fixture")
	WorldSavePreview.remove("preview-legacy")
	_release_scene(scene)
	map_gen.params = saved_params
	map_gen.clear_loaded_world()
	map_gen.save_to_disk()
	await process_frame
	if fail == 0:
		print("PASS test_world_save_preview")
	return fail
