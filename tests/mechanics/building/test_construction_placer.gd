extends "res://tests/helpers/test_helpers.gd"
## Shared construction placement (#296): plank runs through ConstructionPlacer.


func _test_construction_placer_plank() -> int:
	## A straight plank run on water that touches land places and spends one
	## wood per cell. Too little wood places and spends nothing. Land, an
	## existing plank, a bent run and a floating water cell (no land or plank
	## next to it) are refused with a reason. While multiplayer is on, planks
	## still place (bridge sync #297); towers/walls stay refused. Time cost:
	## about 0.4 s in tools/verify.sh (~2.0 s alone with
	## --only=construction_placer_plank, against ~1.7 s runner start-up).
	print("-- test_construction_placer_plank")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var inventory: Inventory = scene.get_node("Inventory")
	var placer := ConstructionPlacer.new(world)
	var land := func(c: Vector2i) -> bool:
		return not world.has_bridge(c) and world.ground_is_walkable(world.predict_cell(c)[0])
	var shore := Vector2i(1 << 20, 0)
	var water_run: Array[Vector2i] = []
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if not land.call(cell):
				continue
			var run: Array[Vector2i] = []
			for i in range(1, 4):
				var w: Vector2i = cell + Vector2i(i, 0)
				if world.predict_cell(w)[0] != TileCatalog.WATER or world.has_bridge(w):
					break
				run.append(w)
			if run.size() >= 2:
				shore = cell
				water_run = run
				break
		if not water_run.is_empty():
			break
	if water_run.is_empty():
		printerr("FAIL construction_placer_plank: no 2+ water cells east of land near the origin")
		scene.queue_free()
		return 1
	# Land cell refused.
	var on_land: Array[Vector2i] = [shore]
	inventory.add(Inventory.WOOD, 5)
	var reasons := placer.can_place(BuildCosts.PLANK, on_land, inventory)
	if ConstructionPlacer.WRONG_GROUND not in reasons \
			or placer.place(BuildCosts.PLANK, on_land, inventory) \
			or inventory.count_of(Inventory.WOOD) != 5:
		printerr("FAIL construction_placer_plank: land gave %s, placed %s, wood %d"
				% [reasons, world.has_bridge(shore), inventory.count_of(Inventory.WOOD)])
		fail += 1
	# Too little wood: need water_run.size(), have 1.
	inventory.spend(Inventory.WOOD, 4)
	reasons = placer.can_place(BuildCosts.PLANK, water_run, inventory)
	if ConstructionPlacer.NOT_ENOUGH_WOOD not in reasons \
			or placer.place(BuildCosts.PLANK, water_run, inventory) \
			or inventory.count_of(Inventory.WOOD) != 1 \
			or world.has_bridge(water_run[0]):
		printerr("FAIL construction_placer_plank: short wood gave %s, wood %d, bridge %s"
				% [reasons, inventory.count_of(Inventory.WOOD), world.has_bridge(water_run[0])])
		fail += 1
	# Enough wood: places the run and spends.
	inventory.add(Inventory.WOOD, water_run.size() - 1)
	var before := inventory.count_of(Inventory.WOOD)
	reasons = placer.can_place(BuildCosts.PLANK, water_run, inventory)
	var cost := placer.cost(BuildCosts.PLANK, water_run)
	if not reasons.is_empty() or cost != water_run.size() \
			or not placer.place(BuildCosts.PLANK, water_run, inventory) \
			or inventory.count_of(Inventory.WOOD) != before - cost \
			or not water_run.all(func(c: Vector2i) -> bool: return world.has_bridge(c)):
		printerr("FAIL construction_placer_plank: place gave reasons %s, wood %d->%d, bridges %s"
				% [reasons, before, inventory.count_of(Inventory.WOOD),
					water_run.map(func(c: Vector2i) -> bool: return world.has_bridge(c))])
		fail += 1
	# Existing plank occupied.
	inventory.add(Inventory.WOOD, 2)
	var one: Array[Vector2i] = [water_run[0]]
	reasons = placer.can_place(BuildCosts.PLANK, one, inventory)
	if ConstructionPlacer.OCCUPIED not in reasons or placer.place(BuildCosts.PLANK, one, inventory):
		printerr("FAIL construction_placer_plank: occupied gave %s" % [reasons])
		fail += 1
	# Bent L-shape refused (not a straight H/V run).
	var bent: Array[Vector2i] = []
	for cell in world.get_used_cells(0):
		var a: Vector2i = cell
		var b: Vector2i = cell + Vector2i.RIGHT
		var c: Vector2i = cell + Vector2i.RIGHT + Vector2i.DOWN
		var trip: Array[Vector2i] = [a, b, c]
		if trip.all(func(x: Vector2i) -> bool: return world.predict_cell(x)[0] == TileCatalog.WATER \
				and not world.has_bridge(x)):
			bent = trip
			break
	if bent.is_empty():
		printerr("FAIL construction_placer_plank: no L-shaped water triple on the chunk")
		fail += 1
	else:
		inventory.add(Inventory.WOOD, 3)
		reasons = placer.can_place(BuildCosts.PLANK, bent, inventory)
		if ConstructionPlacer.NOT_STRAIGHT not in reasons \
				or placer.place(BuildCosts.PLANK, bent, inventory):
			printerr("FAIL construction_placer_plank: bent gave %s" % [reasons])
			fail += 1
	# Floating water: a water cell with no land or plank neighbour.
	var floating := Vector2i(1 << 20, 0)
	for cell in world.get_used_cells(0):
		if world.predict_cell(cell)[0] != TileCatalog.WATER or world.has_bridge(cell):
			continue
		if ConstructionPlacer._neighbours(cell).any(func(n: Vector2i) -> bool:
				return land.call(n) or world.has_bridge(n)):
			continue
		floating = cell
		break
	if floating.x != 1 << 20:
		inventory.add(Inventory.WOOD, 1)
		var float_cells: Array[Vector2i] = [floating]
		reasons = placer.can_place(BuildCosts.PLANK, float_cells, inventory)
		if ConstructionPlacer.NOT_ADJACENT not in reasons \
				or placer.place(BuildCosts.PLANK, float_cells, inventory) \
				or world.has_bridge(floating):
			printerr("FAIL construction_placer_plank: floating gave %s, bridge %s"
					% [reasons, world.has_bridge(floating)])
			fail += 1
	else:
		printerr("FAIL construction_placer_plank: no floating water cell on the chunk")
		fail += 1
	# Multiplayer on: planks still place (#297); wood is spent.
	var peer := ENetMultiplayerPeer.new()
	var api := SceneMultiplayer.new()
	if peer.create_client("127.0.0.1", 1) != OK:
		printerr("FAIL construction_placer_plank: could not start an ENet client")
		fail += 1
	else:
		api.multiplayer_peer = peer
		set_multiplayer(api, scene.get_path())
		# Fresh water next to the existing bridge tip is adjacent via plank.
		var tip: Vector2i = water_run[water_run.size() - 1] + Vector2i.RIGHT
		if world.predict_cell(tip)[0] == TileCatalog.WATER and not world.has_bridge(tip):
			inventory.add(Inventory.WOOD, 1)
			var tip_cells: Array[Vector2i] = [tip]
			reasons = placer.can_place(BuildCosts.PLANK, tip_cells, inventory)
			var wood_before := inventory.count_of(Inventory.WOOD)
			if ConstructionPlacer.MULTIPLAYER_ON in reasons \
					or not reasons.is_empty() \
					or not placer.place(BuildCosts.PLANK, tip_cells, inventory) \
					or not world.has_bridge(tip) \
					or inventory.count_of(Inventory.WOOD) != wood_before - 1:
				printerr("FAIL construction_placer_plank: multiplayer plank gave %s, bridge %s, wood %d"
						% [reasons, world.has_bridge(tip), inventory.count_of(Inventory.WOOD)])
				fail += 1
		api.multiplayer_peer = null
		peer.close()
		set_multiplayer(null, scene.get_path())
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_placer_plank")
	return fail



