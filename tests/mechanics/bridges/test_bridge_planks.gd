extends "res://tests/helpers/test_helpers.gd"
## Plank bridges over water.


func _test_bridge_planks() -> int:
	## build_bridge lays one straight run of planks over generated water, with
	## land joints at the ends that touch land and tips elsewhere. The planks
	## stay when the chunk is drawn again, predict_cell sees them, they are no
	## mob home and grow no plants, the hero walks across them while plain
	## water still blocks, and a new map clears them. Land, bent runs and
	## cells that already have planks are refused.
	print("-- test_bridge_planks")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var piece := func(n: String) -> Vector2i:
		return TileCatalog.TILES["BRIDGE_PLANK_%s_WATER" % n]["atlas"]
	var want := {
		[3, true, true, true]: ["H_START", "H", "H_END"],
		[1, true, true, true]: ["H_SINGLE"],
		[2, false, false, false]: ["V_TIP_N", "V_TIP_S"],
		[3, true, true, false]: ["H_START", "H", "H_TIP_E"],
		[2, false, false, true]: ["V_TIP_N", "V_END"],
	}
	for k in want:
		var got: Array[Vector2i] = world.bridge_pieces(k[0], k[1], k[2], k[3])
		var names: Array = want[k].map(piece)
		if got != Array(names, TYPE_VECTOR2I, "", null):
			printerr("FAIL bridge_planks: pieces %s got %s, want %s" % [k, got, want[k]])
			fail += 1
	# A row of 2..6 water cells near the origin with land at both ends.
	var run_start := Vector2i(1 << 20, 0)
	var run_len := 0
	var seed_value := 0
	var land := func(c: Vector2i) -> bool:
		return world.ground_is_walkable(world.predict_cell(c)[0])
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if not land.call(cell) or world.predict_cell(cell + Vector2i.RIGHT)[0] != TileCatalog.WATER:
				continue
			var n := 1
			while n <= 6 and world.predict_cell(cell + Vector2i(n + 1, 0))[0] == TileCatalog.WATER:
				n += 1
			if n >= 2 and n <= 6 and land.call(cell + Vector2i(n + 1, 0)) \
					and world.get_cell_source_id(0, cell + Vector2i(n + 1, 0)) != -1:
				run_start = cell + Vector2i.RIGHT
				run_len = n
				break
		if run_len > 0:
			seed_value = s
			break
	if run_len == 0:
		printerr("FAIL bridge_planks: no short water gap between land near the origin on any seed")
		scene.queue_free()
		return fail + 1
	var run_end := run_start + Vector2i(run_len - 1, 0)
	if world.build_bridge(run_start - Vector2i.RIGHT, run_end) or world.build_bridge(run_start, run_end + Vector2i.DOWN):
		printerr("FAIL bridge_planks: a run onto land or a bent run was accepted")
		fail += 1
	if not world.build_bridge(run_end, run_start) or world.build_bridge(run_start, run_start):
		printerr("FAIL bridge_planks: build_bridge %s..%s did not build exactly once" % [run_start, run_end])
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	var pieces: Array[Vector2i] = world.bridge_pieces(run_len, true, true, true)
	for i in run_len:
		var c := run_start + Vector2i(i, 0)
		if world.get_cell_atlas_coords(0, c) != pieces[i] or world.predict_cell(c) != [pieces[i], world.NO_PLANT]:
			printerr("FAIL bridge_planks: %s drawn %s predicted %s, want %s" % [
				c, world.get_cell_atlas_coords(0, c), world.predict_cell(c), pieces[i]])
			fail += 1
		if not world.is_walkable_land(c) or world.get_cell_source_id(1, c) != -1 \
				or world.get_cell_source_id(world.GROUND_DECOR_LAYER, c) != -1:
			printerr("FAIL bridge_planks: %s is not bare walkable ground" % c)
			fail += 1
		if MobSpawner.is_home_cell(world, c, MobCatalog.HOME_SAND) or MobSpawner.is_home_cell(world, c, MobCatalog.HOME_GRASS):
			printerr("FAIL bridge_planks: %s is a mob home" % c)
			fail += 1
	# The hero's body walks the whole bridge; the water row next to it blocks.
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	scene.get_node("World").add_child(player)
	var free_row := func(row: Vector2i) -> bool:
		player.global_position = world.to_global(world.map_to_local(row - Vector2i.RIGHT))
		return player.move_and_collide(Vector2(16.0 * (run_len + 1), 0), true) == null
	await physics_frame
	await physics_frame
	if not free_row.call(run_start):
		printerr("FAIL bridge_planks: the hero cannot walk across the bridge")
		fail += 1
	var blocked := 0
	for side in [Vector2i.UP, Vector2i.DOWN]:
		if world.predict_cell(run_start + side)[0] == TileCatalog.WATER:
			blocked += 0 if free_row.call(run_start + side) else 1
		else:
			blocked += 1  # land there; nothing to check
	if blocked != 2 or world.predict_cell(run_start + Vector2i.DOWN)[0] != TileCatalog.WATER \
			and world.predict_cell(run_start + Vector2i.UP)[0] != TileCatalog.WATER:
		printerr("FAIL bridge_planks: the hero walks over plain water next to the bridge, or no water there")
		fail += 1
	player.queue_free()
	world.apply_map_params(_spawn_params(seed_value, 0.0))
	world.generate_chunk(Vector2(0, 0))
	if world.get_cell_atlas_coords(0, run_start) != TileCatalog.WATER:
		printerr("FAIL bridge_planks: a new map kept the bridge at %s" % run_start)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_bridge_planks (seed %s, %s cells at %s)" % [seed_value, run_len, run_start])
	return fail


