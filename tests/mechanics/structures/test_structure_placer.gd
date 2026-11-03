extends "res://tests/helpers/test_helpers.gd"
## Placing a structure file on the world map (StructurePlacer, #270).


func _guard_post() -> Structure:
	return Structure.parse(FileAccess.get_file_as_string("res://structures/guard_post.txt"))["structure"]


func _footprint(s: Structure, anchor_cell: Vector2i) -> Dictionary:
	## Map cell -> [ground legend char, object legend char] for every grid
	## cell with something on either layer.
	var out := {}
	for y in s.size.y:
		for x in s.size.x:
			var g: String = s.layers["ground"][y][x]
			var o: String = s.layers["object"][y][x]
			if g != Structure.EMPTY or o != Structure.EMPTY:
				out[anchor_cell + Vector2i(x, y) - s.anchor] = [g, o]
	return out


func _find_anchor(world, s: Structure, want: Callable) -> Variant:
	## The first drawn anchor cell near the origin whose footprint passes
	## `want` (called with the footprint's predicted cells), or null.
	for cell: Vector2i in world.get_used_cells(0):
		var cells: Array = _footprint(s, cell).keys()
		if cells.all(func(c): return world.get_cell_source_id(0, c) != -1) and want.call(cells):
			return cell
	return null


func _test_structure_place() -> int:
	## guard_post placed on clear land: sand ground, solved wall and gate
	## pieces with collision, the host's blue flag, nothing left of the
	## plants or decor under it, and predict_cell agrees. It is listed by id
	## with owner and anchor, stays when the chunk is drawn again, and a
	## second guard post on top of it is refused. A new map clears it.
	print("-- test_structure_place")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var s := _guard_post()
	var anchor: Variant = null
	var seed_value := 0
	for sv in [11, 42, 99]:
		world.apply_map_params(_spawn_params(sv, 0.0))
		world.generate_chunk(Vector2(0, 0))
		anchor = _find_anchor(world, s, func(cells): return cells.all(world.predicted_clear))
		if anchor != null:
			seed_value = sv
			break
	if anchor == null:
		printerr("FAIL structure_place: no clear 5x4 spot near the origin on seeds 11, 42, 99")
		scene.queue_free()
		return 1
	var generated := {}
	for c in _footprint(s, anchor):
		generated[c] = world.get_cell_atlas_coords(0, c)
	var reasons: Array = world.can_place_structure(s, anchor)
	var id: int = world.place_structure(s, anchor, 1)
	if not reasons.is_empty() or id <= 0:
		printerr("FAIL structure_place: clear land at %s refused: %s (id %s)" % [anchor, reasons, id])
		fail += 1
	var walls := {}
	for c in _footprint(s, anchor):
		var o: String = _footprint(s, anchor)[c][1]
		if o != Structure.EMPTY and s.legend[o]["tile"].begins_with("WALL_"):
			walls[c] = {"gate": s.legend[o]["tile"].contains("GATE")}
	var solved: Dictionary = WallSolver.solve(walls)
	var check := func(label: String) -> int:
		var bad := 0
		var foot := _footprint(s, anchor)
		for c: Vector2i in foot:
			var g: String = foot[c][0]
			var o: String = foot[c][1]
			var want_ground: Vector2i = generated[c] if g == Structure.EMPTY else TileCatalog.TILES[s.legend[g]["tile"]]["atlas"]
			var want_object: Vector2i = world.NO_PLANT
			if o != Structure.EMPTY:
				var tile: String = s.legend[o]["tile"]
				if "auto" in s.legend[o]["attributes"]:
					tile = solved[c]
				want_object = TileCatalog.TILES[tile]["atlas"]
			var drawn_object: Vector2i = world.get_cell_atlas_coords(1, c) if world.get_cell_source_id(1, c) != -1 else world.NO_PLANT
			if world.get_cell_atlas_coords(0, c) != want_ground or drawn_object != want_object \
					or world.get_cell_source_id(world.GROUND_DECOR_LAYER, c) != -1:
				printerr("FAIL structure_place %s: %s drawn %s/%s/%s, want %s/%s/none" % [label, c,
					world.get_cell_atlas_coords(0, c), drawn_object,
					world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, c), want_ground, want_object])
				bad += 1
			if world.predict_cell(c) != [want_ground, want_object]:
				printerr("FAIL structure_place %s: %s predicted %s" % [label, c, world.predict_cell(c)])
				bad += 1
			var td = world.get_cell_tile_data(1, c)
			var solid: bool = td != null and td.get_collision_polygons_count(0) > 0
			if solid != walls.has(c):
				printerr("FAIL structure_place %s: %s collision %s, want %s" % [label, c, solid, walls.has(c)])
				bad += 1
		return bad
	fail += check.call("placed")
	var flag_cell: Vector2i = anchor + Vector2i(2, 2) - s.anchor
	if world.get_cell_atlas_coords(1, flag_cell) != TileCatalog.PROP_FLAG_BLUE:
		printerr("FAIL structure_place: the host's flag at %s is not blue" % flag_cell)
		fail += 1
	var listed: Dictionary = world.placed_structures()
	if listed != {id: {"name": "guard_post", "owner": 1, "anchor": anchor}}:
		printerr("FAIL structure_place: placements listed as %s" % listed)
		fail += 1
	world.clear()
	world.generate_chunk(Vector2(0, 0))
	fail += check.call("redrawn")
	var again: Array = world.can_place_structure(s, anchor)
	if not "overlaps another structure" in again or world.place_structure(s, anchor, 1) != -1 \
			or world.placed_structures().size() != 1:
		printerr("FAIL structure_place: a guard post on top of the first got %s" % again)
		fail += 1
	world.apply_map_params(_spawn_params(seed_value, 0.0))
	world.generate_chunk(Vector2(0, 0))
	if not world.placed_structures().is_empty() or world.get_cell_atlas_coords(1, flag_cell) == TileCatalog.PROP_FLAG_BLUE:
		printerr("FAIL structure_place: a new map kept the guard post")
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_structure_place (seed %s, anchor %s)" % [seed_value, anchor])
	return fail


