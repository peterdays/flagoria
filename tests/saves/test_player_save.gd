extends "res://tests/helpers/test_helpers.gd"
## Player section of a world save (#197): position, health, wood, score,
## charted ground. An older save with no player section loads as a new player.


func _test_player_save_round_trip() -> int:
	## Walk-away state saved from the in-game menu comes back when that file
	## is hosted: same spot, health, wood, score, charted cell and paid chunk.
	## The file stays version 3.
	print("-- test_player_save_round_trip")
	var fail := 0
	var map_gen = root.get_node("MapGen")
	var before: MapGenParams = map_gen.params
	var scene = _player_scene()
	var body: Node2D = scene.get_node("World/1")
	body.set_physics_process(false)
	var spot := body.position + Vector2(160, -48)
	body.position = spot
	body.health.set_health_now(4)
	scene.get_node("Inventory").add(Inventory.WOOD, 3)
	scene.get_node("Points").award(1, 8, "test")
	scene.get_node("Discovery").restore_found({"3,-1": 1})
	var far := Vector2i(80, 40)
	var west := Vector2i(-10, 5)
	var chart_now: ExploredMap = scene.get_node("CanvasLayer1/MinimapPanel").explored
	chart_now.reveal_cells(far, 0)
	chart_now.reveal_cells(west, 0)
	var saved: Dictionary = scene.get_node("CanvasLayer1/InGameMenu").save_world()
	var doc := MapSave.read_document(saved["path"]) if saved["error"] == "" else {"error": saved["error"], "data": null}
	var section = doc["data"]["player"] if doc["data"] is Dictionary else null
	if saved["error"] != "" or doc.get("error", "") != "" or not section is Dictionary \
			or int(section.get("health", -1)) != 4 or int(section.get("wood", -1)) != 3 \
			or int(section.get("score", -1)) != 8 or section.get("discovered", {}).get("3,-1", 0) != 1 \
			or not section.get("charted", {}) is Dictionary or section["charted"].is_empty() \
			or doc["data"]["format_version"] != MapSave.FORMAT_VERSION:
		printerr("FAIL player_save_round_trip: save %s player %s" % [saved["error"], section])
		fail += 1
	elif not section["position"] is Array or not is_equal_approx(float(section["position"][0]), spot.x) \
			or not is_equal_approx(float(section["position"][1]), spot.y):
		printerr("FAIL player_save_round_trip: position %s want %s" % [section["position"], spot])
		fail += 1
	var path: String = saved["path"]
	scene.queue_free()
	await process_frame

	if path != "" and map_gen.load_map_inputs(path) != "":
		printerr("FAIL player_save_round_trip: load failed")
		fail += 1
	else:
		var again = _player_scene(false)
		again.world_params = map_gen.params.duplicate_params()
		again._apply_params_to_world(again.world_params)
		again._restore_loaded_world()
		again.add_player(1)
		var loaded: Node2D = again.get_node("World/1")
		var chart: ExploredMap = again.get_node("CanvasLayer1/MinimapPanel").explored
		if not is_equal_approx(loaded.position.x, spot.x) or not is_equal_approx(loaded.position.y, spot.y):
			printerr("FAIL player_save_round_trip: loaded at %s, want %s" % [loaded.position, spot])
			fail += 1
		if loaded.health.health != 4 or again.get_node("Inventory").count_of(Inventory.WOOD) != 3 \
				or again.get_node("Points").total_of(1) != 8 \
				or again.get_node("Discovery").discoverer_of(Vector2i(3, -1)) != 1 \
				or not chart.is_explored(far) or not chart.is_explored(west):
			printerr("FAIL player_save_round_trip: health %s wood %s score %s found %s chart %s"
					% [loaded.health.health, again.get_node("Inventory").count_of(Inventory.WOOD),
					again.get_node("Points").total_of(1),
					again.get_node("Discovery").discoverer_of(Vector2i(3, -1)), chart.is_explored(far)])
			fail += 1
		again.queue_free()
		await process_frame
	if path != "":
		DirAccess.remove_absolute(path)
	map_gen.params = before
	map_gen.clear_loaded_world()
	if fail == 0:
		print("PASS test_player_save_round_trip")
	return fail


