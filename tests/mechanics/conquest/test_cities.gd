extends "res://tests/helpers/test_helpers.gd"
## Closed wall loops around a flag tower make a city (Cities, #277).


func _scene(label: String) -> Dictionary:
	## {scene, world, cities}, or {} after FAIL. Caller regenerates seeds.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var cities: Cities = scene.get_node_or_null("World/Cities")
	if cities == null:
		printerr("FAIL %s: World/Cities missing" % label)
		scene.queue_free()
		return {}
	return {"scene": scene, "world": scene.get_node("World/worldMap"), "cities": cities}


func _regen(t: Dictionary, seed_value: int) -> void:
	t["world"].apply_map_params(_spawn_params(seed_value, 0.0))
	t["world"].generate_chunk(Vector2(0, 0))


func _clear_rect(world, origin: Vector2i, size: Vector2i) -> bool:
	for y in size.y:
		for x in size.x:
			var c := origin + Vector2i(x, y)
			if world.get_cell_source_id(0, c) == -1 or not world.predicted_clear(c):
				return false
	return true


func _find_clear(world, size: Vector2i) -> Variant:
	for cell: Vector2i in world.get_used_cells(0):
		if _clear_rect(world, cell, size):
			return cell
	return null


func _structure_spot(world, structure: Structure) -> Variant:
	for cell: Vector2i in world.get_used_cells(0):
		var cells: Array = StructurePlacer.footprint(structure, cell).keys()
		if cells.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
			return cell
	return null


