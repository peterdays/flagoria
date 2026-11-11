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
	var list: ItemList = scene.get_node("CanvasLayer2/WorldsPanel/Margin/VBox/List")
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
	var list: ItemList = scene.get_node("CanvasLayer2/WorldsPanel/Margin/VBox/List")
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
	var list: ItemList = scene.get_node("CanvasLayer2/WorldsPanel/Margin/VBox/List")
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
