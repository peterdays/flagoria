extends "res://tests/helpers/test_helpers.gd"
## Trees that sprout on free cells up to the biome's target tree share
## (#361, TreeSprouts). A guard post built on chopped trees takes them away
## for good; trees sprout back on free cells of the area until it holds the
## smaller of BiomeCatalog.TREE_SHARE of its land and what the map generates
## there, and never on a blocked cell.

const TREES: Array[Vector2i] = [TileCatalog.TREE, TileCatalog.TREE_BUSHY, TileCatalog.PINE]
## guard_post cells (from its top-left) with sand ground and no object: only
## the structure guard keeps a sprout off them.
const OPEN_CELLS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(3, 2)]


static func guard_post() -> Structure:
	return Structure.parse(FileAccess.get_file_as_string("res://structures/guard_post.txt"))["structure"]


static func window_at(world, cell: Vector2i) -> Rect2i:
	## The area TreeSprouts.due counts around `cell`: 3 chunks a side
	## (TreeSprouts.AREA_CHUNKS).
	var size := Vector2i(world.chunk_width, world.chunk_height) * 3
	return Rect2i(cell - size / 2, size)


static func trees_in(world, window: Rect2i) -> int:
	## Trees, bushy trees and pines predict_cell puts in `window`.
	var n := 0
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			if world.predict_cell(Vector2i(x, y))[1] in TREES:
				n += 1
	return n


static func share_target(world, window: Rect2i) -> int:
	## TREE_SHARE of the window's land (biomes off: one biome), rounded down.
	var land := 0
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			if world.predict_cell(Vector2i(x, y))[0] != TileCatalog.WATER:
				land += 1
	var shares: Dictionary = (load("res://Scripts/BiomeCatalog.gd") as GDScript).get_script_constant_map().get("TREE_SHARE", {})
	return floori(shares.get(BiomeCatalog.TEMPERATE, 0.0) * land)


static func target_in(world, window: Rect2i) -> int:
	## The smaller of share_target and the trees the window generates,
	## counted on the untouched map.
	return mini(share_target(world, window), trees_in(world, window))


static func deficit_world(world, s: Structure, dense := false) -> Dictionary:
	## On the first of a few biome-off seeds, a guard post near the origin
	## built on at least 2 chopped trees, one of them on an open cell, in an
	## area that then holds fewer trees than its target. Returns {anchor,
	## window, target, lost, before, top_left, params} or {} when none is found.
	## `dense`: instead, an area that still holds its share_target after the
	## loss, so it is short of what it generates but not of its share.
	for sv in [11, 42, 99, 7, 3]:
		var params := _static_params(sv)
		world.apply_map_params(params)
		for r in range(0, 96 if dense else 48, 3):
			for dy in range(-r, r + 1, 3):
				for dx in range(-r, r + 1, 3):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var found := _try_anchor(world, s, Vector2i(dx, dy), dense)
					if not found.is_empty():
						found["params"] = params
						return found
	return {}


static func _try_anchor(world, s: Structure, anchor: Vector2i, dense := false, centre: Variant = null) -> Dictionary:
	## `centre`: count the area around that cell instead of around `anchor`.
	var top_left: Vector2i = anchor - s.anchor
	var trees: Array[Vector2i] = []
	var open_tree := false
	for cell: Vector2i in StructurePlacer.footprint(s, anchor):
		var p: Array = world.predict_cell(cell)
		if p[1] in TREES:
			trees.append(cell)
			open_tree = open_tree or (cell - top_left) in OPEN_CELLS
		elif not world.predicted_clear(cell):
			return {}
	if trees.size() < 2 or not open_tree:
		return {}
	var window := window_at(world, anchor if centre == null else centre)
	var target := target_in(world, window)
	var before := trees_in(world, window)
	if dense and share_target(world, window) > before - trees.size():
		return {}
	if not dense and target - (before - trees.size()) < 2:
		return {}
	for cell in trees:
		world.cut_grown(cell)
	if world.place_structure(s, anchor, 1) <= 0:
		return {}
	return {"anchor": anchor, "window": window, "target": target, "lost": trees, "before": before,
			"top_left": top_left}


static func _static_params(sv: int) -> MapGenParams:
	var params := MapGenParams.make_defaults()
	params.biome_frequency = 0.0
	for key in ["altitude_seed", "moisture_seed", "temperature_seed", "items_seed", "biome_seed"]:
		params.set(key, sv)
	return params


