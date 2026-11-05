extends "res://tests/helpers/test_helpers.gd"
## Buildable wooden tower through ConstructionPlacer (#273).


func _clear_tower_anchor(world) -> Variant:
	## First drawn anchor whose 3x3 tower_wood footprint is predicted_clear.
	var s: Structure = StructurePlacer.load_named("tower_wood")
	if s == null:
		return null
	for seed_value in [11, 42, 99, 7, 1, 3, 5]:
		world.apply_map_params(_spawn_params(seed_value, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell: Vector2i in world.get_used_cells(0):
			var cells: Array = StructurePlacer.footprint(s, cell).keys()
			if cells.is_empty():
				continue
			if cells.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
				return cell
	return null


func _test_construction_placer_tower() -> int:
	## A clear land anchor places tower_wood for 10 wood, owned by the local
	## peer with a team flag. Water, an overlapping structure, a player, a mob,
	## too little wood and multiplayer on are refused and spend nothing.
	## Time cost: about 0.6 s in tools/verify.sh (~2.3 s alone with
	## --only=construction_placer_tower, against ~1.7 s runner start-up).
	print("-- test_construction_placer_tower")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var inventory: Inventory = scene.get_node("Inventory")
	var placer := ConstructionPlacer.new(world)
	var anchor: Variant = _clear_tower_anchor(world)
	if anchor == null:
		printerr("FAIL construction_placer_tower: no clear 3x3 land near origin")
		scene.queue_free()
		return 1
	var cells: Array[Vector2i] = [anchor]
	# Too little wood.
	inventory.add(Inventory.WOOD, 9)
	var reasons := placer.can_place(BuildCosts.TOWER, cells, inventory)
	if ConstructionPlacer.NOT_ENOUGH_WOOD not in reasons \
			or placer.place(BuildCosts.TOWER, cells, inventory) \
			or inventory.count_of(Inventory.WOOD) != 9 \
			or not world.placed_structures().is_empty():
		printerr("FAIL construction_placer_tower: short wood gave %s wood %d placed %s"
				% [reasons, inventory.count_of(Inventory.WOOD), world.placed_structures()])
		fail += 1
	# Enough wood: places, spends 10, owns flag.
	inventory.add(Inventory.WOOD, 1)
	var before := inventory.count_of(Inventory.WOOD)
	reasons = placer.can_place(BuildCosts.TOWER, cells, inventory)
	var cost := placer.cost(BuildCosts.TOWER, cells)
	var ok := placer.place(BuildCosts.TOWER, cells, inventory)
	var placed: Dictionary = world.placed_structures()
	var owner_id: int = scene.multiplayer.get_unique_id()
	if not reasons.is_empty() or cost != 10 or not ok \
			or inventory.count_of(Inventory.WOOD) != before - 10 \
			or placed.size() != 1:
		printerr("FAIL construction_placer_tower: place reasons %s cost %d ok %s wood %d->%d placed %s"
				% [reasons, cost, ok, before, inventory.count_of(Inventory.WOOD), placed])
		fail += 1
	else:
		var id: int = placed.keys()[0]
		var entry: Dictionary = placed[id]
		var towers: Dictionary = world._structures.towers()
		if entry.get("name") != "tower_wood" or entry.get("owner") != owner_id \
				or entry.get("anchor") != anchor or not towers.has(id):
			printerr("FAIL construction_placer_tower: entry %s towers %s owner want %d"
					% [entry, towers, owner_id])
			fail += 1
		else:
			var flag: Vector2i = towers[id][0]
			var want_flag: String = StructurePlacer.OWNER_FLAGS.get(owner_id, StructurePlacer.OTHER_OWNER_FLAG)
			if world.predict_cell(flag)[1] != TileCatalog.TILES[want_flag]["atlas"]:
				printerr("FAIL construction_placer_tower: flag atlas %s want %s"
						% [world.predict_cell(flag)[1], TileCatalog.TILES[want_flag]["atlas"]])
				fail += 1
	# Overlapping structure refused.
	inventory.add(Inventory.WOOD, 10)
	reasons = placer.can_place(BuildCosts.TOWER, cells, inventory)
	if ConstructionPlacer.OCCUPIED not in reasons or placer.place(BuildCosts.TOWER, cells, inventory):
		printerr("FAIL construction_placer_tower: overlap gave %s" % [reasons])
		fail += 1
	# Water refused (wrong ground).
	var water_anchor := Vector2i(1 << 20, 0)
	for cell in world.get_used_cells(0):
		if world.predict_cell(cell)[0] == TileCatalog.WATER and not world.has_bridge(cell):
			water_anchor = cell
			break
	if water_anchor.x != 1 << 20:
		var wcells: Array[Vector2i] = [water_anchor]
		reasons = placer.can_place(BuildCosts.TOWER, wcells, inventory)
		if ConstructionPlacer.WRONG_GROUND not in reasons \
				or placer.place(BuildCosts.TOWER, wcells, inventory):
			printerr("FAIL construction_placer_tower: water gave %s" % [reasons])
			fail += 1
	else:
		printerr("FAIL construction_placer_tower: no water cell on chunk")
		fail += 1
	# Player occupancy.
	var clear2: Variant = null
	var s: Structure = StructurePlacer.load_named("tower_wood")
	for cell: Vector2i in world.get_used_cells(0):
		var foot: Array = StructurePlacer.footprint(s, cell).keys()
		if foot.all(func(c): return world.predicted_clear(c) and not world._structures.has_cell(c)):
			clear2 = cell
			break
	if clear2 != null:
		var player = load("res://Player/character_body_2d.tscn").instantiate()
		player.name = "occupier"
		player.global_position = world.to_global(world.map_to_local(clear2))
		scene.get_node("World").add_child(player)
		await process_frame
		var pcells: Array[Vector2i] = [clear2]
		reasons = placer.can_place(BuildCosts.TOWER, pcells, inventory)
		if ConstructionPlacer.OCCUPIED not in reasons \
				or placer.place(BuildCosts.TOWER, pcells, inventory):
			printerr("FAIL construction_placer_tower: player gave %s" % [reasons])
			fail += 1
		player.queue_free()
		await process_frame
		# Mob occupancy.
		var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
		mob.setup(MobCatalog.SLIME, world.to_global(world.map_to_local(clear2)), 1)
		scene.get_node("World/Mobs").add_child(mob)
		await process_frame
		reasons = placer.can_place(BuildCosts.TOWER, pcells, inventory)
		if ConstructionPlacer.OCCUPIED not in reasons \
				or placer.place(BuildCosts.TOWER, pcells, inventory):
			printerr("FAIL construction_placer_tower: mob gave %s" % [reasons])
			fail += 1
		mob.queue_free()
	else:
		printerr("FAIL construction_placer_tower: no second clear spot for occupancy")
		fail += 1
	# Multiplayer on.
	var peer := ENetMultiplayerPeer.new()
	var api := SceneMultiplayer.new()
	if peer.create_client("127.0.0.1", 1) != OK:
		printerr("FAIL construction_placer_tower: could not start ENet client")
		fail += 1
	else:
		api.multiplayer_peer = peer
		set_multiplayer(api, scene.get_path())
		if clear2 != null:
			var mcells: Array[Vector2i] = [clear2]
			reasons = placer.can_place(BuildCosts.TOWER, mcells, inventory)
			if ConstructionPlacer.MULTIPLAYER_ON not in reasons \
					or placer.place(BuildCosts.TOWER, mcells, inventory):
				printerr("FAIL construction_placer_tower: multiplayer gave %s" % [reasons])
				fail += 1
		api.multiplayer_peer = null
		peer.close()
		set_multiplayer(null, scene.get_path())
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_placer_tower")
	return fail


func _test_construction_placer_tower_atomic_spend() -> int:
	## Tower writer is all-or-nothing (#380 comment): a spend-fail stub leaves
	## no structure; a writer refusal after a real spend refunds the 10 wood.
	## Time cost: about 0.3 s in tools/verify.sh (~2.0 s alone with
	## --only=construction_placer_tower_atomic_spend).
	print("-- test_construction_placer_tower_atomic_spend")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var stub: Inventory = (load("res://tests/mechanics/building/spend_fail_inventory.gd") as GDScript).new()
	scene.add_child(stub)
	var placer := ConstructionPlacer.new(world)
	var anchor: Variant = _clear_tower_anchor(world)
	if anchor == null:
		printerr("FAIL construction_placer_tower_atomic_spend: no clear 3x3")
		scene.queue_free()
		return 1
	var cells: Array[Vector2i] = [anchor]
	stub.add(Inventory.WOOD, 10)
	var reasons := placer.can_place(BuildCosts.TOWER, cells, stub)
	var placed := placer.place(BuildCosts.TOWER, cells, stub)
	if not reasons.is_empty() or placed or not world.placed_structures().is_empty() \
			or stub.count_of(Inventory.WOOD) != 10:
		printerr("FAIL construction_placer_tower_atomic_spend: spend-fail reasons %s placed %s wood %d structs %s"
				% [reasons, placed, stub.count_of(Inventory.WOOD), world.placed_structures()])
		fail += 1
	# Writer refuse refunds: buy with a writer that always fails.
	var inventory: Inventory = scene.get_node("Inventory")
	inventory.add(Inventory.WOOD, 10)
	var why := BuildCosts.buy(inventory, BuildCosts.TOWER, 1, func() -> bool: return false)
	if why != BuildCosts.NOT_PLACED or inventory.count_of(Inventory.WOOD) != 10:
		printerr("FAIL construction_placer_tower_atomic_spend: writer refuse got '%s' wood %d"
				% [why, inventory.count_of(Inventory.WOOD)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_placer_tower_atomic_spend")
	return fail
