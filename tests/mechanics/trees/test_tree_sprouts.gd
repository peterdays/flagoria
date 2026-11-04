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
	## player or a mob, on the spawn cell or the start castle's gate
	## (_spawn_and_gate), on a structure, on a plant or stump, on water, on a
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
	fail += _spawn_and_gate(world, sprouts, window)
	fail += _water_bridge_beach(world, sprouts)
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sprouts_skip_blocked_cells")
	return fail


func _water_bridge_beach(world, sprouts) -> int:
	## Biomes on, tree_min_alt -1: water, a bridge over it and beach sand
	## near the origin would each grow a tree by the noise, and none is a
	## candidate; and deficits there matches counted_deficits (bridge cells
	## are not land).
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
		if sprouts.deficits(window) != counted_deficits(world, window):
			printerr("FAIL sprouts_skip_blocked_cells: bridge at %s: deficits %s, counted %s"
					% [bridge[0], sprouts.deficits(window), counted_deficits(world, window)])
			return 1
		return 0
	printerr("FAIL sprouts_skip_blocked_cells: no area on seed 42 with water, a bridge and beach sand")
	return 1


static func counted_deficits(world, window: Rect2i) -> Dictionary:
	## TreeSprouts.deficits counted cell by cell over the whole window:
	## land (not water or a bridge), trees and tree stumps now, and the trees
	## the untouched map puts there, per biome.
	var land := {}
	var grown := {}
	var now := {}
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var cell := Vector2i(x, y)
			var p: Array = world.predict_cell(cell)
			if p[0] == TileCatalog.WATER or world._bridges.has_bridge(cell):
				continue
			var b: int = world.biome_at(cell)
			land[b] = land.get(b, 0) + 1
			var cuts = world._tree_cuts
			var stump: bool = cuts.has_cut(cell) and cuts.cut_type(cell).id != "bush"
			if p[1] in TREES or stump:
				now[b] = now.get(b, 0) + 1
			if _untouched_tree(world, cell, p, stump):
				grown[b] = grown.get(b, 0) + 1
	var out := {}
	for b in land:
		var missing: int = mini(floori(BiomeCatalog.tree_share(b) * land[b]), grown.get(b, 0)) - now.get(b, 0)
		if missing > 0:
			out[b] = missing
	return out


static func _untouched_tree(world, cell: Vector2i, p: Array, stump: bool) -> bool:
	if world._tree_cuts.sprouts.has(cell):
		return false
	if not world._structures.has_cell(cell):
		return stump or (p[1] in TREES and not world._tree_cuts.has_cut(cell))
	var b: int = world.biome_at(cell)
	var alt: float = world.cell_altitude(cell, b)
	var moist: float = world.moisture.get_noise_2d(cell.x, cell.y)
	var chance: float = world.items_chance.get_noise_2d(cell.x, cell.y)
	var ground: Vector2i = world.ground_tile(alt, moist, chance, b)
	if not world.ground_is_walkable(ground) or (world.biome_frequency > 0.0 and ground == TileCatalog.SAND):
		return false
	return world.plant_tile(alt, moist, chance, b) in TREES


func _test_sprout_deficits_match_count() -> int:
	## deficits, which reads the untouched map from per-square tables and
	## counts only changed cells, gives what counting every cell gives:
	## after a guard post on chopped trees, more chopped trees and bushes,
	## and a sprout pass, on windows off the square grid (a bridge:
	## _water_bridge_beach).
	print("-- test_sprout_deficits_match_count")
	var s := _scene()
	var world = s["world"]
	var fail := 0
	var sprouts = _sprouts_of(world, "sprout_deficits_match_count")
	var d := deficit_world(world, guard_post()) if sprouts != null else {}
	if d.is_empty():
		s["scene"].queue_free()
		await process_frame
		return 1
	var window: Rect2i = d["window"]
	var states := 0
	for step in 4:
		if step == 1:
			var chopped := 0
			for y in range(window.position.y, window.end.y, 7):
				for x in range(window.position.x, window.end.x, 5):
					if world.predict_cell(Vector2i(x, y))[1] != world.NO_PLANT and world.cut_grown(Vector2i(x, y)) != null:
						chopped += 1
			if chopped < 5:
				printerr("FAIL sprout_deficits_match_count: chopped only %d plants" % chopped)
				fail += 1
		elif step == 2:
			sprouts.sprout_pass(window, 1.0)
		elif step == 3:
			window = Rect2i(window.position + Vector2i(13, -5), window.size)
		for w: Rect2i in [window, Rect2i(window.position + Vector2i(3, 21), Vector2i(17, 40))]:
			states += 1
			var want := counted_deficits(world, w)
			var got: Dictionary = sprouts.deficits(w)
			if got != want:
				printerr("FAIL sprout_deficits_match_count: step %d window %s: deficits %s, counted %s" % [step, w, got, want])
				fail += 1
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sprout_deficits_match_count (%d windows, missing %s at first)" % [states, d["target"] - (d["before"] - d["lost"].size())])
	return fail


func _spawn_and_gate(world, sprouts, window: Rect2i) -> int:
	## No candidate on the spawn cell, the start castle's gate, or the cell
	## outside the gate (TileMap._castle_front), though each is a free cell.
	var free: Array = sprouts.candidates(window).get(BiomeCatalog.TEMPERATE, [])
	var front: Variant = null
	for c: Vector2i in free:
		if c - StartCastle.GATE_FRONT in free and not free[0] in [c, c - StartCastle.GATE_FRONT]:
			front = c
			break
	if front == null:
		printerr("FAIL sprouts_skip_blocked_cells: no free cell with a free cell above it in %s" % window)
		return 1
	var spawn: Vector2i = free[0]
	var gate: Vector2i = front - StartCastle.GATE_FRONT
	world.spawn_point = spawn
	world._castle_front = front
	free = sprouts.candidates(window).get(BiomeCatalog.TEMPERATE, [])
	world._castle_front = null
	var bad := [spawn, front, gate].filter(func(c: Vector2i) -> bool: return c in free)
	if not bad.is_empty():
		printerr("FAIL sprouts_skip_blocked_cells: spawn %s, gate %s or gate front %s is a candidate: %s"
				% [spawn, gate, front, bad])
		return 1
	print("   spawn %s, gate %s, gate front %s: no candidates" % [spawn, gate, front])
	return 0


