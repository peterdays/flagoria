extends "res://tests/helpers/test_helpers.gd"
## Free-form wall blocks through ConstructionPlacer (#276).


func _clear_wall_cells(world, count: int = 3) -> Array[Vector2i]:
	## Contiguous clear land run of `count` cells (H) that 4-touches a seeded
	## support wall (first block must touch tower/castle/wall — design decision for #276), or
	## empty. The support cell itself is not returned.
	for seed_value in [11, 42, 99, 7, 1, 3, 5, 13, 17]:
		world.apply_map_params(_spawn_params(seed_value, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell: Vector2i in world.get_used_cells(0):
			var run: Array[Vector2i] = []
			for i in range(count + 1):
				var c: Vector2i = cell + Vector2i(i, 0)
				if world.get_cell_source_id(0, c) == -1 or not world.predicted_clear(c) \
						or world.has_wall(c) or world._structures.has_cell(c):
					break
				run.append(c)
			if run.size() == count + 1:
				var support: Array[Vector2i] = [run[0]]
				if not world.place_wall_cells(support):
					continue
				var out: Array[Vector2i] = []
				for i in range(1, run.size()):
					out.append(run[i])
				return out
	return []


func _test_construction_placer_wall() -> int:
	## A clear land cell places a palisade for 2 wood; a straight run places
	## every cell. Water, an existing wall, a structure, a player, a mob, a
	## tree, short wood, a bent run and multiplayer on are refused and spend
	## nothing. Pieces come from WallSolver. Collision stays on redraw.
	## Time cost: about 0.7 s in tools/verify.sh (~2.5 s alone with
	## --only=construction_placer_wall).
	print("-- test_construction_placer_wall")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var inventory: Inventory = scene.get_node("Inventory")
	var placer := ConstructionPlacer.new(world)
	var run := _clear_wall_cells(world, 3)
	if run.is_empty():
		printerr("FAIL construction_placer_wall: no clear 3-cell land run")
		scene.queue_free()
		return 1
	# Floating cell (no 4-touch to wall/tower/castle) refused, no spend.
	var floating: Array[Vector2i] = [Vector2i(1 << 19, 1 << 19)]
	inventory.add(Inventory.WOOD, 2)
	var float_reasons := placer.can_place(BuildCosts.WALL_BLOCK, floating, inventory)
	if ConstructionPlacer.NOT_ADJACENT not in float_reasons \
			or placer.place(BuildCosts.WALL_BLOCK, floating, inventory) \
			or inventory.count_of(Inventory.WOOD) != 2:
		printerr("FAIL construction_placer_wall: floating gave %s wood %d"
				% [float_reasons, inventory.count_of(Inventory.WOOD)])
		fail += 1
	# Fabricated L: _check_wall flags NOT_STRAIGHT regardless of ground.
	var bent: Array[Vector2i] = [
		Vector2i(1000, 1000), Vector2i(1001, 1000), Vector2i(1001, 1001),
	]
	# Short wood (drain leftovers from the floating check first).
	while inventory.count_of(Inventory.WOOD) > 0:
		inventory.spend(Inventory.WOOD, inventory.count_of(Inventory.WOOD))
	inventory.add(Inventory.WOOD, 1)
	var one: Array[Vector2i] = [run[0]]
	var reasons := placer.can_place(BuildCosts.WALL_BLOCK, one, inventory)
	if ConstructionPlacer.NOT_ENOUGH_WOOD not in reasons \
			or placer.place(BuildCosts.WALL_BLOCK, one, inventory) \
			or inventory.count_of(Inventory.WOOD) != 1 \
			or world.has_wall(run[0]):
		printerr("FAIL construction_placer_wall: short wood gave %s wood %d wall %s"
				% [reasons, inventory.count_of(Inventory.WOOD), world.has_wall(run[0])])
		fail += 1
	# Single cell places, spends 2, WallSolver POST on overlay.
	inventory.add(Inventory.WOOD, 1)
	var before := inventory.count_of(Inventory.WOOD)
	reasons = placer.can_place(BuildCosts.WALL_BLOCK, one, inventory)
	var cost := placer.cost(BuildCosts.WALL_BLOCK, one)
	var ok := placer.place(BuildCosts.WALL_BLOCK, one, inventory)
	if not reasons.is_empty() or cost != 2 or not ok \
			or inventory.count_of(Inventory.WOOD) != before - 2 \
			or not world.has_wall(run[0]):
		printerr("FAIL construction_placer_wall: place reasons %s cost %d ok %s wood %d->%d wall %s"
				% [reasons, cost, ok, before, inventory.count_of(Inventory.WOOD), world.has_wall(run[0])])
		fail += 1
	else:
		var atlas: Vector2i = world.get_cell_atlas_coords(1, run[0])
		# Next to the seeded support the solver picks a connected PALISADE_* piece.
		if atlas.y != 15 and atlas.y != 17 and atlas.y != 18:
			printerr("FAIL construction_placer_wall: overlay atlas %s not a palisade row" % [atlas])
			fail += 1
	# Existing wall occupied.
	inventory.add(Inventory.WOOD, 2)
	reasons = placer.can_place(BuildCosts.WALL_BLOCK, one, inventory)
	if ConstructionPlacer.OCCUPIED not in reasons \
			or placer.place(BuildCosts.WALL_BLOCK, one, inventory):
		printerr("FAIL construction_placer_wall: occupied gave %s" % [reasons])
		fail += 1
	# Rest of run places as a straight segment; solver updates neighbours.
	var rest: Array[Vector2i] = [run[1], run[2]]
	inventory.add(Inventory.WOOD, 4)
	before = inventory.count_of(Inventory.WOOD)
	ok = placer.place(BuildCosts.WALL_BLOCK, rest, inventory)
	if not ok or inventory.count_of(Inventory.WOOD) != before - 4 \
			or not rest.all(func(c: Vector2i) -> bool: return world.has_wall(c)):
		printerr("FAIL construction_placer_wall: run place ok %s wood %d"
				% [ok, inventory.count_of(Inventory.WOOD)])
		fail += 1
	else:
		var mid: Vector2i = world._walls.piece(run[1])
		if mid != TileCatalog.PALISADE_H:
			printerr("FAIL construction_placer_wall: mid piece %s want PALISADE_H" % [mid])
			fail += 1
	# Water refused.
	var water_cell := Vector2i(1 << 20, 0)
	for cell in world.get_used_cells(0):
		if world.predict_cell(cell)[0] == TileCatalog.WATER and not world.has_bridge(cell):
			water_cell = cell
			break
	if water_cell.x != 1 << 20:
		var wcells: Array[Vector2i] = [water_cell]
		inventory.add(Inventory.WOOD, 2)
		reasons = placer.can_place(BuildCosts.WALL_BLOCK, wcells, inventory)
		if ConstructionPlacer.WRONG_GROUND not in reasons \
				or placer.place(BuildCosts.WALL_BLOCK, wcells, inventory):
			printerr("FAIL construction_placer_wall: water gave %s" % [reasons])
			fail += 1
	else:
		printerr("FAIL construction_placer_wall: no water cell")
		fail += 1
	# Bent L refused.
	inventory.add(Inventory.WOOD, 6)
	reasons = placer.can_place(BuildCosts.WALL_BLOCK, bent, inventory)
	if ConstructionPlacer.NOT_STRAIGHT not in reasons \
			or placer.place(BuildCosts.WALL_BLOCK, bent, inventory):
		printerr("FAIL construction_placer_wall: bent gave %s" % [reasons])
		fail += 1
	# Player / mob occupancy on a clear cell.
	var clear2: Vector2i = Vector2i(1 << 20, 0)
	for cell: Vector2i in world.get_used_cells(0):
		if world.predicted_clear(cell) and not world.has_wall(cell) \
				and not world._structures.has_cell(cell):
			clear2 = cell
			break
	if clear2.x != 1 << 20:
		var player = load("res://Player/character_body_2d.tscn").instantiate()
		player.name = "occupier"
		player.global_position = world.to_global(world.map_to_local(clear2))
		scene.get_node("World").add_child(player)
		await process_frame
		var pcells: Array[Vector2i] = [clear2]
		inventory.add(Inventory.WOOD, 2)
		reasons = placer.can_place(BuildCosts.WALL_BLOCK, pcells, inventory)
		if ConstructionPlacer.OCCUPIED not in reasons \
				or placer.place(BuildCosts.WALL_BLOCK, pcells, inventory):
			printerr("FAIL construction_placer_wall: player gave %s" % [reasons])
			fail += 1
		player.queue_free()
		await process_frame
		var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
		mob.setup(MobCatalog.SLIME, world.to_global(world.map_to_local(clear2)), 1)
		scene.get_node("World/Mobs").add_child(mob)
		await process_frame
		reasons = placer.can_place(BuildCosts.WALL_BLOCK, pcells, inventory)
		if ConstructionPlacer.OCCUPIED not in reasons \
				or placer.place(BuildCosts.WALL_BLOCK, pcells, inventory):
			printerr("FAIL construction_placer_wall: mob gave %s" % [reasons])
			fail += 1
		mob.queue_free()
		await process_frame
	else:
		printerr("FAIL construction_placer_wall: no clear cell for occupancy")
		fail += 1
	# Collision kept on redraw (before we re-seed for the tree check).
	var kept: Vector2i = world._walls.piece(run[0])
	world.generate_chunk(Vector2(0, 0))
	if not world.has_wall(run[0]) or world.get_cell_atlas_coords(1, run[0]) != kept:
		printerr("FAIL construction_placer_wall: redraw lost wall atlas %s now %s"
				% [kept, world.get_cell_atlas_coords(1, run[0])])
		fail += 1
	# Tree/bush occupied: search a biome-seeded chunk so plants exist.
	var tree_cell := Vector2i(1 << 20, 0)
	for seed_value in [49, 21, 33, 11]:
		world.apply_map_params(_spawn_params(seed_value, 0.02))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			var top = world.predict_cell(cell)[1]
			if top == TileCatalog.TREE or top == TileCatalog.PINE \
					or top == TileCatalog.TREE_BUSHY or top == TileCatalog.BUSH:
				tree_cell = cell
				break
		if tree_cell.x != 1 << 20:
			break
	if tree_cell.x != 1 << 20:
		var tcells: Array[Vector2i] = [tree_cell]
		inventory.add(Inventory.WOOD, 2)
		reasons = placer.can_place(BuildCosts.WALL_BLOCK, tcells, inventory)
		if ConstructionPlacer.OCCUPIED not in reasons \
				or placer.place(BuildCosts.WALL_BLOCK, tcells, inventory):
			printerr("FAIL construction_placer_wall: tree gave %s" % [reasons])
			fail += 1
	else:
		printerr("FAIL construction_placer_wall: no tree/bush cell")
		fail += 1
	# Multiplayer on.
	var peer := ENetMultiplayerPeer.new()
	var api := SceneMultiplayer.new()
	if peer.create_client("127.0.0.1", 1) != OK:
		printerr("FAIL construction_placer_wall: could not start ENet client")
		fail += 1
	else:
		api.multiplayer_peer = peer
		set_multiplayer(api, scene.get_path())
		var mcell: Vector2i = tree_cell if tree_cell.x != 1 << 20 else (clear2 if clear2.x != 1 << 20 else run[0])
		var mcells: Array[Vector2i] = [mcell]
		inventory.add(Inventory.WOOD, 2)
		reasons = placer.can_place(BuildCosts.WALL_BLOCK, mcells, inventory)
		if ConstructionPlacer.MULTIPLAYER_ON not in reasons \
				or placer.place(BuildCosts.WALL_BLOCK, mcells, inventory):
			printerr("FAIL construction_placer_wall: multiplayer gave %s" % [reasons])
			fail += 1
		api.multiplayer_peer = null
		peer.close()
		set_multiplayer(null, scene.get_path())
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_placer_wall")
	return fail


func _test_construction_placer_wall_atomic_spend() -> int:
	## Wall writer is all-or-nothing (#380): a spend-fail stub leaves no wall;
	## a writer refusal after a real spend refunds the wood. Time cost: about
	## 0.3 s in tools/verify.sh (~2.0 s alone with
	## --only=construction_placer_wall_atomic_spend).
	print("-- test_construction_placer_wall_atomic_spend")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var stub: Inventory = (load("res://tests/mechanics/building/spend_fail_inventory.gd") as GDScript).new()
	scene.add_child(stub)
	var placer := ConstructionPlacer.new(world)
	var run := _clear_wall_cells(world, 1)
	if run.is_empty():
		printerr("FAIL construction_placer_wall_atomic_spend: no clear cell")
		scene.queue_free()
		return 1
	stub.add(Inventory.WOOD, 2)
	var reasons := placer.can_place(BuildCosts.WALL_BLOCK, run, stub)
	var placed := placer.place(BuildCosts.WALL_BLOCK, run, stub)
	if not reasons.is_empty() or placed or world.has_wall(run[0]) \
			or stub.count_of(Inventory.WOOD) != 2:
		printerr("FAIL construction_placer_wall_atomic_spend: spend-fail reasons %s placed %s wood %d wall %s"
				% [reasons, placed, stub.count_of(Inventory.WOOD), world.has_wall(run[0])])
		fail += 1
	var inventory: Inventory = scene.get_node("Inventory")
	inventory.add(Inventory.WOOD, 2)
	var why := BuildCosts.buy(inventory, BuildCosts.WALL_BLOCK, 1, func() -> bool: return false)
	if why != BuildCosts.NOT_PLACED or inventory.count_of(Inventory.WOOD) != 2:
		printerr("FAIL construction_placer_wall_atomic_spend: writer refuse got '%s' wood %d"
				% [why, inventory.count_of(Inventory.WOOD)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_placer_wall_atomic_spend")
	return fail
