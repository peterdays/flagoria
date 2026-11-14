extends "res://tests/helpers/test_helpers.gd"
## Land inside city walls, limited by each flag's range (#279). One tower
## scores only the interior cells inside its disk. A second tower adds the
## cells it newly covers. Opening the wall removes the city and the points.
## The scoreboard reads the same Points total. Radius 2 keeps the fixture
## small; play uses LandScore.range_cells (5).


func _scene(label: String) -> Dictionary:
	LandScore.enabled = true
	LandScore.range_cells = 2
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var land: LandScore = scene.get_node_or_null("World/LandScore")
	var points: Points = scene.get_node_or_null("Points")
	var cities: Cities = scene.get_node_or_null("World/Cities")
	if land == null or points == null or cities == null:
		printerr("FAIL %s: LandScore, Points or Cities missing" % label)
		scene.queue_free()
		_restore_range()
		return {}
	return {
		"scene": scene, "world": scene.get_node("World/worldMap"),
		"land": land, "points": points, "cities": cities,
	}


func _restore_range() -> void:
	LandScore.range_cells = 5
	LandScore.enabled = true


func _perimeter(lo: Vector2i, hi: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(lo.x, hi.x + 1):
		out.append(Vector2i(x, lo.y))
		out.append(Vector2i(x, hi.y))
	for y in range(lo.y + 1, hi.y):
		out.append(Vector2i(lo.x, y))
		out.append(Vector2i(hi.x, y))
	return out


func _walkable_rect(world, origin: Vector2i, size: Vector2i) -> bool:
	for y in size.y:
		for x in size.x:
			var c := origin + Vector2i(x, y)
			if world.get_cell_source_id(0, c) == -1:
				return false
			var ground: Vector2i = world.predict_cell(c)[0]
			if not world.ground_is_walkable(ground):
				return false
	return true


func _carve(world, origin: Vector2i, size: Vector2i) -> bool:
	## Cut trees and pick stones so a walkable rect accepts a tower and walls.
	if not _walkable_rect(world, origin, size):
		return false
	for y in size.y:
		for x in size.x:
			var c := origin + Vector2i(x, y)
			world.cut_grown(c)
			world._object_removals.remove_any(c)
			if not world.predicted_clear(c):
				return false
	return true


func _find_clear(world, size: Vector2i) -> Variant:
	for cell: Vector2i in world.get_used_cells(0):
		if _carve(world, cell, size):
			return cell
	return null


func _setup_city(label: String) -> Dictionary:
	## A closed free-form ring with one wooden tower near a corner, or {}.
	var t := _scene(label)
	if t.is_empty():
		return {}
	var world = t["world"]
	var span := Vector2i(8, 5)
	for sv in [11, 42, 99, 7, 3]:
		world.apply_map_params(_spawn_params(sv, 0.0))
		for off in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]:
			world.generate_chunk(off)
		var origin = _find_clear(world, span)
		if origin == null:
			continue
		var o: Vector2i = origin
		var id: int = world.place_structure(StructurePlacer.load_named("tower_wood"), o + Vector2i(2, 3), 1)
		if id <= 0:
			continue
		var ring := _perimeter(o, o + Vector2i(7, 4))
		var blocked := false
		for cell in ring:
			if world._structures.has_cell(cell) or not world.predicted_clear(cell) \
					or world.get_cell_source_id(0, cell) == -1:
				blocked = true
				break
		if blocked or not world.place_wall_cells(ring):
			continue
		t["id"] = id
		t["origin"] = o
		t["ring"] = ring
		t["land"].tick()
		return t
	printerr("FAIL %s: no 8x5 walkable ring on seeds 11, 42, 99, 7, 3" % label)
	t["scene"].queue_free()
	_restore_range()
	return {}


func _manual(t: Dictionary, peer: int) -> int:
	## Interior cells of `peer`'s cities inside a Euclidean disk of the test
	## radius around one of that peer's flags. Independent of LandScore.
	var world = t["world"]
	var cities: Cities = t["cities"]
	var towers: Dictionary = world._structures.towers()
	var placed: Dictionary = world._structures.placements()
	var flags: Array[Vector2i] = []
	for id in towers:
		if int(placed.get(id, {}).get("owner", 0)) != peer:
			continue
		for flag in towers[id]:
			flags.append(flag)
	var seen := {}
	var r2 := LandScore.range_cells * LandScore.range_cells
	for id in cities.cities:
		if cities.owner_of(int(id)) != peer:
			continue
		for cell in cities.cities[id]["interior"]:
			if seen.has(cell):
				continue
			var c: Vector2i = cell
			for flag in flags:
				var d := c - flag
				if d.x * d.x + d.y * d.y <= r2:
					seen[c] = true
					break
	return seen.size()


