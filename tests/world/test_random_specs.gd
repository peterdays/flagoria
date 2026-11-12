extends "res://tests/helpers/test_helpers.gd"
## Random specs (#335): playable ranges and playable maps.


const N_SPECS := 8  ## stated for Done-when; keep verify time modest
const BASE_SEED := 487_000  ## fixed RNG seed base so each spec reproduces in verify (#487)
const BIOME_SAMPLE := 1024  ## half-width; step 16 ≈ light BIOME_COVERAGE pass
const BIOME_STEP := 16
const LAND_SAMPLE := 14  ## within a default 32-wide chunk


func _in_range(value: float, key: String) -> bool:
	var r: Array = MapGenParams.PLAYABLE_RANGES[key]
	return value >= r[0] - 0.0001 and value <= r[1] + 0.0001


func _assert_ranges(p: MapGenParams, label: String) -> int:
	var fail := 0
	for key in ["altitude_frequency", "moisture_frequency", "temperature_frequency",
			"items_frequency", "biome_frequency", "biome_edge", "fractal_lacunarity",
			"fractal_gain", "island_falloff", "archipelago_jitter", "bush_min_chance",
			"tree_min_chance", "flower_min_chance", "pine_min_alt", "pine_min_moist",
			"pine_min_chance", "bushy_tree_min_moist", "swamp_bush_min_chance"]:
		if not _in_range(p.get(key), key):
			printerr("FAIL %s %s=%s out of PLAYABLE_RANGES" % [label, key, p.get(key)])
			fail += 1
	if p.fractal_octaves < 3 or p.fractal_octaves > 7:
		printerr("FAIL %s fractal_octaves=%s" % [label, p.fractal_octaves])
		fail += 1
	if not _in_range(p.water_max_alt, "water_max_alt"):
		printerr("FAIL %s water_max_alt=%s" % [label, p.water_max_alt])
		fail += 1
	if p.sand_max_alt <= p.water_max_alt or p.swamp_special_alt <= p.sand_max_alt:
		printerr("FAIL %s alt order water=%s sand=%s swamp=%s"
				% [label, p.water_max_alt, p.sand_max_alt, p.swamp_special_alt])
		fail += 1
	if p.bush_min_alt >= p.bush_max_alt or p.flower_min_alt >= p.flower_max_alt:
		printerr("FAIL %s foliage order flower=%s..%s bush=%s..%s"
				% [label, p.flower_min_alt, p.flower_max_alt, p.bush_min_alt, p.bush_max_alt])
		fail += 1
	if p.ground_chance_a >= p.ground_chance_b or p.ground_chance_b >= p.ground_chance_c:
		printerr("FAIL %s ground chances %s %s %s"
				% [label, p.ground_chance_a, p.ground_chance_b, p.ground_chance_c])
		fail += 1
	if p.island_radius != 0 and not _in_range(p.island_radius, "island_radius"):
		printerr("FAIL %s island_radius=%s" % [label, p.island_radius])
		fail += 1
	if p.archipelago_spacing != 0 and not _in_range(p.archipelago_spacing, "archipelago_spacing"):
		printerr("FAIL %s archipelago_spacing=%s" % [label, p.archipelago_spacing])
		fail += 1
	if p.island_radius > 0 and p.archipelago_spacing > 0:
		printerr("FAIL %s both island and archipelago on" % label)
		fail += 1
	for skip in MapGenParams.RANDOM_SPECS_SKIP:
		# Compared against defaults after randomize from a known baseline in the test.
		pass
	return fail


func _count_land(world, around: Vector2 = Vector2.ZERO, half: int = LAND_SAMPLE) -> int:
	var origin: Vector2i = world.local_to_map(around)
	var n := 0
	for x in range(origin.x - half, origin.x + half):
		for y in range(origin.y - half, origin.y + half):
			if world.is_walkable_land(Vector2i(x, y)):
				n += 1
	return n


func _biomes_present(world) -> Array:
	var seen := {}
	var half := BIOME_SAMPLE
	for x in range(-half, half, BIOME_STEP):
		for y in range(-half, half, BIOME_STEP):
			seen[world.biome_at(Vector2i(x, y))] = true
	return seen.keys()


func _shape_mode_label(p: MapGenParams) -> String:
	if p.island_radius > 0:
		return "island"
	if p.archipelago_spacing > 0:
		return "archipelago"
	return "open"


func _noise_type_label(t: int) -> String:
	match t:
		FastNoiseLite.TYPE_VALUE:
			return "VALUE"
		FastNoiseLite.TYPE_VALUE_CUBIC:
			return "VALUE_CUBIC"
		FastNoiseLite.TYPE_SIMPLEX:
			return "SIMPLEX"
		FastNoiseLite.TYPE_SIMPLEX_SMOOTH:
			return "SIMPLEX_SMOOTH"
		_:
			return str(t)


func _print_spec_failure(p: MapGenParams, rng_seed: int, label: String) -> void:
	printerr(
		"FAIL %s reproducibility: rng_seed=%s (repro: seed(%s) then randomize_specs); "
		+ "shape=%s noise_type=%s water_max_alt=%s sand_max_alt=%s "
		+ "island_radius=%s island_falloff=%s archipelago_spacing=%s "
		+ "archipelago_island_radius=%s archipelago_jitter=%s "
		+ "archipelago_world_extent=%s archipelago_island_count=%s"
		% [
			label,
			rng_seed,
			rng_seed,
			_shape_mode_label(p),
			_noise_type_label(p.noise_type),
			p.water_max_alt,
			p.sand_max_alt,
			p.island_radius,
			p.island_falloff,
			p.archipelago_spacing,
			p.archipelago_island_radius,
			p.archipelago_jitter,
			p.archipelago_world_extent,
			p.archipelago_island_count,
		]
	)