func _test_bridge_joins() -> int:
	## Two placements that meet become one deck (#416): plain planks across the
	## old end, rope only on walkable ground, a tip only on open water. Removing
	## the continuation puts the tip back; placing it again joins the deck.
	## A one-cell side branch does not turn the longer run. Land, a diagonal,
	## an occupied cell and a floating cell stay refused. Time cost: about
	## 0.5 s in tools/verify.sh (~2.2 s for --only=bridge_joins,bridge_planks,
	## against ~1.7 s of runner start-up).
	print("-- test_bridge_joins")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var gap: Array[Vector2i] = []
	var plus: Array[Vector2i] = []
	var vertical: Array[Vector2i] = []
	var floating := Vector2i(1 << 20, 0)
	var seed_value := 0
	for s in [11, 42, 7, 1, 99, 3, 5, 13, 17, 23]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		gap = _gap_between_land(world, Vector2i.RIGHT, 4, 8)
		vertical = _gap_between_land(world, Vector2i.DOWN, 4, 6)
		plus = _open_plus(world)
		floating = _floating_water(world, gap, plus)
		if not gap.is_empty() and not plus.is_empty() and floating.x != 1 << 20:
			seed_value = s
			break
	if gap.is_empty() or plus.is_empty() or floating.x == 1 << 20:
		printerr("FAIL bridge_joins: no shore gap, open plus and floating water on the origin chunk")
		scene.queue_free()
		return 1
	# Side branch on a longer straight run, away from the shore gap.
	var row: Array[Vector2i] = [plus[0], plus[1], plus[2]]
	var branch: Array[Vector2i] = [plus[3]]
	if not world.build_bridge(row[0], row[2]):
		printerr("FAIL bridge_joins: plus row refused")
		fail += 1
	else:
		var alone: Array = _joined_keys(3, true, false, false)
		fail += _keys_match(world, row, alone, "plus alone")
		if not world.build_bridge(plus[3], plus[3]):
			printerr("FAIL bridge_joins: side branch refused")
			fail += 1
		else:
			fail += _keys_match(world, row, alone, "plus with branch")
			var branch_key := _plank_key(world.get_cell_atlas_coords(0, plus[3]))
			if branch_key != "V_TIP_S":
				printerr("FAIL bridge_joins: branch %s want V_TIP_S" % branch_key)
				fail += 1
			if not world._bridges.erase_cells(branch) or world.has_bridge(plus[3]) \
					or world.get_cell_atlas_coords(0, plus[3]) != TileCatalog.WATER:
				printerr("FAIL bridge_joins: branch erase left %s" % _plank_key(world.get_cell_atlas_coords(0, plus[3])))
				fail += 1
			fail += _keys_match(world, row, alone, "plus after branch erase")
		if world._bridges.erase_cells(branch):
			printerr("FAIL bridge_joins: erasing a missing branch returned true")
			fail += 1
		var gone: Array[Vector2i] = row.duplicate()
		if not world._bridges.erase_cells(gone):
			printerr("FAIL bridge_joins: plus row did not erase")
			fail += 1
	# Shore gap: three planks, then the cells that continue them to the far land.
	var first: Array[Vector2i] = [gap[0], gap[1], gap[2]]
	var rest: Array[Vector2i] = []
	for i in range(3, gap.size()):
		rest.append(gap[i])
	var land_cell := gap[0] + Vector2i.LEFT
	if world.build_bridge(land_cell, gap[0]) or world.build_bridge(gap[0], gap[0] + Vector2i.DOWN + Vector2i.RIGHT):
		printerr("FAIL bridge_joins: a run onto land or a diagonal was accepted")
		fail += 1
	if not world.build_bridge(first[0], first[2]) or world.build_bridge(first[0], first[2]):
		printerr("FAIL bridge_joins: the first three planks did not build exactly once")
		fail += 1
	fail += _keys_match(world, first, _joined_keys(3, true, true, false), "separate")
	var inventory: Inventory = scene.get_node("Inventory")
	inventory.add(Inventory.WOOD, 8)
	var placer := ConstructionPlacer.new(world)
	var why: Array[String] = placer.can_place(BuildCosts.PLANK, rest, inventory)
	var land_why: Array[String] = placer.can_place(BuildCosts.PLANK, [land_cell], inventory)
	var occupied_why: Array[String] = placer.can_place(BuildCosts.PLANK, [first[0]], inventory)
	var float_why: Array[String] = placer.can_place(BuildCosts.PLANK, [floating], inventory)
	if not why.is_empty() or ConstructionPlacer.WRONG_GROUND not in land_why \
			or ConstructionPlacer.OCCUPIED not in occupied_why \
			or ConstructionPlacer.NOT_ADJACENT not in float_why:
		printerr("FAIL bridge_joins: support changed rest %s land %s occupied %s float %s"
				% [why, land_why, occupied_why, float_why])
		fail += 1
	if not world.build_bridge(rest[0], rest[rest.size() - 1]):
		printerr("FAIL bridge_joins: continuation refused")
		fail += 1
	var deck: Array = _joined_keys(gap.size(), true, true, true)
	fail += _keys_match(world, gap, deck, "joined")
	world.generate_chunk(Vector2(0, 0))
	fail += _keys_match(world, gap, deck, "redraw")
	if not world._bridges.erase_cells(rest):
		printerr("FAIL bridge_joins: continuation erase failed")
		fail += 1
	fail += _keys_match(world, first, _joined_keys(3, true, true, false), "removed")
	for c in rest:
		if world.has_bridge(c) or world.get_cell_atlas_coords(0, c) != TileCatalog.WATER:
			printerr("FAIL bridge_joins: removed %s is %s bridge %s" % [c, world.get_cell_atlas_coords(0, c), world.has_bridge(c)])
			fail += 1
	if not world.build_bridge(rest[0], rest[rest.size() - 1]):
		printerr("FAIL bridge_joins: rejoin refused")
		fail += 1
	fail += _keys_match(world, gap, deck, "rejoined")
	var middle: Array[Vector2i] = [gap[2]]
	if not world._bridges.erase_cells(middle):
		printerr("FAIL bridge_joins: middle erase failed")
		fail += 1
	if _plank_key(world._bridges.piece(gap[1])) != "H_TIP_E" or world.has_bridge(gap[2]) \
			or world.get_cell_atlas_coords(0, gap[2]) != TileCatalog.WATER:
		printerr("FAIL bridge_joins: gap at the old end left %s / %s"
				% [_plank_key(world._bridges.piece(gap[1])), world.get_cell_atlas_coords(0, gap[2])])
		fail += 1
	if gap.size() == 4:
		if _plank_key(world._bridges.piece(gap[3])) != "H_END":
			printerr("FAIL bridge_joins: far shore after the gap is %s" % _plank_key(world._bridges.piece(gap[3])))
			fail += 1
	elif _plank_key(world._bridges.piece(gap[3])) != "H_TIP_W" \
			or _plank_key(world._bridges.piece(gap[gap.size() - 1])) != "H_END":
		printerr("FAIL bridge_joins: cells past the gap are %s .. %s"
				% [_plank_key(world._bridges.piece(gap[3])), _plank_key(world._bridges.piece(gap[gap.size() - 1]))])
		fail += 1
	if not world.build_bridge(gap[2], gap[2]):
		printerr("FAIL bridge_joins: middle rejoin refused")
		fail += 1
	fail += _keys_match(world, gap, deck, "middle rejoined")
	if not vertical.is_empty() and not _shares(vertical, gap) and not _shares(vertical, plus):
		var vfirst: Array[Vector2i] = [vertical[0], vertical[1], vertical[2]]
		var vrest: Array[Vector2i] = []
		for i in range(3, vertical.size()):
			vrest.append(vertical[i])
		if world.build_bridge(vfirst[0], vfirst[2]) and world.build_bridge(vrest[0], vrest[vrest.size() - 1]):
			fail += _keys_match(world, vertical, _joined_keys(vertical.size(), false, true, true), "vertical joined")
			if world._bridges.erase_cells(vrest):
				fail += _keys_match(world, vfirst, _joined_keys(3, false, true, false), "vertical removed")
		else:
			printerr("FAIL bridge_joins: vertical run refused")
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_bridge_joins (seed %s, gap %s at %s)" % [seed_value, gap.size(), gap[0]])
	return fail


