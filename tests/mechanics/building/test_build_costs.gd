extends "res://tests/helpers/test_helpers.gd"
## Wood costs for building (#272): the cost table, Inventory.spend and
## BuildCosts.buy.


func _test_build_cost_table() -> int:
	## A plank costs 1 wood, a wall block 2, a tower 10 and the starting castle
	## 0; costs scale with units. A removal gives back half the total cost,
	## rounded down. An unknown kind has no cost and no refund.
	print("-- test_build_cost_table")
	var fail := 0
	var want := {
		[BuildCosts.PLANK, 1]: [1, 0], [BuildCosts.PLANK, 4]: [4, 2],
		[BuildCosts.WALL_BLOCK, 1]: [2, 1], [BuildCosts.WALL_BLOCK, 3]: [6, 3],
		[BuildCosts.TOWER, 1]: [10, 5], [BuildCosts.START_CASTLE, 1]: [0, 0],
		[&"moat", 1]: [-1, 0],
	}
	for k in want:
		var got := [BuildCosts.cost(k[0], k[1]), BuildCosts.refund(k[0], k[1])]
		if got != want[k]:
			printerr("FAIL build_cost_table: %s x%d cost, refund %s, want %s" % [k[0], k[1], got, want[k]])
			fail += 1
	if BuildCosts.REFUND_SHARE != 0.5:
		printerr("FAIL build_cost_table: refund share %s, want 0.5" % BuildCosts.REFUND_SHARE)
		fail += 1
	if fail == 0:
		print("PASS test_build_cost_table")
	return fail


func _test_inventory_spend() -> int:
	## spend takes wood and emits changed when there is enough; with too
	## little, or a negative amount, it takes nothing and emits nothing.
	print("-- test_inventory_spend")
	var fail := 0
	var inventory := Inventory.new()
	var seen := []
	inventory.changed.connect(func(r: StringName, c: int) -> void: seen.append([r, c]))
	inventory.add(Inventory.WOOD, 5)
	seen.clear()
	var steps := [[3, true, 2], [3, false, 2], [-1, false, 2], [2, true, 0], [0, true, 0]]
	for s in steps:
		var ok := inventory.spend(Inventory.WOOD, s[0])
		if ok != s[1] or inventory.count_of(Inventory.WOOD) != s[2]:
			printerr("FAIL inventory_spend: spend %d gave %s with %d left, want %s with %d"
					% [s[0], ok, inventory.count_of(Inventory.WOOD), s[1], s[2]])
			fail += 1
	if seen != [[Inventory.WOOD, 2], [Inventory.WOOD, 0], [Inventory.WOOD, 0]]:
		printerr("FAIL inventory_spend: changed emitted %s" % [seen])
		fail += 1
	inventory.free()
	if fail == 0:
		print("PASS test_inventory_spend")
	return fail


func _test_build_costs_buy() -> int:
	## In the main scene, buying a 3-plank bridge with 2 wood is refused: no
	## planks and still 2 wood. With 3 wood it lays the planks and leaves 0.
	## A placement the writer refuses (planks already there) spends nothing.
	## The starting castle is bought with no wood. While multiplayer is on,
	## a wall buy spends and writes; the starting castle still refuses.
	print("-- test_build_costs_buy")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var inventory: Inventory = scene.get_node("Inventory")
	var start := Vector2i(1 << 20, 0)
	for s in [11, 42, 7, 1, 99]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if range(3).all(func(i: int) -> bool: return world.predict_cell(cell + Vector2i(i, 0))[0] == TileCatalog.WATER):
				start = cell
				break
		if start.x != 1 << 20:
			break
	if start.x == 1 << 20:
		printerr("FAIL build_costs_buy: no 3-cell water row near the origin on any seed")
		scene.queue_free()
		return 1
	var run_end := start + Vector2i(2, 0)
	var bridge := func() -> bool: return world.build_bridge(start, run_end)
	inventory.add(Inventory.WOOD, 2)
	var why := BuildCosts.buy(inventory, BuildCosts.PLANK, 3, bridge)
	if why != BuildCosts.NOT_ENOUGH_WOOD or inventory.count_of(Inventory.WOOD) != 2 or world.has_bridge(start):
		printerr("FAIL build_costs_buy: 2 wood for 3 planks gave '%s', %d wood, bridge %s"
				% [why, inventory.count_of(Inventory.WOOD), world.has_bridge(start)])
		fail += 1
	inventory.add(Inventory.WOOD, 1)
	why = BuildCosts.buy(inventory, BuildCosts.PLANK, 3, bridge)
	if why != "" or inventory.count_of(Inventory.WOOD) != 0 or not world.has_bridge(start) or not world.has_bridge(run_end):
		printerr("FAIL build_costs_buy: 3 wood for 3 planks gave '%s', %d wood, bridge %s"
				% [why, inventory.count_of(Inventory.WOOD), world.has_bridge(start)])
		fail += 1
	inventory.add(Inventory.WOOD, 3)
	why = BuildCosts.buy(inventory, BuildCosts.PLANK, 3, bridge)
	if why != BuildCosts.NOT_PLACED or inventory.count_of(Inventory.WOOD) != 3:
		printerr("FAIL build_costs_buy: planks on planks gave '%s', %d wood" % [why, inventory.count_of(Inventory.WOOD)])
		fail += 1
	inventory.spend(Inventory.WOOD, 3)
	world.apply_map_params(_spawn_params(42, 0.0))
	why = BuildCosts.buy(inventory, BuildCosts.START_CASTLE, 1, func() -> bool: return world.place_start_castle(1))
	if why != "" or inventory.count_of(Inventory.WOOD) != 0 or world.placed_structures().size() != 1:
		printerr("FAIL build_costs_buy: castle with 0 wood gave '%s', %d wood, %d placed"
				% [why, inventory.count_of(Inventory.WOOD), world.placed_structures().size()])
		fail += 1
	# A client still connecting counts as multiplayer on.
	var peer := ENetMultiplayerPeer.new()
	var api := SceneMultiplayer.new()
	if peer.create_client("127.0.0.1", 1) != OK:
		printerr("FAIL build_costs_buy: could not start an ENet client")
		fail += 1
	else:
		api.multiplayer_peer = peer
		set_multiplayer(api, scene.get_path())
		inventory.add(Inventory.WOOD, 10)
		var called := [false]
		why = BuildCosts.buy(inventory, BuildCosts.START_CASTLE, 1, func() -> bool:
			called[0] = true
			return true)
		if why != BuildCosts.MULTIPLAYER_ON or called[0] or inventory.count_of(Inventory.WOOD) != 10:
			printerr("FAIL build_costs_buy: castle multiplayer on gave '%s', placed %s, %d wood"
					% [why, called[0], inventory.count_of(Inventory.WOOD)])
			fail += 1
		called[0] = false
		why = BuildCosts.buy(inventory, BuildCosts.WALL_BLOCK, 1, func() -> bool:
			called[0] = true
			return true)
		if why != "" or not called[0] or inventory.count_of(Inventory.WOOD) != 8:
			printerr("FAIL build_costs_buy: wall multiplayer on gave '%s', placed %s, %d wood"
					% [why, called[0], inventory.count_of(Inventory.WOOD)])
			fail += 1
		api.multiplayer_peer = null
		peer.close()
		set_multiplayer(null, scene.get_path())
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_costs_buy")
	return fail