func _scene() -> Dictionary:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	return {"scene": scene, "world": world}


func _sprouts_of(world, label: String) -> Variant:
	if not "sprouts" in world._tree_cuts:
		printerr("FAIL %s: the map has no tree sprouts (TreeCuts.sprouts)" % label)
		return null
	return world._tree_cuts.sprouts


func _test_sprouts_stop_at_target() -> int:
	## An area that lost trees for good under a guard post: one sprout pass
	## at chance 1 sprouts exactly the missing trees, up to the target, and
	## more passes add none, and an area still at its share after a loss
	## sprouts none. A sprouted tree can be chopped and regrows as
	## itself; its stump counts, so nothing sprouts for it meanwhile. The
	## sprouts survive a save round trip.
	print("-- test_sprouts_stop_at_target")
	var s := _scene()
	var world = s["world"]
	var fail := 0
	var sprouts = _sprouts_of(world, "sprouts_stop_at_target")
	var d := deficit_world(world, guard_post()) if sprouts != null else {}
	if sprouts == null or d.is_empty():
		if sprouts != null:
			printerr("FAIL sprouts_stop_at_target: no guard post spot that leaves an area short of trees")
		s["scene"].queue_free()
		await process_frame
		return 1
	var window: Rect2i = d["window"]
	var missing: int = d["target"] - trees_in(world, window)
	var first: Array = sprouts.sprout_pass(window, 1.0)
	if first.size() != missing or trees_in(world, window) != d["target"]:
		printerr("FAIL sprouts_stop_at_target: %d trees missing, %d sprouted, the area holds %d trees, target %d"
				% [missing, first.size(), trees_in(world, window), d["target"]])
		fail += 1
	var more := 0
	for i in 20:
		more += sprouts.sprout_pass(window, 1.0).size()
	if more != 0 or trees_in(world, window) != d["target"]:
		printerr("FAIL sprouts_stop_at_target: 20 more passes sprouted %d past the target" % more)
		fail += 1
	if not first.is_empty():
		var cell: Vector2i = first[0]
		var tree: Vector2i = world.predict_cell(cell)[1]
		world.play_time = 100.0
		world.regrow_delay = 30.0
		if world.cut_grown(cell) == null or not sprouts.sprout_pass(window, 1.0).is_empty():
			printerr("FAIL sprouts_stop_at_target: a chopped sprout at %s was made up for while its stump stands" % cell)
			fail += 1
		world.play_time = 200.0
		if world.regrow_due() != 1 or world.predict_cell(cell)[1] != tree:
			printerr("FAIL sprouts_stop_at_target: the chopped sprout at %s regrew as %s, want %s"
					% [cell, world.predict_cell(cell)[1], tree])
			fail += 1
	# A save round trip keeps every sprout.
	var saved = JSON.parse_string(JSON.stringify(world.cut_changes()))
	var held := {}
	for cell in first:
		held[cell] = world.predict_cell(cell)[1]
	world.apply_map_params(d["params"])
	world.restore_cuts(saved)
	for cell in held:
		if world.predict_cell(cell)[1] != held[cell]:
			printerr("FAIL sprouts_stop_at_target: after a save round trip %s is %s, want %s (save %s)"
					% [cell, world.predict_cell(cell)[1], held[cell], saved])
			fail += 1
			break
	# An area that lost trees but still holds its share sprouts none.
	var dense := deficit_world(world, guard_post(), true)
	var extra: Array = [] if dense.is_empty() else sprouts.sprout_pass(dense["window"], 1.0)
	if dense.is_empty() or not extra.is_empty():
		printerr("FAIL sprouts_stop_at_target: an area above its share after a loss: found %s, sprouted %d"
				% [not dense.is_empty(), extra.size()])
		fail += 1
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sprouts_stop_at_target (%d trees, target %d, %d lost, %d sprouted)"
				% [d["before"], d["target"], d["lost"].size(), first.size()])
	return fail