func _test_construction_placer_atomic_spend() -> int:
	## place() must not leave a written run when the charge fails (#380 item 3).
	## An inventory stub reports enough wood for can_place, but spend always
	## fails; after place returns false the water cells must still be bare.
	## Time cost: about 0.1 s in tools/verify.sh (~1.8 s alone with
	## --only=construction_placer_atomic_spend, against ~1.7 s runner start-up).
	print("-- test_construction_placer_atomic_spend")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var stub: Inventory = (load("res://tests/mechanics/building/spend_fail_inventory.gd") as GDScript).new()
	scene.add_child(stub)
	var placer := ConstructionPlacer.new(world)
	var land := func(c: Vector2i) -> bool:
		return not world.has_bridge(c) and world.ground_is_walkable(world.predict_cell(c)[0])
	var water_run: Array[Vector2i] = []
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if not land.call(cell):
				continue
			var run: Array[Vector2i] = []
			for i in range(1, 4):
				var w: Vector2i = cell + Vector2i(i, 0)
				if world.predict_cell(w)[0] != TileCatalog.WATER or world.has_bridge(w):
					break
				run.append(w)
			if run.size() >= 2:
				water_run = run
				break
		if not water_run.is_empty():
			break
	if water_run.is_empty():
		printerr("FAIL construction_placer_atomic_spend: no 2+ water cells east of land")
		scene.queue_free()
		return 1
	stub.add(Inventory.WOOD, water_run.size())
	var reasons := placer.can_place(BuildCosts.PLANK, water_run, stub)
	var placed := placer.place(BuildCosts.PLANK, water_run, stub)
	var any_bridge := water_run.any(func(c: Vector2i) -> bool: return world.has_bridge(c))
	# Invariant: a failed place leaves no run written (charge and write are atomic).
	if not reasons.is_empty() or placed or any_bridge or stub.count_of(Inventory.WOOD) != water_run.size():
		printerr("FAIL construction_placer_atomic_spend: reasons %s, placed %s, bridge %s, wood %d"
				% [reasons, placed, any_bridge, stub.count_of(Inventory.WOOD)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_placer_atomic_spend")
	return fail


func _test_build_costs_spend_failed() -> int:
	## Spend runs before the writer (#380 item 3). A stub inventory whose
	## spend always fails returns spend failed and never calls the writer.
	## When the writer refuses after a real spend, the wood is put back.
	## Uses the scene tree so multiplayer_on has a MultiplayerAPI.
	## Time cost: about 0.15 s in tools/verify.sh (~1.8 s alone with --only=).
	print("-- test_build_costs_spend_failed")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var stub: Inventory = (load("res://tests/mechanics/building/spend_fail_inventory.gd") as GDScript).new()
	scene.add_child(stub)
	stub.add(Inventory.WOOD, 1)
	var called := [false]
	var why := BuildCosts.buy(stub, BuildCosts.PLANK, 1, func() -> bool:
		called[0] = true
		return true)
	if why != BuildCosts.SPEND_FAILED or called[0] or stub.count_of(Inventory.WOOD) != 1:
		printerr("FAIL build_costs_spend_failed: got '%s' called %s wood %d"
				% [why, called[0], stub.count_of(Inventory.WOOD)])
		fail += 1
	var inventory: Inventory = scene.get_node("Inventory")
	inventory.add(Inventory.WOOD, 1)
	why = BuildCosts.buy(inventory, BuildCosts.PLANK, 1, func() -> bool: return false)
	if why != BuildCosts.NOT_PLACED or inventory.count_of(Inventory.WOOD) != 1:
		printerr("FAIL build_costs_spend_failed: writer refuse got '%s' with %d wood"
				% [why, inventory.count_of(Inventory.WOOD)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_costs_spend_failed")
	return fail


func _shore_water_run(world, length: int) -> Array[Vector2i]:
	## A water run of `length` cells going east from land on the first seed
	## that has one near the origin; the land cell first. Empty when none.
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell: Vector2i in world.get_used_cells(0):
			if world.has_bridge(cell) or not world.ground_is_walkable(world.predict_cell(cell)[0]):
				continue
			var run: Array[Vector2i] = [cell]
			for i in range(1, length + 1):
				var w: Vector2i = cell + Vector2i(i, 0)
				if world.predict_cell(w)[0] != TileCatalog.WATER or world.has_bridge(w):
					break
				run.append(w)
			if run.size() == length + 1:
				return run
	return []


func _test_construction_placer_plank_occupied() -> int:
	## A plank cell under a player, a mob, a wall or a structure is refused as
	## occupied (#380 item 2): nothing is written and no wood is spent, and the
	## host's write_plank (peer requests, #297) refuses it too. Each case gets
	## a fresh map, so one case's result cannot hide another's.
	## Time cost: about 0.2 s in tools/verify.sh (~2.5 s alone with --only=,
	## against ~2.4 s runner start-up).
	print("-- test_construction_placer_plank_occupied")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var inventory: Inventory = scene.get_node("Inventory")
	inventory.add(Inventory.WOOD, 5)
	var placer := ConstructionPlacer.new(world)
	var tower := StructurePlacer.load_named(ConstructionPlacer.TOWER_STRUCTURE)
	var offset: Vector2i = StructurePlacer.footprint(tower, Vector2i.ZERO).keys()[0]
	for what in ["bare", "player", "mob", "wall", "structure"]:
		var run := _shore_water_run(world, 2)  # applies the params: no bridge, wall or structure
		if run.is_empty():
			printerr("FAIL construction_placer_plank_occupied: no 2 water cells east of land")
			fail += 1
			break
		var target: Array[Vector2i] = [run[1]]
		var at: Vector2 = world.to_global(world.map_to_local(run[1]))
		var occupier: Node = null
		match what:
			"player":
				occupier = load("res://Player/character_body_2d.tscn").instantiate()
				occupier.name = "occupier"
				occupier.global_position = at
				scene.get_node("World").add_child(occupier)
			"mob":
				occupier = load("res://Mobs/mob.tscn").instantiate()
				occupier.setup(MobCatalog.SLIME, at, 1)
				scene.get_node("World/Mobs").add_child(occupier)
			"wall":
				world.place_wall_cells(target)  # the writer itself does not check ground
			"structure":
				# A footprint over the cell, as a joining peer's list would put it.
				world.replace_structures([[ConstructionPlacer.TOWER_STRUCTURE, 1, run[1] - offset]])
				if not world._structures.has_cell(run[1]):
					printerr("FAIL construction_placer_plank_occupied: the test tower does not cover %s" % run[1])
					fail += 1
		var wood := inventory.count_of(Inventory.WOOD)
		var reasons: Array[String] = placer.can_place(BuildCosts.PLANK, target, inventory)
		if what == "bare":
			if not reasons.is_empty():
				printerr("FAIL construction_placer_plank_occupied: the bare cell is refused: %s" % [reasons])
				fail += 1
		else:
			var placed := placer.place(BuildCosts.PLANK, target, inventory)
			var written: Array[Vector2i] = placer.write_plank(target)
			if ConstructionPlacer.OCCUPIED not in reasons or placed or not written.is_empty() \
					or world.has_bridge(run[1]) or inventory.count_of(Inventory.WOOD) != wood:
				printerr("FAIL construction_placer_plank_occupied: %s gave %s, placed %s, host wrote %s, wood %d->%d"
						% [what, reasons, placed, written, wood, inventory.count_of(Inventory.WOOD)])
				fail += 1
		if occupier != null:
			occupier.get_parent().remove_child(occupier)
			occupier.free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_placer_plank_occupied")
	return fail


func _test_construction_writers_all_or_nothing() -> int:
	## The writer contract BuildCosts.buy relies on (#380 item 3, #381): a
	## writer that refuses writes nothing, so putting the wood back leaves the
	## map as it was. Checked for every registered writer: build_bridge with
	## land at the end of the run, place_wall_cells with one cell already a
	## wall, and place_structure on a refused anchor.
	## Time cost: about 0.1 s in tools/verify.sh (~2.4 s alone with --only=).
	print("-- test_construction_writers_all_or_nothing")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var run := _shore_water_run(world, 2)
	if run.is_empty():
		printerr("FAIL construction_writers_all_or_nothing: no 2 water cells east of land")
		scene.queue_free()
		return 1
	# Bridge: the last cell of the run is land, so the run is refused whole.
	if world.build_bridge(run[2], run[0]) or run.any(func(c: Vector2i) -> bool: return world.has_bridge(c)):
		printerr("FAIL construction_writers_all_or_nothing: bridge over %s wrote %s"
				% [run, run.map(func(c: Vector2i) -> bool: return world.has_bridge(c))])
		fail += 1
	# Wall: one cell of the run is already a wall.
	var land: Vector2i = run[0]
	var first: Array[Vector2i] = [land + Vector2i.UP]
	world.place_wall_cells(first)
	var cells: Array[Vector2i] = [land, land + Vector2i.UP, land + Vector2i.UP * 2]
	if world.place_wall_cells(cells) or world.has_wall(land) or world.has_wall(land + Vector2i.UP * 2):
		printerr("FAIL construction_writers_all_or_nothing: wall run %s wrote %s"
				% [cells, cells.map(func(c: Vector2i) -> bool: return world.has_wall(c))])
		fail += 1
	# Structure: a tower anchored on water is refused and writes no cell.
	var tower := StructurePlacer.load_named(ConstructionPlacer.TOWER_STRUCTURE)
	var before: int = world.placed_structures().size()
	var footprint: Dictionary = StructurePlacer.footprint(tower, run[2])
	if world.place_structure(tower, run[2], 1) != -1 or world.placed_structures().size() != before \
			or footprint.keys().any(func(c: Vector2i) -> bool: return world._structures.has_cell(c)):
		printerr("FAIL construction_writers_all_or_nothing: tower on water at %s was written" % run[2])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_writers_all_or_nothing")
	return fail