func _test_random_specs_playable() -> int:
	## N_SPECS random specs: each property in PLAYABLE_RANGES, land > 0, a
	## SpawnFinder spawn, archipelago maps have land on an island centre,
	## biomes-on maps show every biome (coverage like BIOME_COVERAGE_OK).
	## Time cost: ~2–4 s in verify (~3 s alone with --only=; N=8 × one chunk).
	print("-- test_random_specs_playable")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var chunk_w0 := 0
	var chunk_h0 := 0
	var chunk_f0 := 0
	for i in N_SPECS:
		var rng_seed := BASE_SEED + i
		seed(rng_seed)
		var p := MapGenParams.make_defaults()
		chunk_w0 = p.chunk_width
		chunk_h0 = p.chunk_height
		chunk_f0 = p.chunk_refresh_frames
		p.randomize_specs()
		var label := "spec %s" % i
		var spec_fail := 0
		spec_fail += _assert_ranges(p, label)
		if p.chunk_width != chunk_w0 or p.chunk_height != chunk_h0 or p.chunk_refresh_frames != chunk_f0:
			printerr("FAIL %s changed chunk_* to %s %s %s"
					% [label, p.chunk_width, p.chunk_height, p.chunk_refresh_frames])
			spec_fail += 1
		world.apply_map_params(p)
		if p.biome_frequency > 0.0:
			var present: Array = _biomes_present(world)
			for b in [BiomeCatalog.OCEANIC, BiomeCatalog.TEMPERATE,
					BiomeCatalog.CONTINENTAL, BiomeCatalog.ARCHIPELAGO_DENSE]:
				if not present.has(b):
					printerr("FAIL %s missing biome %s (have %s)" % [label, b, present])
					spec_fail += 1
		var gen_at := Vector2.ZERO
		if p.archipelago_spacing > 0:
			# Jittered island centre of the spawn square, not the geometric mid-cell.
			var centre: Vector2 = world.archipelago_centre(Vector2i(0, 0))
			gen_at = world.map_to_local(Vector2i(int(centre.x), int(centre.y)))
		world.generate_chunk(gen_at)
		await physics_frame
		var land := _count_land(world, gen_at)
		if land <= 0:
			printerr("FAIL %s land=%s" % [label, land])
			spec_fail += 1
		else:
			var spawn: Vector2i = SpawnFinder.resolve_player_spawn(world)
			if not world.is_clear_ground(spawn) and not world.is_walkable_land(spawn):
				printerr("FAIL %s spawn %s not walkable/clear" % [label, spawn])
				spec_fail += 1
		if spec_fail > 0:
			_print_spec_failure(p, rng_seed, label)
		fail += spec_fail
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_random_specs_playable (N=%s)" % N_SPECS)
	return fail


func _test_random_seed_unchanged_by_specs_contract() -> int:
	## Random seeds still only changes seeds; Random specs changes more.
	## Time cost: ~0.05 s in verify.
	print("-- test_random_seed_unchanged_by_specs_contract")
	var fail := 0
	var p := MapGenParams.make_defaults()
	var before := p.to_dict()
	p.randomize_seeds()
	for key in before.keys():
		if key.ends_with("_seed"):
			continue
		if p.get(key) != before[key]:
			printerr("FAIL random_seed changed non-seed %s" % key)
			fail += 1
	var p2 := MapGenParams.make_defaults()
	var water0: float = p2.water_max_alt
	# Force a different water by looping until it moves (almost always).
	var moved := false
	for i in 20:
		p2.randomize_specs()
		if absf(p2.water_max_alt - water0) > 0.001 or p2.island_radius != 0 or p2.archipelago_spacing != 0:
			moved = true
			break
	if not moved:
		printerr("FAIL random_specs did not change shape/water in 20 tries")
		fail += 1
	if fail == 0:
		print("PASS test_random_seed_unchanged_by_specs_contract")
	return fail


func _test_random_specs_panel_button() -> int:
	## The panel has a Random specs button that fills fields from randomize_specs.
	## Time cost: ~0.2 s in verify.
	print("-- test_random_specs_panel_button")
	var fail := 0
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var btn: Button = panel.get_node_or_null("Margin/VBox/Buttons/RandomSpecs")
	if btn == null or btn.text != "Random specs":
		printerr("FAIL random_specs_panel_button missing RandomSpecs button")
		fail += 1
	else:
		var params: MapGenParams = root.get_node("MapGen").params
		var before_water: float = params.water_max_alt
		panel._on_random_specs_pressed()
		# Fields show the new values.
		var spin: SpinBox = panel._spin_boxes["water_max_alt"]
		if absf(spin.value - params.water_max_alt) > 0.001:
			printerr("FAIL random_specs_panel_button spin %s != params %s"
					% [spin.value, params.water_max_alt])
			fail += 1
		fail += _assert_ranges(params, "panel")
	panel.queue_free()
	await process_frame
	# Restore MapGen defaults so later tests are not poisoned.
	root.get_node("MapGen").reset_to_defaults()
	if fail == 0:
		print("PASS test_random_specs_panel_button")
	return fail
