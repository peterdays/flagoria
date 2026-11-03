extends "res://tests/helpers/test_helpers.gd"
## Each player starts with one castle (structures/castle.txt, #271).


func _castle() -> Structure:
	if not FileAccess.file_exists("res://structures/castle.txt"):
		return null
	return Structure.parse(FileAccess.get_file_as_string("res://structures/castle.txt"))["structure"]


func _legend_cell(s: Structure, anchor_cell: Vector2i, tile_prefix: String) -> Vector2i:
	## The map cell of the first object entry whose tile starts with
	## `tile_prefix`, for `s` placed with its anchor on `anchor_cell`.
	for y in s.size.y:
		for x in s.size.x:
			var o: String = s.layers["object"][y][x]
			if o != Structure.EMPTY and s.legend[o]["tile"].begins_with(tile_prefix):
				return anchor_cell + Vector2i(x, y) - s.anchor
	return Vector2i.MAX


func _check_castle(label: String, world, s: Structure) -> Dictionary:
	## {"fail": count, "front": the land cell outside the gate} for the one
	## castle on `world`: owned by the host, every cell on land, an open gate
	## with clear land outside it that reaches at least SPAWN_MIN_REACHABLE
	## clear cells, a clear courtyard inside, and the host's blue flag.
	var out := {"fail": 0, "front": Vector2i.MAX}
	var listed: Dictionary = world.placed_structures()
	if listed.size() != 1:
		printerr("FAIL start_castle %s: %d placements, want one castle: %s" % [label, listed.size(), listed])
		out["fail"] += 1
		return out
	var entry: Dictionary = listed.values()[0]
	if entry["name"] != "castle" or entry["owner"] != 1:
		printerr("FAIL start_castle %s: placement %s, want the host's castle" % [label, entry])
		out["fail"] += 1
	var anchor: Vector2i = entry["anchor"]
	for c: Vector2i in StructurePlacer.footprint(s, anchor):
		if not world.ground_is_walkable(world.predict_cell(c)[0]):
			printerr("FAIL start_castle %s: castle cell %s is not on land" % [label, c])
			out["fail"] += 1
			break
	var gate := _legend_cell(s, anchor, "WALL_GATE_")
	var front := gate + Vector2i(0, 1)
	out["front"] = front
	if world.get_cell_atlas_coords(1, gate) != TileCatalog.WALL_GATE_H_OPEN:
		printerr("FAIL start_castle %s: gate %s drawn %s, want an open gate" % [label, gate, world.get_cell_atlas_coords(1, gate)])
		out["fail"] += 1
	if not world.is_clear_ground(front) or not world.is_clear_ground(gate + Vector2i(0, -1)):
		printerr("FAIL start_castle %s: outside %s or inside the gate is not clear land" % [label, front])
		out["fail"] += 1
	var reach: int = world.reachable_clear_cells(front).size()
	if reach < world.SPAWN_MIN_REACHABLE:
		printerr("FAIL start_castle %s: the gate reaches %d clear cells, want %d" % [label, reach, world.SPAWN_MIN_REACHABLE])
		out["fail"] += 1
	var flag := _legend_cell(s, anchor, "PROP_FLAG_")
	if world.get_cell_atlas_coords(1, flag) != TileCatalog.PROP_FLAG_BLUE:
		printerr("FAIL start_castle %s: flag %s is not the host's blue" % [label, flag])
		out["fail"] += 1
	return out


func _check_gate_fit(label: String, world, player: CharacterBody2D, front: Vector2i) -> int:
	## The player's body walks from the gate front through the open gate
	## into the courtyard without touching a wall, while a step from the
	## gate cell into the wall beside it collides (so the walls are live).
	await physics_frame
	await physics_frame
	var at := func(cell: Vector2i) -> Transform2D:
		return Transform2D(0.0, world.to_global(world.map_to_local(cell)))
	var step := func(from: Vector2i, to: Vector2i) -> Vector2:
		return world.to_global(world.map_to_local(to)) - world.to_global(world.map_to_local(from))
	var gate := front + Vector2i(0, -1)
	var court := front + Vector2i(0, -2)
	var through: bool = player.test_move(at.call(front), step.call(front, court))
	var into_wall: bool = player.test_move(at.call(gate), step.call(gate, gate + Vector2i(-1, 0)))
	if through or not into_wall:
		printerr("FAIL start_castle %s: through the gate collides %s, into the wall beside it %s" % [label, through, into_wall])
		return 1
	return 0