func _plank_key(atlas: Vector2i) -> String:
	for tile_name: String in TileCatalog.TILES:
		if tile_name.begins_with("BRIDGE_PLANK_") and tile_name.ends_with("_WATER") \
				and TileCatalog.TILES[tile_name]["atlas"] == atlas:
			return tile_name.trim_prefix("BRIDGE_PLANK_").trim_suffix("_WATER")
	return ""


func _keys_match(world, cells: Array[Vector2i], keys: Array, label: String) -> int:
	var fail := 0
	for i in cells.size():
		var drawn := _plank_key(world.get_cell_atlas_coords(0, cells[i]))
		var stored := _plank_key(world._bridges.piece(cells[i])) if world.has_bridge(cells[i]) else ""
		if drawn != str(keys[i]) or stored != str(keys[i]):
			printerr("FAIL bridge_joins: %s %s drawn %s stored %s want %s" % [label, cells[i], drawn, stored, keys[i]])
			fail += 1
	return fail


func _joined_keys(n: int, horizontal: bool, land_before: bool, land_after: bool) -> Array:
	var axis := "H" if horizontal else "V"
	var tip_far := "_TIP_E" if horizontal else "_TIP_S"
	var tip_near := "_TIP_W" if horizontal else "_TIP_N"
	var keys: Array = []
	for i in n:
		var key := axis
		if i == 0 and i == n - 1 and land_before and land_after:
			key = axis + "_SINGLE"
		elif i == 0 and land_before:
			key = axis + "_START"
		elif i == n - 1 and land_after:
			key = axis + "_END"
		elif i == n - 1:
			key = axis + tip_far
		elif i == 0:
			key = axis + tip_near
		keys.append(key)
	return keys


