extends "res://tests/helpers/test_helpers.gd"
## Biomes (Scripts/BiomeCatalog.gd) and their terrain, plants and structures.


func _test_biomes() -> int:
	## biome_frequency 0 keeps TEMPERATE and prior archipelago squares; frequency
	## > 0 yields multiple biomes and thins OCEANIC archipelago squares vs dense.
	print("-- test_biomes")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = _pre_biome_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	params.biome_seed = 31
	params.biome_frequency = 0.0
	params.archipelago_spacing = 64
	params.archipelago_island_radius = 16
	params.archipelago_jitter = 0.0
	params.island_falloff = 2.0
	world.apply_map_params(params)

	for cell in [Vector2i(0, 0), Vector2i(100, -50), Vector2i(-200, 300), Vector2i(40, 40)]:
		if world.biome_at(cell) != BiomeCatalog.TEMPERATE:
			printerr("FAIL biomes: frequency 0 should stay TEMPERATE at %s" % cell)
			fail += 1
	# Prior unbounded archipelago: distant squares stay active when biomes off.
	for sq in [Vector2i(0, 0), Vector2i(5, 5), Vector2i(-3, 2)]:
		if not world.archipelago_square_active(sq):
			printerr("FAIL biomes: frequency 0 dropped square %s" % sq)
			fail += 1

	params.biome_frequency = 0.003
	world.apply_map_params(params)
	var seen := {}
	for x in range(-400, 401, 40):
		for y in range(-400, 401, 40):
			seen[world.biome_at(Vector2i(x, y))] = true
	if seen.size() < 2:
		printerr("FAIL biomes: expected at least two biome ids, got %s" % seen.keys())
		fail += 1

	# Density: over many squares, OCEANIC keeps fewer than TEMPERATE/DENSE.
	var oceanic_active := 0
	var oceanic_total := 0
	var dense_active := 0
	var dense_total := 0
	for sx in range(-40, 41):
		for sy in range(-40, 41):
			var sq := Vector2i(sx, sy)
			var half: int = int(params.archipelago_spacing / 2)
			var centre_cell: Vector2i = sq * params.archipelago_spacing + Vector2i(half, half)
			var bid: int = world.biome_at(centre_cell)
			var active: bool = world.archipelago_square_active(sq)
			if bid == BiomeCatalog.OCEANIC:
				oceanic_total += 1
				if active:
					oceanic_active += 1
			elif bid == BiomeCatalog.ARCHIPELAGO_DENSE or bid == BiomeCatalog.TEMPERATE:
				dense_total += 1
				if active:
					dense_active += 1
	if oceanic_total < 5 or dense_total < 5:
		printerr(
			"FAIL biomes: not enough squares to compare density (oceanic=%s dense=%s)"
			% [oceanic_total, dense_total]
		)
		fail += 1
	else:
		var oceanic_rate := float(oceanic_active) / float(oceanic_total)
		var dense_rate := float(dense_active) / float(dense_total)
		if oceanic_rate >= dense_rate:
			printerr(
				"FAIL biomes: oceanic keep rate %s should be below dense/temperate %s"
				% [oceanic_rate, dense_rate]
			)
			fail += 1
	if not world.archipelago_square_active(Vector2i.ZERO):
		printerr("FAIL biomes: spawn square (0,0) must stay active")
		fail += 1

	if fail == 0:
		print(
			"PASS test_biomes biomes=%s oceanic=%s/%s dense=%s/%s"
			% [seen.keys(), oceanic_active, oceanic_total, dense_active, dense_total]
		)
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_biome_terrain() -> int:
	## Per-biome ground mix (BiomeCatalog.TERRAIN): with biome_frequency 0 the
	## map is unchanged (digests pinned before per-biome terrain existed); with
	## biomes on, beaches, swamps and flowers differ by biome, and beaches stay bare.
	print("-- test_biome_terrain")
	const FLOWER := Vector2i(9, 3)
	const NONE := Vector2i(-1, -1)
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	# Biomes off: whole chunks (ground, foliage, flowers) match the pinned output.
	var pinned := [
		[false, Vector2i(0, 0), "889d3ec826e36c7d1785deb1c6df496073fcf76cfc8f919b9c725db178d94a85"],
		[false, Vector2i(3000, -1500), "943071931c6c2264f5d5b0fbe4423363c2f6881646a833056134df4ae9da7e6c"],
		[true, Vector2i(0, 0), "84d0e789cb2058f807eb9b3fb877ad73a57ce660fe08cebb570d04dc82503687"],
		[true, Vector2i(3000, -1500), "15f85b7289577e289ab2b5686e0789d6dbe2b1f66f8e7b4d37c2658dba49f5c8"],
	]
	for pin in pinned:
		world.apply_map_params(_biome_terrain_params(pin[0]))
		world.generate_chunk(world.map_to_local(pin[1]))
		var got := _chunk_digest(world, pin[1], 96)
		if got != pin[2]:
			printerr("FAIL biome_terrain: frequency 0 archipelago=%s at %s changed (digest %s)" % [pin[0], pin[1], got])
			fail += 1
	# Biomes off: the biome id passed in is ignored.
	for b in BiomeCatalog.TERRAIN:
		for c in [[0.22, 0.5, 0.5], [0.24, 0.5, 0.5], [0.28, 0.5, 0.5], [0.5, -0.1, 0.5], [0.5, 0.1, -0.5]]:
			var want: Vector2i = world.ground_tile(c[0], c[1], c[2])
			if world.ground_tile(c[0], c[1], c[2], b) != want:
				printerr("FAIL biome_terrain: frequency 0 biome %s changed ground at %s" % [b, c])
				fail += 1

	# Biomes on: same altitude / moisture / chance, different ground per biome.
	var on := _biome_terrain_params(true)
	on.biome_frequency = 0.003
	world.apply_map_params(on)
	var T := BiomeCatalog.TEMPERATE
	# [name, alt, moist, chance, biome, expected tile]
	var cases := [
		["temperate_grass_above_beach", 0.28, 0.5, 0.5, T, TileCatalog.GRASS_C],
		["oceanic_wide_beach", 0.28, 0.5, 0.5, BiomeCatalog.OCEANIC, TileCatalog.SAND],
		["dense_wide_beach", 0.28, 0.5, 0.5, BiomeCatalog.ARCHIPELAGO_DENSE, TileCatalog.SAND],
		["temperate_beach", 0.24, 0.5, 0.5, T, TileCatalog.SAND],
		["continental_narrow_beach", 0.24, 0.5, 0.5, BiomeCatalog.CONTINENTAL, TileCatalog.GRASS_C],
		["temperate_swamp", 0.5, -0.1, 0.5, T, TileCatalog.SWAMP],
		["continental_dry", 0.5, -0.1, 0.5, BiomeCatalog.CONTINENTAL, TileCatalog.GRASS_C],
		["temperate_dry", 0.5, 0.1, 0.5, T, TileCatalog.GRASS_C],
		["dense_wet_swamp", 0.5, 0.1, 0.5, BiomeCatalog.ARCHIPELAGO_DENSE, TileCatalog.SWAMP],
	]
	for c in cases:
		var got: Vector2i = world.ground_tile(c[1], c[2], c[3], c[4])
		if got != c[5]:
			printerr("FAIL biome_terrain case=%s got %s want %s" % [c[0], got, c[5]])
			fail += 1

	# Flowers: density follows the biome; beaches stay bare when biomes are on.
	var ground := Vector2i(500, 500)
	var beach := Vector2i(502, 500)
	world.set_cell(0, ground, 0, TileCatalog.GRASS_A)
	world.set_cell(0, beach, 0, TileCatalog.SAND)
	# [name, cell, alt, chance, biome, expected layer-1, expected layer-2]
	var decor := [
		["temperate_no_flower", ground, 0.28, 0.2, T, NONE, NONE],
		["continental_meadow", ground, 0.28, 0.2, BiomeCatalog.CONTINENTAL, NONE, FLOWER],
		["temperate_flower", ground, 0.28, 0.5, T, NONE, FLOWER],
		# No flower; the bare cell gets OCEANIC stones (BiomeCatalog.STRUCTURES).
		["oceanic_sparse", ground, 0.28, 0.5, BiomeCatalog.OCEANIC, NONE, TileCatalog.STONES],
		["beach_no_plants", beach, 0.35, 0.9, T, NONE, NONE],
	]
	for d in decor:
		world.erase_cell(1, d[1])
		world.erase_cell(world.GROUND_DECOR_LAYER, d[1])
		world.set_tile_type_z1(d[1], d[2], 0.5, 0.0, d[3], d[4])
		var got1: Vector2i = world.get_cell_atlas_coords(1, d[1])
		var got2: Vector2i = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, d[1])
		if got1 != d[5] or got2 != d[6]:
			printerr("FAIL biome_terrain decor=%s got l1=%s l2=%s want %s %s" % [d[0], got1, got2, d[5], d[6]])
			fail += 1

	# Generated chunks use the same per-biome ground the render tool samples.
	var probe := Vector2i(700, -300)
	world.generate_chunk(world.map_to_local(probe))
	var mismatched := 0
	for x in range(probe.x - 48, probe.x + 48):
		for y in range(probe.y - 48, probe.y + 48):
			var cell := Vector2i(x, y)
			var b: int = world.biome_at(cell)
			var want: Vector2i = world.ground_tile(world.cell_altitude(cell, b),
				world.moisture.get_noise_2d(x, y), world.items_chance.get_noise_2d(x, y), b)
			if world.get_cell_atlas_coords(0, cell) != want:
				mismatched += 1
	if mismatched > 0:
		printerr("FAIL biome_terrain: %s generated cells differ from ground_tile" % mismatched)
		fail += 1

	# Over a wide area: swamp share of land is highest in ARCHIPELAGO_DENSE and
	# lowest in CONTINENTAL; sand share is highest in OCEANIC.
	var land := {}
	var swamp := {}
	var sand := {}
	for b in BiomeCatalog.TERRAIN:
		land[b] = 0
		swamp[b] = 0
		sand[b] = 0
	for x in range(-2048, 2048, 16):
		for y in range(-2048, 2048, 16):
			var cell := Vector2i(x, y)
			var b: int = world.biome_at(cell)
			var tile: Vector2i = world.ground_tile(world.cell_altitude(cell, b),
				world.moisture.get_noise_2d(x, y), world.items_chance.get_noise_2d(x, y), b)
			if tile == TileCatalog.WATER:
				continue
			land[b] += 1
			if tile == TileCatalog.SAND:
				sand[b] += 1
			elif tile == TileCatalog.SWAMP or tile == TileCatalog.SWAMP_SPECIAL:
				swamp[b] += 1
	var share := func(d: Dictionary, b: int) -> float: return float(d[b]) / maxf(1.0, float(land[b]))
	for b in land:
		if land[b] < 20:
			printerr("FAIL biome_terrain: biome %s has only %s land samples" % [b, land[b]])
			fail += 1
	var ocean := BiomeCatalog.OCEANIC
	var cont := BiomeCatalog.CONTINENTAL
	var dense := BiomeCatalog.ARCHIPELAGO_DENSE
	if not (share.call(swamp, dense) > share.call(swamp, T) and share.call(swamp, T) > share.call(swamp, cont)):
		printerr("FAIL biome_terrain: swamp shares dense=%s temperate=%s continental=%s" % [share.call(swamp, dense), share.call(swamp, T), share.call(swamp, cont)])
		fail += 1
	if not (share.call(sand, ocean) > share.call(sand, T) and share.call(sand, T) > share.call(sand, cont)):
		printerr("FAIL biome_terrain: sand shares oceanic=%s temperate=%s continental=%s" % [share.call(sand, ocean), share.call(sand, T), share.call(sand, cont)])
		fail += 1

	if fail == 0:
		print("PASS test_biome_terrain land=%s swamp=%s sand=%s" % [land, swamp, sand])
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_biome_plants() -> int:
	## Per-biome plant density (BiomeCatalog.PLANTS): with biome_frequency 0 the
	## biome id is ignored (whole-chunk digests are pinned in test_biome_terrain);
	## with biomes on, tree and bush density differ by biome.
	print("-- test_biome_plants")
	const NONE := Vector2i(-1, -1)
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	# Biomes off: the biome id passed in is ignored.
	world.apply_map_params(_biome_terrain_params(true))
	for b in BiomeCatalog.PLANTS:
		for alt in [0.28, 0.35, 0.5]:
			for chance in [-0.1, 0.1, 0.2, 0.4, 0.5]:
				var want: Vector2i = world.plant_tile(alt, 0.5, chance)
				if world.plant_tile(alt, 0.5, chance, b) != want:
					printerr("FAIL biome_plants: frequency 0 biome %s changed plant at alt=%s chance=%s" % [b, alt, chance])
					fail += 1
		# No pines with biomes off, even on dry high ground.
		if world.plant_tile(0.8, -0.1, 0.9, b) != NONE:
			printerr("FAIL biome_plants: frequency 0 biome %s grew a pine" % b)
			fail += 1
		# No bushy trees with biomes off, even on the wettest land.
		if world.plant_tile(0.8, 0.95, 0.9, b) != TileCatalog.TREE:
			printerr("FAIL biome_plants: frequency 0 biome %s grew a bushy tree" % b)
			fail += 1

	# Biomes on: same altitude / moisture / chance, different plant per biome.
	var on := _biome_terrain_params(true)
	on.biome_frequency = 0.003
	world.apply_map_params(on)
	var T := BiomeCatalog.TEMPERATE
	var ocean := BiomeCatalog.OCEANIC
	var cont := BiomeCatalog.CONTINENTAL
	var dense := BiomeCatalog.ARCHIPELAGO_DENSE
	# [name, alt, chance, biome, expected plant]
	var cases := [
		["temperate_no_tree", 0.5, 0.2, T, NONE],
		["continental_forest", 0.5, 0.2, cont, TileCatalog.TREE],
		["temperate_tree", 0.5, 0.4, T, TileCatalog.TREE],
		["oceanic_sparse_trees", 0.5, 0.4, ocean, NONE],
		["dense_sparse_trees", 0.5, 0.4, dense, NONE],
		["temperate_no_bush", 0.35, -0.1, T, NONE],
		["dense_scrub", 0.35, -0.1, dense, TileCatalog.BUSH],
		["temperate_bush", 0.35, 0.1, T, TileCatalog.BUSH],
		["oceanic_sparse_bushes", 0.35, 0.1, ocean, NONE],
	]
	for c in cases:
		var got: Vector2i = world.plant_tile(c[1], 0.4, c[2], c[3])
		if got != c[4]:
			printerr("FAIL biome_plants case=%s got %s want %s" % [c[0], got, c[4]])
			fail += 1
	# Pines: dry high ground only, never on swamp, per-biome chance.
	# [name, alt, moist, chance, biome, expected plant]
	var pine_cases := [
		["continental_pine", 0.6, -0.1, 0.1, cont, TileCatalog.PINE],
		["continental_pine_low", 0.45, -0.1, 0.9, cont, NONE],
		["continental_pine_wet_is_tree", 0.6, 0.1, 0.9, cont, TileCatalog.TREE],
		["continental_swamp_no_pine", 0.6, -0.3, 0.9, cont, NONE],
		["continental_pine_rare_chance", 0.6, -0.1, 0.0, cont, NONE],
		["oceanic_sparse_pines", 0.6, -0.1, 0.4, ocean, NONE],
		["oceanic_pine", 0.6, -0.1, 0.7, ocean, TileCatalog.PINE],
		["temperate_no_pine", 0.6, -0.1, 0.9, T, NONE],
		["dense_no_pine", 0.6, -0.1, 0.9, dense, NONE],
	]
	for c in pine_cases:
		var got: Vector2i = world.plant_tile(c[1], c[2], c[3], c[4])
		if got != c[5]:
			printerr("FAIL biome_plants case=%s got %s want %s" % [c[0], got, c[5]])
			fail += 1
	# Bushy trees: a tree cell on land wetter than bushy_tree_min_moist plus
	# the biome's bushy_moist; never in TEMPERATE (the biomes-off row).
	# [name, alt, moist, chance, biome, expected plant]
	var bushy_cases := [
		["continental_wet_bushy", 0.6, 0.6, 0.9, cont, TileCatalog.TREE_BUSHY],
		["continental_moist_oak", 0.6, 0.4, 0.9, cont, TileCatalog.TREE],
		["dense_bushy", 0.6, 0.2, 0.9, dense, TileCatalog.TREE_BUSHY],
		["oceanic_bushy", 0.6, 0.4, 0.9, ocean, TileCatalog.TREE_BUSHY],
		["oceanic_dry_oak", 0.6, 0.2, 0.9, ocean, TileCatalog.TREE],
		["temperate_no_bushy", 0.6, 0.95, 0.9, T, TileCatalog.TREE],
		["bushy_needs_tree_chance", 0.6, 0.6, 0.2, ocean, NONE],
	]
	for c in bushy_cases:
		var got: Vector2i = world.plant_tile(c[1], c[2], c[3], c[4])
		if got != c[5]:
			printerr("FAIL biome_plants case=%s got %s want %s" % [c[0], got, c[5]])
			fail += 1

	# Generated chunks place the plant that plant_tile picks (beaches stay bare).
	var probe := Vector2i(700, -300)
	world.generate_chunk(world.map_to_local(probe))
	var mismatched := 0
	var placed := 0
	for x in range(probe.x - 48, probe.x + 48):
		for y in range(probe.y - 48, probe.y + 48):
			var cell := Vector2i(x, y)
			var want: Vector2i = NONE
			if world.is_walkable_land(cell) and world.get_cell_atlas_coords(0, cell) != TileCatalog.SAND:
				var b: int = world.biome_at(cell)
				want = world.plant_tile(world.cell_altitude(cell, b),
					world.moisture.get_noise_2d(x, y), world.items_chance.get_noise_2d(x, y), b)
			var got: Vector2i = world.get_cell_atlas_coords(1, cell)
			if want == TileCatalog.FLOWER:
				got = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell)
			if got != want:
				mismatched += 1
			elif want != NONE:
				placed += 1
	if mismatched > 0 or placed == 0:
		printerr("FAIL biome_plants: %s generated cells differ from plant_tile (%s placed)" % [mismatched, placed])
		fail += 1

	# Over a wide area: tree share of land is highest in CONTINENTAL and lowest
	# in OCEANIC; bush share is highest in ARCHIPELAGO_DENSE and lowest in OCEANIC.
	var land := {}
	var trees := {}
	var bushes := {}
	var pines := {}
	var bushy := {}
	for b in BiomeCatalog.PLANTS:
		land[b] = 0
		trees[b] = 0
		bushes[b] = 0
		pines[b] = 0
		bushy[b] = 0
	for x in range(-2048, 2048, 16):
		for y in range(-2048, 2048, 16):
			var cell := Vector2i(x, y)
			var b: int = world.biome_at(cell)
			var alt: float = world.cell_altitude(cell, b)
			var moist: float = world.moisture.get_noise_2d(x, y)
			var chance: float = world.items_chance.get_noise_2d(x, y)
			var tile: Vector2i = world.ground_tile(alt, moist, chance, b)
			if tile == TileCatalog.WATER:
				continue
			land[b] += 1
			if tile == TileCatalog.SAND:
				continue
			var plant: Vector2i = world.plant_tile(alt, moist, chance, b)
			if plant == TileCatalog.TREE:
				trees[b] += 1
			elif plant == TileCatalog.BUSH:
				bushes[b] += 1
			elif plant == TileCatalog.PINE:
				pines[b] += 1
			elif plant == TileCatalog.TREE_BUSHY:
				bushy[b] += 1
	var share := func(d: Dictionary, b: int) -> float: return float(d[b]) / maxf(1.0, float(land[b]))
	for b in land:
		if land[b] < 20:
			printerr("FAIL biome_plants: biome %s has only %s land samples" % [b, land[b]])
			fail += 1
	if not (share.call(trees, cont) > share.call(trees, T) and share.call(trees, T) > share.call(trees, ocean)):
		printerr("FAIL biome_plants: tree shares continental=%s temperate=%s oceanic=%s" % [share.call(trees, cont), share.call(trees, T), share.call(trees, ocean)])
		fail += 1
	if not (share.call(bushes, dense) > share.call(bushes, T) and share.call(bushes, T) > share.call(bushes, ocean)):
		printerr("FAIL biome_plants: bush shares dense=%s temperate=%s oceanic=%s" % [share.call(bushes, dense), share.call(bushes, T), share.call(bushes, ocean)])
		fail += 1
	if not (share.call(pines, cont) > share.call(pines, ocean) and pines[T] == 0 and pines[dense] == 0):
		printerr("FAIL biome_plants: pine shares continental=%s oceanic=%s temperate=%s dense=%s" % [share.call(pines, cont), share.call(pines, ocean), share.call(pines, T), share.call(pines, dense)])
		fail += 1
	# Dense islands have too few trees in this sample to count bushy ones;
	# the point cases above cover them.
	if not (bushy[cont] > 0 and bushy[T] == 0):
		printerr("FAIL biome_plants: bushy trees continental=%s temperate=%s" % [bushy[cont], bushy[T]])
		fail += 1

	# A save from before pines and bushy trees (no pine_min_chance or
	# bushy_tree_min_moist) loads with both off, so
	# its world regenerates unchanged; a current save keeps both values.
	var older := on.duplicate_params()
	older.ensure_seeds()
	var data: Dictionary = older.to_dict()
	data.erase("pine_min_chance")
	data.erase("bushy_tree_min_moist")
	var path := MapSave.path_for("test_pre_pine_save")
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format_version": 1, "params": data}))
	file.close()
	var loaded = MapSave.load_map(path)
	DirAccess.remove_absolute(path)
	if loaded["error"] != "":
		printerr("FAIL biome_plants: pre-pine save error=%s" % loaded["error"])
		fail += 1
	else:
		world.apply_map_params(loaded["params"])
		if world.plant_tile(0.6, -0.1, 0.9, cont) != NONE:
			printerr("FAIL biome_plants: pre-pine save grew pines")
			fail += 1
		if world.plant_tile(0.6, 0.95, 0.9, cont) != TileCatalog.TREE:
			printerr("FAIL biome_plants: pre-bushy save grew bushy trees")
			fail += 1
	var saved = MapSave.save_map(older, "test_pine_save")
	var reloaded = MapSave.load_map(saved["path"])
	DirAccess.remove_absolute(saved["path"])
	if reloaded["error"] != "" or reloaded["params"].pine_min_chance != older.pine_min_chance \
			or reloaded["params"].bushy_tree_min_moist != older.bushy_tree_min_moist:
		printerr("FAIL biome_plants: pine save reloaded error=%s" % reloaded["error"])
		fail += 1

	if fail == 0:
		print("PASS test_biome_plants land=%s trees=%s bushes=%s pines=%s bushy=%s" % [land, trees, bushes, pines, bushy])
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_biome_structures() -> int:
	## Per-biome structures (BiomeCatalog.STRUCTURES): with biome_frequency 0
	## there are none (whole-chunk digests are pinned in test_biome_terrain);
	## with biomes on, OCEANIC and CONTINENTAL land without a plant, beaches
	## included, gets walkable stones on GROUND_DECOR_LAYER.
	print("-- test_biome_structures")
	const NONE := Vector2i(-1, -1)
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	# Stones never block movement.
	var src: TileSetAtlasSource = world.tile_set.get_source(TileCatalog.SOURCE_ID)
	if src.get_tile_data(TileCatalog.STONES, 0).get_collision_polygons_count(0) != 0:
		printerr("FAIL biome_structures: STONES has a collision polygon")
		fail += 1

	# Biomes off: no structures for any biome id.
	world.apply_map_params(_biome_terrain_params(true))
	for b in BiomeCatalog.STRUCTURES:
		for chance in [-0.5, 0.0, 0.4, 0.9]:
			if world.structure_tile(chance, b) != NONE:
				printerr("FAIL biome_structures: frequency 0 biome %s placed stones at chance=%s" % [b, chance])
				fail += 1

	var on := _biome_terrain_params(true)
	on.biome_frequency = 0.003
	world.apply_map_params(on)
	var T := BiomeCatalog.TEMPERATE
	var ocean := BiomeCatalog.OCEANIC
	var cont := BiomeCatalog.CONTINENTAL
	var dense := BiomeCatalog.ARCHIPELAGO_DENSE
	# [name, chance, biome, expected]
	var cases := [
		["temperate_none", 0.9, T, NONE],
		["dense_none", 0.9, dense, NONE],
		["oceanic_stones", 0.35, ocean, TileCatalog.STONES],
		["oceanic_below", 0.25, ocean, NONE],
		["continental_stones", 0.4, cont, TileCatalog.STONES],
		["continental_below", 0.3, cont, NONE],
	]
	for c in cases:
		var got: Vector2i = world.structure_tile(c[1], c[2])
		if got != c[3]:
			printerr("FAIL biome_structures case=%s got %s want %s" % [c[0], got, c[3]])
			fail += 1

	# Placement: plants take precedence, beaches and dry land get stones.
	var ground := Vector2i(600, 600)
	var beach := Vector2i(602, 600)
	world.set_cell(0, ground, 0, TileCatalog.GRASS_A)
	world.set_cell(0, beach, 0, TileCatalog.SAND)
	# [name, cell, alt, moist, chance, biome, expected layer-1, expected layer-2]
	var decor := [
		["oceanic_bush_first", ground, 0.35, 0.5, 0.9, ocean, TileCatalog.BUSH, NONE],
		["oceanic_dry_stones", ground, 0.35, -0.5, 0.5, ocean, NONE, TileCatalog.STONES],
		["oceanic_beach_stones", beach, 0.35, 0.5, 0.9, ocean, NONE, TileCatalog.STONES],
		["temperate_dry_bare", ground, 0.35, -0.5, 0.9, T, NONE, NONE],
		["continental_flower_first", ground, 0.28, 0.5, 0.5, cont, NONE, TileCatalog.FLOWER],
	]
	for d in decor:
		world.erase_cell(1, d[1])
		world.erase_cell(world.GROUND_DECOR_LAYER, d[1])
		world.set_tile_type_z1(d[1], d[2], d[3], 0.0, d[4], d[5])
		var got1: Vector2i = world.get_cell_atlas_coords(1, d[1])
		var got2: Vector2i = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, d[1])
		if got1 != d[6] or got2 != d[7]:
			printerr("FAIL biome_structures decor=%s got l1=%s l2=%s want %s %s" % [d[0], got1, got2, d[6], d[7]])
			fail += 1

	# Over a wide area: stone share of land is highest in OCEANIC, then
	# CONTINENTAL; TEMPERATE and ARCHIPELAGO_DENSE have none.
	var land := {}
	var stones := {}
	for b in BiomeCatalog.STRUCTURES:
		land[b] = 0
		stones[b] = 0
	for x in range(-2048, 2048, 16):
		for y in range(-2048, 2048, 16):
			var cell := Vector2i(x, y)
			var b: int = world.biome_at(cell)
			var alt: float = world.cell_altitude(cell, b)
			var moist: float = world.moisture.get_noise_2d(x, y)
			var chance: float = world.items_chance.get_noise_2d(x, y)
			var tile: Vector2i = world.ground_tile(alt, moist, chance, b)
			if tile == TileCatalog.WATER:
				continue
			land[b] += 1
			var plant: Vector2i = NONE
			if tile != TileCatalog.SAND:
				plant = world.plant_tile(alt, moist, chance, b)
			if plant == NONE and world.structure_tile(chance, b) == TileCatalog.STONES:
				stones[b] += 1
	var share := func(b: int) -> float: return float(stones[b]) / maxf(1.0, float(land[b]))
	for b in land:
		if land[b] < 20:
			printerr("FAIL biome_structures: biome %s has only %s land samples" % [b, land[b]])
			fail += 1
	if not (share.call(ocean) > share.call(cont) and share.call(cont) > 0.0 and stones[T] == 0 and stones[dense] == 0):
		printerr("FAIL biome_structures: stone shares oceanic=%s continental=%s temperate=%s dense=%s" % [share.call(ocean), share.call(cont), share.call(T), share.call(dense)])
		fail += 1

	if fail == 0:
		print("PASS test_biome_structures land=%s stones=%s" % [land, stones])
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_new_world_biomes_on() -> int:
	## A new world has biomes on: default params give a world with every biome
	## in a wide area. A map save written before biomes existed (no
	## biome_frequency) still loads with biomes off, so it regenerates unchanged.
	print("-- test_new_world_biomes_on")
	var fail := 0
	var params := MapGenParams.make_defaults()
	if params.biome_frequency <= 0.0:
		printerr("FAIL new_world_biomes_on: default biome_frequency=%s" % params.biome_frequency)
		fail += 1
	params.altitude_seed = 11
	params.moisture_seed = 12
	params.temperature_seed = 13
	params.items_seed = 14
	params.biome_seed = 15
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	world.apply_map_params(params)
	var seen := {}
	for x in range(-2048, 2048, 64):
		for y in range(-2048, 2048, 64):
			seen[world.biome_at(Vector2i(x, y))] = true
	scene.queue_free()
	for b in [BiomeCatalog.OCEANIC, BiomeCatalog.TEMPERATE, BiomeCatalog.CONTINENTAL, BiomeCatalog.ARCHIPELAGO_DENSE]:
		if not seen.has(b):
			printerr("FAIL new_world_biomes_on: biome %s missing from a 4096-tile area" % b)
			fail += 1

	var legacy := _pre_biome_defaults()
	legacy.biome_frequency = 0.01
	legacy.ensure_seeds()
	var data: Dictionary = legacy.to_dict()
	data.erase("biome_frequency")
	var path := MapSave.path_for("test_pre_biome_save")
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format_version": 1, "params": data}))  # saves from before biomes are version 1
	file.close()
	var loaded = MapSave.load_map(path)
	DirAccess.remove_absolute(path)
	if loaded["error"] != "" or loaded["params"].biome_frequency != 0.0:
		printerr("FAIL new_world_biomes_on: pre-biome save loaded error=%s biome_frequency=%s" % [loaded["error"], loaded["params"].biome_frequency if loaded["params"] else null])
		fail += 1

	var current := MapGenParams.make_defaults()
	current.ensure_seeds()
	var saved = MapSave.save_map(current, "test_biome_save")
	var reloaded = MapSave.load_map(saved["path"])
	DirAccess.remove_absolute(saved["path"])
	if reloaded["error"] != "" or reloaded["params"].biome_frequency != current.biome_frequency:
		printerr("FAIL new_world_biomes_on: biome save reloaded error=%s" % reloaded["error"])
		fail += 1
	if fail == 0:
		print("PASS test_new_world_biomes_on (%s biomes seen)" % seen.size())
	return fail