func _test_start_castle() -> int:
	## Hosting a new world (alone) places the host's castle next to the
	## spawn on seeds 11, 42 and 99 and the player starts outside its gate,
	## where it also respawns, and its body fits through the gate. A spot taken by a player moves the search
	## outward. A dedicated server, with no player of its own, has none.
	print("-- test_start_castle")
	var s := _castle()
	if s == null:
		printerr("FAIL start_castle: structures/castle.txt is missing or does not parse")
		return 1
	var fail := 0
	var biomes: float = MapGenParams.make_defaults().biome_frequency
	for sv in [11, 42, 99]:
		var scene = load("res://flagoria_main.tscn").instantiate()
		root.add_child(scene)
		var world = scene.get_node("World/worldMap")
		if scene.setup_server(_spawn_params(sv, biomes), _free_udp_port()) != OK:
			printerr("FAIL start_castle seed %s: cannot host" % sv)
			fail += 1
		var me: int = scene.multiplayer.get_unique_id()
		scene.add_player(me)
		var got := _check_castle("seed %s" % sv, world, s)
		fail += got["fail"]
		var player = scene.get_node_or_null("World/%s" % me)
		if player == null or player.position != world.map_to_local(got["front"]) \
				or world.resolve_player_spawn() != got["front"]:
			printerr("FAIL start_castle seed %s: player at %s, spawn %s, want the gate front %s" % [sv,
				player.position if player else null, world.resolve_player_spawn(), got["front"]])
			fail += 1
		elif player.spawn_position() != world.map_to_local(got["front"]):
			printerr("FAIL start_castle seed %s: respawn at %s, want the gate front" % [sv, player.spawn_position()])
			fail += 1
		else:
			fail += await _check_gate_fit("seed %s" % sv, world, player, got["front"])
		if sv == 11 and got["front"] != Vector2i.MAX:
			# Stand a player on the castle's gate: the next search starts
			# from the same spawn and must move outward.
			var first: Vector2i = world.placed_structures().values()[0]["anchor"]
			var origin: Vector2i = SpawnFinder.resolve_player_spawn(world)
			world.apply_map_params(_spawn_params(sv, biomes))
			player.position = world.map_to_local(_legend_cell(s, first, "WALL_GATE_"))
			if not world.place_start_castle(me):
				printerr("FAIL start_castle moved: no castle once the first spot is taken")
				fail += 1
			else:
				var moved := _check_castle("moved", world, s)
				fail += moved["fail"]
				var second: Vector2i = world.placed_structures().values()[0]["anchor"]
				if second == first or Vector2(moved["front"]).distance_to(origin) < Vector2(got["front"]).distance_to(origin):
					printerr("FAIL start_castle moved: castle at %s after %s, gate front %s nearer %s than %s"
							% [second, first, moved["front"], origin, got["front"]])
					fail += 1
		scene.enet_peer.close()
		scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		scene.queue_free()
		await process_frame
	var dedicated = load("res://flagoria_main.tscn").instantiate()
	root.add_child(dedicated)
	if dedicated.start_dedicated_server(_free_udp_port(), _spawn_params(11, biomes)) != OK \
			or not dedicated.get_node("World/worldMap").placed_structures().is_empty():
		printerr("FAIL start_castle: a dedicated server placed %s" % dedicated.get_node("World/worldMap").placed_structures())
		fail += 1
	dedicated.enet_peer.close()
	dedicated.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	dedicated.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_start_castle")
	return fail