func _test_sprouts_skip_blocked_cells() -> int:
	## Where an area is short of trees, no free-cell candidate is under a
	## player or a mob, on a structure, on a plant or stump, on water, on a
	## bridge, or on a beach with biomes on, though the map would grow a tree
	## on each such cell (sprout_tile). Water, bridge and beach are checked
	## with tree_min_alt lowered, so the noise alone would put trees there.
	print("-- test_sprouts_skip_blocked_cells")
	var s := _scene()
	var world = s["world"]
	var scene = s["scene"]
	var fail := 0
	var sprouts = _sprouts_of(world, "sprouts_skip_blocked_cells")
	var d := deficit_world(world, guard_post()) if sprouts != null else {}
	if sprouts == null or d.is_empty():
		scene.queue_free()
		await process_frame
		return 1
	var window: Rect2i = d["window"]
	var free: Array = sprouts.candidates(window).get(BiomeCatalog.TEMPERATE, [])
	var open: Array = OPEN_CELLS.map(func(c: Vector2i) -> Vector2i: return d["top_left"] + c) \
			.filter(func(c: Vector2i) -> bool: return sprouts.sprout_tile(c) != world.NO_PLANT)
	if open.is_empty() or open.any(func(c: Vector2i) -> bool: return c in free):
		printerr("FAIL sprouts_skip_blocked_cells: guard post cells %s (trees there before) are candidates" % [open])
		fail += 1
	var plants: Array = []
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var c := Vector2i(x, y)
			if world.predict_cell(c)[1] in TREES:
				plants.append(c)
	var outside := plants[0] as Vector2i
	world.cut_grown(outside)
	free = sprouts.candidates(window).get(BiomeCatalog.TEMPERATE, [])
	if plants.size() < 2 or plants.any(func(c: Vector2i) -> bool: return c in free):
		printerr("FAIL sprouts_skip_blocked_cells: a tree or the stump %s is a candidate" % outside)
		fail += 1
	if free.size() < 2:
		printerr("FAIL sprouts_skip_blocked_cells: only %d free cells in %s" % [free.size(), window])
		scene.queue_free()
		await process_frame
		return fail + 1
	# A player and a mob each standing on a free cell.
	var at_player: Vector2i = free[0]
	var at_mob: Vector2i = free[free.size() - 1]
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = "1"
	player.position = world.to_global(world.map_to_local(at_player))
	scene.get_node("World").add_child(player)
	var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
	mob.setup(MobCatalog.SLIME, world.to_global(world.map_to_local(at_mob)), 1)
	scene.get_node("World/Mobs").add_child(mob)
	mob.set_physics_process(false)
	free = sprouts.candidates(window).get(BiomeCatalog.TEMPERATE, [])
	if at_player in free or at_mob in free:
		printerr("FAIL sprouts_skip_blocked_cells: a cell under the player (%s) or a mob (%s) is a candidate"
				% [at_player in free, at_mob in free])
		fail += 1
	player.queue_free()
	mob.queue_free()
	fail += _water_bridge_beach(world, sprouts)
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sprouts_skip_blocked_cells")
	return fail


func _water_bridge_beach(world, sprouts) -> int:
	## Biomes on, tree_min_alt -1: water, a bridge over it and beach sand
	## near the origin would each grow a tree by the noise, and none is a
	## candidate.
	var params := _static_params(42)
	params.biome_frequency = 0.003
	params.tree_min_alt = -1.0
	for r in range(0, 400, 32):
		world.apply_map_params(params)
		var window := window_at(world, Vector2i(r, 0))
		var water: Array[Vector2i] = []
		var sand: Array[Vector2i] = []
		for y in range(window.position.y, window.end.y):
			for x in range(window.position.x, window.end.x):
				var c := Vector2i(x, y)
				var g: Vector2i = world.predict_cell(c)[0]
				if sprouts.sprout_tile(c) == world.NO_PLANT:
					continue
				if g == TileCatalog.WATER:
					water.append(c)
				elif g == TileCatalog.SAND:
					sand.append(c)
		var bridge: Array[Vector2i] = []
		for c in water:
			if c + Vector2i.RIGHT in water and world.build_bridge(c, c + Vector2i.RIGHT):
				bridge = [c, c + Vector2i.RIGHT]
				break
		if water.size() < 3 or sand.is_empty() or bridge.is_empty():
			continue
		var free := {}
		for cells in sprouts.candidates(window).values():
			for c in cells:
				free[c] = true
		var bad := []
		for c in water + sand:
			if free.has(c):
				bad.append([c, world.predict_cell(c)])
		if free.is_empty() or not bad.is_empty():
			printerr("FAIL sprouts_skip_blocked_cells: %d candidates; water, bridge or beach cells among them: %s"
					% [free.size(), bad])
			return 1
		return 0
	printerr("FAIL sprouts_skip_blocked_cells: no area on seed 42 with water, a bridge and beach sand")
	return 1