func _interior(t: Dictionary, peer: int) -> int:
	var cities: Cities = t["cities"]
	var seen := {}
	for id in cities.cities:
		if cities.owner_of(int(id)) != peer:
			continue
		for cell in cities.cities[id]["interior"]:
			seen[cell] = true
	return seen.size()


func _board_shows(scene: Node, points: Points, peer: int) -> bool:
	var board: ScoreboardPanel = scene.get_node("CanvasLayer1/ScoreboardPanel")
	board.bind(points, peer)
	for row in board.sorted_rows():
		if int(row[0]) == peer and int(row[1]) == points.total_of(peer):
			return true
	return false


func _test_land_score_range() -> int:
	## One tower scores only its disk. A second tower raises that total.
	## Opening the ring removes the city and the points. The scoreboard
	## shows the same number. Time cost: ~0.5 s.
	print("-- test_land_score_range")
	var t := _setup_city("land_score_range")
	if t.is_empty():
		return 1
	var fail := 0
	var land: LandScore = t["land"]
	var points: Points = t["points"]
	var want := _manual(t, 1)
	var inside := _interior(t, 1)
	if want <= 0 or want >= inside or points.total_of(1) != want:
		printerr("FAIL land_score_range: one tower total %s, disk %s, interior %s"
				% [points.total_of(1), want, inside])
		fail += 1
	var flag: Vector2i = t["world"]._structures.towers()[t["id"]][0]
	if land.select_cell(flag) != t["id"] or not is_equal_approx(land.ring_radius_px(), 2.0 * 16.0):
		printerr("FAIL land_score_range: selected %s radius %s" % [land.selected_tower, land.ring_radius_px()])
		fail += 1
	elif not _board_shows(t["scene"], points, 1):
		printerr("FAIL land_score_range: scoreboard %s, points %s"
				% [t["scene"].get_node("CanvasLayer1/ScoreboardPanel").sorted_rows(), points.total_of(1)])
		fail += 1
	var second: int = t["world"].place_structure(
			StructurePlacer.load_named("tower_wood"), t["origin"] + Vector2i(5, 3), 1)
	land.tick()
	var raised := _manual(t, 1)
	if second <= 0 or raised <= want or points.total_of(1) != raised:
		printerr("FAIL land_score_range: second tower %s total %s, was %s, disk %s"
				% [second, points.total_of(1), want, raised])
		fail += 1
	elif not _board_shows(t["scene"], points, 1):
		printerr("FAIL land_score_range: scoreboard after the second tower %s"
				% [t["scene"].get_node("CanvasLayer1/ScoreboardPanel").sorted_rows()])
		fail += 1
	var gap: Vector2i = t["cities"].cities[t["id"]]["walls"].keys()[0]
	var open: Array[Vector2i] = [gap]
	if not t["world"]._walls.erase_cells(open):
		printerr("FAIL land_score_range: could not open %s" % gap)
		fail += 1
	else:
		land.tick()
		if points.total_of(1) != 0 or land.covered_of(1) != 0 or t["cities"].cities.has(t["id"]):
			printerr("FAIL land_score_range: after the gap total %s covered %s cities %s"
					% [points.total_of(1), land.covered_of(1), t["cities"].cities.keys()])
			fail += 1
		elif not _board_shows(t["scene"], points, 1):
			printerr("FAIL land_score_range: scoreboard after the loss %s"
					% [t["scene"].get_node("CanvasLayer1/ScoreboardPanel").sorted_rows()])
			fail += 1
	t["scene"].queue_free()
	_restore_range()
	if fail == 0:
		print("PASS test_land_score_range")
	return fail


func _test_land_score_client_skips() -> int:
	## A connecting client does not award land. Offline, the same peer does.
	## Time cost: ~0.4 s. The connect is refused; nothing waits on a peer.
	print("-- test_land_score_client_skips")
	var t := _setup_city("land_score_client_skips")
	if t.is_empty():
		return 1
	var fail := 0
	var held: int = t["points"].total_of(1)
	var path: NodePath = t["land"].get_path()
	var api := SceneMultiplayer.new()
	set_multiplayer(api, path)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", _free_udp_port())
	api.multiplayer_peer = peer
	t["land"].tick()
	if t["points"].total_of(1) != held:
		printerr("FAIL land_score_client_skips: client moved the total to %s" % t["points"].total_of(1))
		fail += 1
	peer.close()
	set_multiplayer(null, path)
	t["world"]._structures.set_owner(t["id"], 2)
	t["land"].tick()
	if t["points"].total_of(1) != 0 or t["points"].total_of(2) <= 0:
		printerr("FAIL land_score_client_skips: offline totals host %s other %s"
				% [t["points"].total_of(1), t["points"].total_of(2)])
		fail += 1
	t["scene"].queue_free()
	_restore_range()
	if fail == 0:
		print("PASS test_land_score_client_skips")
	return fail