func _gap_between_land(world, step: Vector2i, min_n: int, max_n: int) -> Array[Vector2i]:
	## Shortest drawn water run of min_n..max_n cells with walkable ground at
	## both ends. Empty when the chunk has none.
	var land := func(c: Vector2i) -> bool:
		return not world.has_bridge(c) and world.ground_is_walkable(world.predict_cell(c)[0])
	var best: Array[Vector2i] = []
	for cell in world.get_used_cells(0):
		if not land.call(cell):
			continue
		var run: Array[Vector2i] = []
		for i in range(1, max_n + 1):
			var w: Vector2i = cell + step * i
			if world.get_cell_source_id(0, w) == -1 or world.predict_cell(w)[0] != TileCatalog.WATER \
					or world.has_bridge(w):
				break
			run.append(w)
		if run.size() < min_n or not land.call(cell + step * (run.size() + 1)):
			continue
		if world.get_cell_source_id(0, cell + step * (run.size() + 1)) == -1:
			continue
		if best.is_empty() or run.size() < best.size():
			best = run
	return best


func _open_plus(world) -> Array[Vector2i]:
	## Three water cells west to east, plus the water cell south of the middle,
	## whose south side is not walkable ground. Empty when the chunk has none.
	for cell in world.get_used_cells(0):
		var row := [cell, cell + Vector2i.RIGHT, cell + Vector2i(2, 0)]
		var south: Vector2i = row[1] + Vector2i.DOWN
		var open := true
		for w in row:
			if world.get_cell_source_id(0, w) == -1 or world.predict_cell(w)[0] != TileCatalog.WATER:
				open = false
				break
		if not open or world.get_cell_source_id(0, south) == -1 \
				or world.predict_cell(south)[0] != TileCatalog.WATER:
			continue
		var past: Vector2i = south + Vector2i.DOWN
		if world.ground_is_walkable(world.predict_cell(past)[0]):
			continue
		if world.ground_is_walkable(world.predict_cell(row[0] + Vector2i.LEFT)[0]) \
				or world.ground_is_walkable(world.predict_cell(row[2] + Vector2i.RIGHT)[0]):
			continue
		return [row[0], row[1], row[2], south]
	return []


func _floating_water(world, gap: Array[Vector2i], plus: Array[Vector2i]) -> Vector2i:
	## Water with no land or plank neighbour, also clear of the runs this test
	## places so the continuation does not turn it into a supported cell.
	var land := func(c: Vector2i) -> bool:
		return not world.has_bridge(c) and world.ground_is_walkable(world.predict_cell(c)[0])
	for cell in world.get_used_cells(0):
		if world.predict_cell(cell)[0] != TileCatalog.WATER or world.has_bridge(cell):
			continue
		if _near(cell, gap) or _near(cell, plus):
			continue
		var touched := false
		for n in [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
			if land.call(n) or world.has_bridge(n):
				touched = true
				break
		if not touched:
			return cell
	return Vector2i(1 << 20, 0)


func _near(cell: Vector2i, cells: Array[Vector2i]) -> bool:
	for c in cells:
		if absi(c.x - cell.x) + absi(c.y - cell.y) <= 1:
			return true
	return false


func _shares(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for c in a:
		if c in b:
			return true
	return false