func _test_player_save_legacy_defaults() -> int:
	## A missing or empty player section, and a section of bad values, loads
	## as the default player: full health, no wood, no score, nothing charted,
	## at the spawn. Version 1, 2 and 3 fixtures have no player progress.
	print("-- test_player_save_legacy_defaults")
	var fail := 0
	var map_gen = root.get_node("MapGen")
	var before: MapGenParams = map_gen.params
	var scene = _player_scene()
	var body: Node2D = scene.get_node("World/1")
	_dirt(scene, body)
	PlayerSave.apply(scene, body, {})
	if not _is_default(scene, body, "empty section"):
		fail += 1
	body.position = Vector2(10, 20)
	body.health.set_health_now(2)
	scene.get_node("Inventory").add(Inventory.WOOD, 5)
	scene.get_node("Points").restore_total(1, 3)
	PlayerSave.apply(scene, body, {
		"health": "nope", "position": [1], "wood": -3, "score": 1.5,
		"charted": {"nope": "!!"}, "discovered": {"z": "a"},
	})
	if body.health.health != body.health.max_health or body.position != Vector2(10, 20) \
			or scene.get_node("Inventory").count_of(Inventory.WOOD) != 0 \
			or scene.get_node("Points").total_of(1) != 0:
		printerr("FAIL player_save_legacy_defaults: bad section health %s at %s wood %s score %s"
				% [body.health.health, body.position, scene.get_node("Inventory").count_of(Inventory.WOOD),
				scene.get_node("Points").total_of(1)])
		fail += 1
	body.queue_free()
	await process_frame

	for fixture in ["res://tests/fixtures/world_save_v1.json", "res://tests/fixtures/world_save_v2.json", "res://tests/fixtures/world_save_v3.json"]:
		_dirt(scene, null)
		var err: String = map_gen.load_map_inputs(fixture)
		scene.world_params = map_gen.params.duplicate_params()
		scene._apply_params_to_world(scene.world_params)
		scene._restore_loaded_world()
		scene.add_player(1)
		var host: Node2D = scene.get_node("World/1")
		var spawn: Vector2 = scene._land_spawn_position(host)
		if err != "" or host.position.distance_to(spawn) > 1.0 or not _is_default(scene, host, fixture):
			printerr("FAIL player_save_legacy_defaults: %s error %s at %s spawn %s" % [fixture, err, host.position, spawn])
			fail += 1
		host.queue_free()
		await process_frame
	map_gen.params = before
	map_gen.clear_loaded_world()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_player_save_legacy_defaults")
	return fail


func _player_scene(with_body := true) -> Node:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene.world_params = params
	scene._apply_params_to_world(params)
	scene.get_node("Discovery").set_physics_process(false)
	scene.get_node("FlagsHeldPoints").set_physics_process(false)
	scene.get_node("CanvasLayer1/MinimapPanel").set_physics_process(false)
	if with_body:
		scene.add_player(1)
	return scene


func _dirt(scene: Node, body: Node) -> void:
	var inventory: Inventory = scene.get_node("Inventory")
	var have: int = inventory.count_of(Inventory.WOOD)
	if have < 9:
		inventory.add(Inventory.WOOD, 9 - have)
	scene.get_node("Points").restore_total(1, 4)
	scene.get_node("Discovery").restore_found({"1,1": 1})
	scene.get_node("CanvasLayer1/MinimapPanel").explored.reveal_cells(Vector2i(80, 40), 0)
	if body:
		body.health.set_health_now(2)


func _is_default(scene: Node, body: Node, label: String) -> bool:
	var chart: ExploredMap = scene.get_node("CanvasLayer1/MinimapPanel").explored
	var ok: bool = body.health.health == body.health.max_health \
			and scene.get_node("Inventory").count_of(Inventory.WOOD) == 0 \
			and scene.get_node("Points").total_of(1) == 0 \
			and scene.get_node("Discovery").discoverer_of(Vector2i(1, 1)) == 0 \
			and chart.explored_count() == 0
	if not ok:
		printerr("FAIL player_save_legacy_defaults: %s health %s wood %s score %s chart %s"
				% [label, body.health.health, scene.get_node("Inventory").count_of(Inventory.WOOD),
				scene.get_node("Points").total_of(1), chart.explored_count()])
	return ok