func _test_structure_place_refused() -> int:
	## can_place gives a reason for a footprint over water, a tree, a bush,
	## a player, outside the world bound, and while multiplayer is on (a
	## connecting client); place then writes nothing and lists nothing.
	print("-- test_structure_place_refused")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var s := _guard_post()
	var top := func(c: Vector2i) -> Vector2i:
		return world.predict_cell(c)[1]
	var wet := func(cells): return cells.any(func(c): return world.predict_cell(c)[0] == TileCatalog.WATER)
	var cases := {
		"water": wet,
		"tree": func(cells): return not wet.call(cells) and cells.any(func(c): return top.call(c) in [TileCatalog.TREE, TileCatalog.TREE_BUSHY, TileCatalog.PINE]),
		"bush": func(cells): return not wet.call(cells) and cells.any(func(c): return top.call(c) == TileCatalog.BUSH),
	}
	var refuse := func(label: String, anchor: Vector2i, reason: String) -> int:
		var before := {}
		for c in _footprint(s, anchor):
			before[c] = [world.get_cell_atlas_coords(0, c), world.get_cell_atlas_coords(1, c)]
		var got: Array = world.can_place_structure(s, anchor)
		var bad := 0
		if not reason in got or world.place_structure(s, anchor, 1) != -1 or not world.placed_structures().is_empty():
			printerr("FAIL structure_place_refused %s at %s: reasons %s, want %s and no placement" % [label, anchor, got, reason])
			bad += 1
		for c in before:
			if [world.get_cell_atlas_coords(0, c), world.get_cell_atlas_coords(1, c)] != before[c]:
				printerr("FAIL structure_place_refused %s: %s changed" % [label, c])
				bad += 1
				break
		return bad
	var found := {}
	for sv in [11, 42, 99]:
		world.apply_map_params(_spawn_params(sv, 0.6))
		world.generate_chunk(Vector2(0, 0))
		for reason in cases:
			if found.has(reason):
				continue
			var a: Variant = _find_anchor(world, s, cases[reason])
			if a != null:
				found[reason] = true
				fail += refuse.call("%s (seed %s)" % [reason, sv], a, reason)
		var clear: Variant = _find_anchor(world, s, func(cells): return cells.all(world.predicted_clear))
		if clear != null and not found.has("player"):
			found["player"] = true
			var player = load("res://Player/character_body_2d.tscn").instantiate()
			player.name = str(scene.multiplayer.get_unique_id())
			scene.get_node("World").add_child(player)
			player.global_position = world.to_global(world.map_to_local(clear))
			fail += refuse.call("player", clear, "overlaps a player")
			player.queue_free()
			await process_frame
			# A connecting client: multiplayer is on, so placing stays off (#278).
			var api := SceneMultiplayer.new()
			set_multiplayer(api, world.get_path())
			var peer := ENetMultiplayerPeer.new()
			peer.create_client("127.0.0.1", _free_udp_port())
			api.multiplayer_peer = peer
			fail += refuse.call("multiplayer", clear, "multiplayer on")
			peer.close()
			set_multiplayer(null, world.get_path())
			found["multiplayer on"] = true
	world.archipelago_spacing = 64
	world.archipelago_world_extent = 40
	fail += refuse.call("out of map", Vector2i(200, 0), "out of map")
	found["out of map"] = true
	for reason in ["water", "tree", "bush", "player", "multiplayer on"]:
		if not found.has(reason):
			printerr("FAIL structure_place_refused: no spot for the %s case on seeds 11, 42, 99" % reason)
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_structure_place_refused")
	return fail