func _test_sprout_pass_time() -> int:
	## No TreeSprouts.due call takes PASS_MS or more headless, called every
	## 0.25 s of play as TileMap does: on a map not counted yet until the
	## first pass sprouts, then with a second player and trees still missing
	## (the sprouts are taken out again), then walking 2 cells a call (40 a
	## pass, the fastest walk). Run with one guard post, then with 25 or more
	## (hundreds of trees missing), then with 12000 trees cut around them
	## too, where deficits still matches the full recount. One call may
	## reach SPIKE_MS, and a run that breaks the limits runs once more from
	## no counts, for a busy CI host.
	const PASS_MS := 4.0
	const SPIKE_MS := 6.0
	print("-- test_sprout_pass_time")
	var s := _scene()
	var world = s["world"]
	var sprouts = _sprouts_of(world, "sprout_pass_time")
	var d := deficit_world(world, guard_post()) if sprouts != null else {}
	var fail := 0 if not d.is_empty() else 1
	for stage: String in ["1 post", "posts", "cuts"] if not d.is_empty() else []:
		var label := stage
		if stage == "posts":
			label = "%d posts" % _crowd(world, d["window"])
			label += ", %d trees missing" % sprouts.deficits(d["window"]).values().reduce(func(a: int, b: int) -> int: return a + b, 0)
		elif stage == "cuts":
			label += " %d cut" % _cut_around(world, d["anchor"], 12000)
			if sprouts.deficits(d["window"]) != counted_deficits(world, d["window"]):
				printerr("FAIL sprout_pass_time: with %s, deficits %s, counted %s"
						% [label, sprouts.deficits(d["window"]), counted_deficits(world, d["window"])])
				fail += 1
		var run := []
		for attempt in 2:
			sprouts.clear()
			run = _time_due(s["scene"], world, sprouts, d["anchor"])
			if run[1] >= 0 and run[0][-1] < SPIKE_MS and run[0][-2] < PASS_MS:
				break
		if run[1] < 0 or run[0][-1] >= SPIKE_MS or run[0][-2] >= PASS_MS:
			printerr("FAIL sprout_pass_time: %s: first sprouts on call %d; slowest calls %s ms (limit %.1f, one up to %.1f), twice"
					% [label, run[1], run[0].slice(-5), PASS_MS, SPIKE_MS])
			fail += 1
		else:
			print("   %s: %d calls, first sprouts on call %d, slowest %s ms, %d sprouted"
					% [label, run[0].size(), run[1], run[0].slice(-3), run[2]])
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sprout_pass_time")
	return fail


func _crowd(world, window: Rect2i) -> int:
	## Guard posts every 3 cells across `window` where they fit once the
	## trees and bushes on the footprint are chopped. Returns how many.
	var placed := 0
	var post := guard_post()
	for y in range(window.position.y + 2, window.end.y - 6, 3):
		for x in range(window.position.x + 2, window.end.x - 6, 3):
			for c: Vector2i in StructurePlacer.footprint(post, Vector2i(x, y)):
				world.cut_grown(c)
			if world.place_structure(post, Vector2i(x, y), 1) > 0:
				placed += 1
	return placed


func _cut_around(world, centre: Vector2i, count: int) -> int:
	## Chop trees and bushes in rings around `centre` until `count` are cut.
	var cut := 0
	for r in 400:
		for k in range(-r, r + 1):
			for c: Vector2i in [Vector2i(k, -r), Vector2i(k, r), Vector2i(-r, k), Vector2i(r, k)]:
				if world.cut_grown(centre + c) != null:
					cut += 1
					if cut == count:
						return cut
	return cut


func _time_due(scene, world, sprouts, anchor: Vector2i) -> Array:
	## _test_sprout_pass_time's run from no counts: [call times sorted (ms),
	## call of the first sprouts or -1, cells sprouted].
	var players := []
	for at: Vector2i in [anchor, anchor + Vector2i(40, 12)]:
		players.append(load("res://Player/character_body_2d.tscn").instantiate())
		players[-1].name = str(players.size())
		players[-1].position = world.to_global(world.map_to_local(at))
	scene.get_node("World").add_child(players[0])
	world.regrow_delay = 5.0
	world.play_time = 0.0
	var times: Array[float] = []
	var sprouted := 0
	var first_pass := -1
	for i in 260:
		if i == first_pass + 1 and first_pass >= 0:
			scene.get_node("World").add_child(players[1])
		if i == first_pass + 60 and first_pass >= 0:
			players[1].free()
		if i >= first_pass + 60 and first_pass >= 0:
			players[0].position += world.global_scale * Vector2(32, 0)
		world.play_time += 0.25
		var t0 := Time.get_ticks_usec()
		var cells: Array = sprouts.due()
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		for c: Vector2i in cells:
			sprouts.erase(c)
			world._predict_cache.erase(c)
		sprouted += cells.size()
		if first_pass < 0 and not cells.is_empty():
			first_pass = i
		elif first_pass < 0 and i >= 120:
			break
	for p in players:
		if is_instance_valid(p):
			p.free()
	times.sort()
	return [times, first_pass, sprouted]
