extends "res://tests/helpers/test_helpers.gd"
## Shared construction placement (#296): plank runs through ConstructionPlacer.


func _test_construction_placer_plank() -> int:
	## A straight plank run on water that touches land places and spends one
	## wood per cell. Too little wood places and spends nothing. Land, an
	## existing plank, a bent run and a floating water cell (no land or plank
	## next to it) are refused with a reason. While multiplayer is on, place
	## refuses. Time cost: about 0.4 s in tools/verify.sh (~2.0 s alone with
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
	# Multiplayer on refuses.
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
			if ConstructionPlacer.MULTIPLAYER_ON not in reasons \
					or placer.place(BuildCosts.PLANK, tip_cells, inventory) \
					or world.has_bridge(tip):
				printerr("FAIL construction_placer_plank: multiplayer gave %s" % [reasons])
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