func _perimeter(lo: Vector2i, hi: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(lo.x, hi.x + 1):
		out.append(Vector2i(x, lo.y))
		out.append(Vector2i(x, hi.y))
	for y in range(lo.y + 1, hi.y):
		out.append(Vector2i(lo.x, y))
		out.append(Vector2i(hi.x, y))
	return out


func _place_tower(world, anchor: Vector2i, owner: int = 1) -> int:
	return world.place_structure(StructurePlacer.load_named("tower_wood"), anchor, owner)


func _setup_ring_city(label: String) -> Dictionary:
	## Scene with a closed free-form ring around a wooden tower, or {}.
	var t := _scene(label)
	if t.is_empty():
		return {}
	var world = t["world"]
	for sv in [11, 42, 99]:
		_regen(t, sv)
		var origin = _find_clear(world, Vector2i(5, 5))
		if origin == null:
			continue
		var o: Vector2i = origin
		var id := _place_tower(world, o + Vector2i(2, 3), 1)
		if id <= 0:
			continue
		var ring := _perimeter(o, o + Vector2i(4, 4))
		# Ring cells must stay clear of the tower footprint.
		var blocked := false
		for cell in ring:
			if world._structures.has_cell(cell) or not world.predicted_clear(cell) \
					or world.get_cell_source_id(0, cell) == -1:
				blocked = true
				break
		if blocked:
			continue
		if not world.place_wall_cells(ring):
			continue
		t["id"] = id
		t["origin"] = o
		t["ring"] = ring
		return t
	printerr("FAIL %s: no 5x5 clear ring spot on seeds 11, 42, 99" % label)
	t["scene"].queue_free()
	return {}


func _setup_guard_post(label: String) -> Dictionary:
	var t := _scene(label)
	if t.is_empty():
		return {}
	var world = t["world"]
	var gp: Structure = StructurePlacer.load_named("guard_post")
	for sv in [11, 42, 99]:
		_regen(t, sv)
		var at = _structure_spot(world, gp)
		if at == null:
			continue
		var id: int = world.place_structure(gp, at, 1)
		if id <= 0:
			continue
		t["id"] = id
		return t
	printerr("FAIL %s: no clear guard_post spot on seeds 11, 42, 99" % label)
	t["scene"].queue_free()
	return {}


func _test_cities_closed_loop_makes_city() -> int:
	## A free-form wall ring around a wooden tower makes a city owned by the
	## tower's owner, with the ring in wall cells and the flag in the interior.
	## Time cost: ~0.4 s alone with --only=.
	print("-- test_cities_closed_loop_makes_city")
	var t := _setup_ring_city("cities_closed_loop_makes_city")
	if t.is_empty():
		return 1
	var fail := 0
	var cities: Cities = t["cities"]
	var id: int = t["id"]
	cities.rebuild()
	if not cities.cities.has(id):
		printerr("FAIL cities_closed_loop_makes_city: no city for tower %s; cities=%s" % [id, cities.cities.keys()])
		fail += 1
	else:
		var rec: Dictionary = cities.cities[id]
		var flag: Vector2i = t["world"]._structures.towers()[id][0]
		if not rec["interior"].has(flag):
			printerr("FAIL cities_closed_loop_makes_city: flag %s not interior" % [flag])
			fail += 1
		if cities.owner_of(id) != 1:
			printerr("FAIL cities_closed_loop_makes_city: owner %s" % cities.owner_of(id))
			fail += 1
		# Only ring cells that 4-touch the interior are city walls (corners of
		# the outer ring may not). Every city wall must be on the ring.
		var ring_set := {}
		for cell in t["ring"]:
			ring_set[cell] = true
		if rec["walls"].is_empty():
			printerr("FAIL cities_closed_loop_makes_city: empty walls")
			fail += 1
		for cell: Vector2i in rec["walls"]:
			if not ring_set.has(cell):
				printerr("FAIL cities_closed_loop_makes_city: wall %s not on ring" % [cell])
				fail += 1
				break
		if rec["walls"].size() < 8:
			printerr("FAIL cities_closed_loop_makes_city: too few walls %d" % rec["walls"].size())
			fail += 1
	t["scene"].queue_free()
	return fail


func _test_cities_open_loop_does_not() -> int:
	## An incomplete wall ring around a tower does not make a city. A placed
	## guard_post (already enclosed) does. Time cost: ~0.4 s alone.
	print("-- test_cities_open_loop_does_not")
	var t := _scene("cities_open_loop_does_not")
	if t.is_empty():
		return 1
	var fail := 0
	var world = t["world"]
	var cities: Cities = t["cities"]
	var found_open := false
	for sv in [11, 42, 99]:
		_regen(t, sv)
		var origin = _find_clear(world, Vector2i(5, 5))
		if origin == null:
			continue
		var o: Vector2i = origin
		var id := _place_tower(world, o + Vector2i(2, 3), 1)
		if id <= 0:
			continue
		var ring := _perimeter(o, o + Vector2i(4, 4))
		var gap := o + Vector2i(2, 0)
		var open_ring: Array[Vector2i] = []
		for cell in ring:
			if cell != gap and world.predicted_clear(cell) and world.get_cell_source_id(0, cell) != -1 \
					and not world._structures.has_cell(cell):
				open_ring.append(cell)
		if open_ring.size() < ring.size() - 1:
			continue
		if not world.place_wall_cells(open_ring):
			continue
		cities.rebuild()
		if cities.cities.has(id):
			printerr("FAIL cities_open_loop_does_not: open ring made a city")
			fail += 1
		found_open = true
		break
	if not found_open:
		printerr("FAIL cities_open_loop_does_not: no open-ring setup on seeds 11, 42, 99")
		fail += 1
	var gp := _setup_guard_post("cities_open_loop_does_not_gp")
	if gp.is_empty():
		fail += 1
	else:
		gp["cities"].rebuild()
		if not gp["cities"].cities.has(gp["id"]):
			printerr("FAIL cities_open_loop_does_not: enclosed guard_post is not a city")
			fail += 1
		gp["scene"].queue_free()
	t["scene"].queue_free()
	return fail


func _test_cities_capture_changes_owner() -> int:
	## Capturing the city's flag tower (StructurePlacer.set_owner) makes
	## owner_of follow the new owner. Time cost: ~0.4 s alone.
	print("-- test_cities_capture_changes_owner")
	var t := _setup_guard_post("cities_capture_changes_owner")
	if t.is_empty():
		return 1
	var fail := 0
	var cities: Cities = t["cities"]
	var id: int = t["id"]
	cities.rebuild()
	if not cities.cities.has(id) or cities.owner_of(id) != 1:
		printerr("FAIL cities_capture_changes_owner: setup city owner %s has=%s"
				% [cities.owner_of(id), cities.cities.has(id)])
		fail += 1
	t["world"]._structures.set_owner(id, 2)
	if cities.owner_of(id) != 2:
		printerr("FAIL cities_capture_changes_owner: after set_owner owner %s" % cities.owner_of(id))
		fail += 1
	t["scene"].queue_free()
	return fail


func _test_cities_dissolve_when_loop_breaks() -> int:
	## Erasing one free-form wall from a closed ring dissolves that city.
	## Time cost: ~0.4 s alone.
	print("-- test_cities_dissolve_when_loop_breaks")
	var t := _setup_ring_city("cities_dissolve_when_loop_breaks")
	if t.is_empty():
		return 1
	var fail := 0
	var cities: Cities = t["cities"]
	var id: int = t["id"]
	cities.rebuild()
	if not cities.cities.has(id):
		printerr("FAIL cities_dissolve_when_loop_breaks: no city before break")
		fail += 1
	var gap: Array[Vector2i] = [t["origin"] + Vector2i(2, 0)]
	if not t["world"]._walls.erase_cells(gap):
		printerr("FAIL cities_dissolve_when_loop_breaks: erase failed")
		fail += 1
	cities.rebuild()
	if cities.cities.has(id):
		printerr("FAIL cities_dissolve_when_loop_breaks: city remained after gap")
		fail += 1
	t["scene"].queue_free()
	return fail


func _test_cities_water_does_not_close() -> int:
	## Walls that leave only water as the open side do not make a city
	## (Pedro card t293s1076). Time cost: ~0.5 s alone.
	print("-- test_cities_water_does_not_close")
	var t := _scene("cities_water_does_not_close")
	if t.is_empty():
		return 1
	var fail := 0
	var world = t["world"]
	var cities: Cities = t["cities"]
	_regen(t, 11)
	var water_cell: Variant = null
	for cell: Vector2i in world.get_used_cells(0):
		var p: Array = world.predict_cell(cell)
		if not world.ground_is_walkable(p[0]):
			water_cell = cell
			break
	if water_cell == null:
		printerr("FAIL cities_water_does_not_close: no water cell on seed 11")
		fail += 1
	elif not cities._is_escape(water_cell):
		printerr("FAIL cities_water_does_not_close: water cell %s not escape" % [water_cell])
		fail += 1
	var found_u := false
	for sv in [11, 42, 99]:
		_regen(t, sv)
		for cell: Vector2i in world.get_used_cells(0):
			if not _clear_rect(world, cell, Vector2i(3, 3)):
				continue
			var north_water := true
			for x in range(3):
				var n := cell + Vector2i(x, -1)
				var p2: Array = world.predict_cell(n)
				if world.ground_is_walkable(p2[0]):
					north_water = false
					break
			if not north_water:
				continue
			var walls: Array[Vector2i] = []
			for x in range(-1, 4):
				walls.append(cell + Vector2i(x, 3))
			for y in range(0, 3):
				walls.append(cell + Vector2i(-1, y))
				walls.append(cell + Vector2i(3, y))
			var placeable: Array[Vector2i] = []
			for w in walls:
				if world.get_cell_source_id(0, w) != -1 and world.predicted_clear(w) \
						and not world.has_wall(w) and not world._structures.has_cell(w):
					placeable.append(w)
			if placeable.size() < walls.size():
				continue
			var id := _place_tower(world, cell + Vector2i(1, 2), 1)
			if id <= 0:
				continue
			if not world.place_wall_cells(placeable):
				continue
			cities.rebuild()
			if cities.cities.has(id):
				printerr("FAIL cities_water_does_not_close: water-open U made a city for %s" % id)
				fail += 1
			found_u = true
			break
		if found_u:
			break
	if not found_u:
		print("cities_water_does_not_close: no water-edge U on seeds; escape helper checked")
	t["scene"].queue_free()
	return fail


func _test_cities_off_in_multiplayer() -> int:
	## While multiplayer is on the city list is cleared and stays empty.
	## Time cost: ~0.3 s alone.
	print("-- test_cities_off_in_multiplayer")
	var t := _setup_guard_post("cities_off_in_multiplayer")
	if t.is_empty():
		return 1
	var fail := 0
	var cities: Cities = t["cities"]
	var id: int = t["id"]
	cities.rebuild()
	if not cities.cities.has(id):
		printerr("FAIL cities_off_in_multiplayer: no city offline")
		fail += 1
	var path: NodePath = cities.get_path()
	var api := SceneMultiplayer.new()
	set_multiplayer(api, path)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", _free_udp_port())
	api.multiplayer_peer = peer
	cities.tick()
	if not cities.cities.is_empty():
		printerr("FAIL cities_off_in_multiplayer: cities remained %s" % [cities.cities.keys()])
		fail += 1
	peer.close()
	set_multiplayer(null, path)
	t["scene"].queue_free()
	return fail
