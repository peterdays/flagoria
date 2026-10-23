extends SceneTree
## Headless test entry point for CI.
## Run: godot --headless --path . --script res://tests/run_tests.gd
## Exit 0 on success, 1 on failure.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	failures += _test_smoke_true()
	failures += _test_map_characterization()
	failures += _test_spawn_on_land()
	failures += _test_map_settings_water_reopen()
	failures += _test_no_decorations_on_water()
	failures += _test_flowers()
	failures += _test_tile_catalog()
	failures += _test_audio_settings()
	failures += await _test_music_player()
	failures += await _test_combat_sfx()
	failures += _test_footsteps()
	failures += _test_island_falloff()
	failures += _test_archipelago()
	failures += _test_archipelago_count()
	failures += _test_archipelago_count_land_masses()
	failures += _test_biomes()
	failures += _test_biome_terrain()
	failures += _test_biome_plants()
	failures += _test_biome_structures()
	failures += await _test_water_blocks_player()
	failures += await _test_forest_walls()
	failures += _test_map_settings_covers_params()
	failures += _test_map_settings_rows_from_hints()
	failures += _test_new_param_needs_no_ui_code()
	failures += _test_biome_seed_panel_round_trip()
	failures += await _test_chunk_refresh_frames()
	failures += _test_map_save_round_trip()
	failures += _test_map_save_rejects_bad_files()
	failures += _test_player_spawn_no_missing_nodes()
	failures += _test_server_port_from_args()
	failures += await _test_dedicated_server_join()
	if failures == 0:
		print("All tests passed.")
		quit(0)
	else:
		print("Tests failed: %s" % failures)
		quit(1)


func _test_smoke_true() -> int:
	## Trivial sanity check that the headless runner executes and reports.
	print("-- test_smoke_true")
	if true:
		print("PASS test_smoke_true")
		return 0
	printerr("FAIL test_smoke_true")
	return 1


func _test_map_characterization() -> int:
	## Fixed MapGenParams seeds + generate_chunk; compare atlas coords on layers 0 and 1.
	print("-- test_map_characterization")
	const CHUNK_POS := Vector2(0, 0)

	# cell -> [layer0 atlas, layer1 atlas]  (Vector2i(-1,-1) = empty)
	var expected := {
		Vector2i(-16, -16): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(12, 6): [Vector2i(5, 4), Vector2i(-1, -1)],
		Vector2i(13, 6): [Vector2i(5, 1), Vector2i(-1, -1)],
		Vector2i(14, 6): [Vector2i(5, 0), Vector2i(-1, -1)],
		Vector2i(14, 11): [Vector2i(6, 0), Vector2i(-1, -1)],
		Vector2i(14, 7): [Vector2i(5, 1), Vector2i(7, 3)],
		Vector2i(0, 0): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(8, -8): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(-8, 8): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(15, 15): [Vector2i(5, 4), Vector2i(-1, -1)],
		Vector2i(15, 6): [Vector2i(6, 0), Vector2i(7, 3)],
	}

	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	if world == null:
		printerr("FAIL: World/worldMap missing")
		return 1

	var params = MapGenParams.make_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	world.apply_map_params(params)
	world.generate_chunk(CHUNK_POS)

	var fail := 0
	for cell in expected.keys():
		var want = expected[cell]
		var got0: Vector2i = world.get_cell_atlas_coords(0, cell)
		var got1: Vector2i = world.get_cell_atlas_coords(1, cell)
		if got0 != want[0] or got1 != want[1]:
			printerr(
				"FAIL cell=%s expected l0=%s l1=%s got l0=%s l1=%s"
				% [cell, want[0], want[1], got0, got1]
			)
			fail += 1

	if fail == 0:
		print("PASS test_map_characterization (%s cells)" % expected.size())
	scene.queue_free()
	return fail

func _test_spawn_on_land() -> int:
	print("-- test_spawn_on_land")
	var cases = [
		{"name": "default_seeds", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.2, "sand": 0.25},
		{"name": "high_water", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.45, "sand": 0.5},
		{"name": "seed_set_b", "alt": 99, "moist": 101, "temp": 103, "items": 107, "water": 0.2, "sand": 0.25},
		{"name": "seed_set_c_high_water", "alt": 4242, "moist": 5252, "temp": 6262, "items": 7272, "water": 0.4, "sand": 0.48},
	]
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	if world == null:
		printerr("FAIL: World/worldMap missing")
		return 1

	for case in cases:
		var params = MapGenParams.make_defaults()
		params.altitude_seed = case["alt"]
		params.moisture_seed = case["moist"]
		params.temperature_seed = case["temp"]
		params.items_seed = case["items"]
		params.water_max_alt = case["water"]
		params.sand_max_alt = case["sand"]
		world.apply_map_params(params)
		var cell: Vector2i = world.resolve_player_spawn()
		if not world.is_walkable_land(cell):
			printerr("FAIL spawn_on_land case=%s cell=%s not walkable land" % [case["name"], cell])
			fail += 1
			continue
		var neighbors: int = world.count_walkable_neighbors(cell)
		if neighbors < 1:
			printerr(
				"FAIL spawn_on_land case=%s cell=%s has zero walkable neighbors"
				% [case["name"], cell]
			)
			fail += 1
			continue
		world.apply_map_params(params)
		var again: Vector2i = world.resolve_player_spawn()
		if again != cell:
			printerr(
				"FAIL spawn_on_land case=%s nondeterministic first=%s second=%s"
				% [case["name"], cell, again]
			)
			fail += 1
			continue
		print("PASS spawn_on_land case=%s cell=%s neighbors=%s" % [case["name"], cell, neighbors])

	scene.queue_free()
	return fail

func _test_map_settings_water_reopen() -> int:
	## Map Settings must show the in-use water value on reopen, even when a
	## SpinBox LineEdit still holds a dirty string for the same numeric value.
	print("-- test_map_settings_water_reopen")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	var spin: SpinBox = panel._spin_boxes["water_max_alt"]
	var in_use := 0.45
	spin.value = in_use
	spin.get_line_edit().text = "0.2"
	var params = MapGenParams.make_defaults()
	params.water_max_alt = in_use
	panel.load_from_params(params)
	var shown := float(spin.get_line_edit().text)
	panel.queue_free()
	if abs(shown - in_use) > 0.001:
		printerr(
			"FAIL map_settings_water_reopen shown=%s want in-use=%s"
			% [shown, in_use]
		)
		return 1
	print("PASS test_map_settings_water_reopen shown=%s" % shown)
	return 0

func _test_no_decorations_on_water() -> int:
	print("-- test_no_decorations_on_water")
	var cases = [
		{"name": "char_seeds", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.2, "sand": 0.25},
		{"name": "high_water", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.45, "sand": 0.5},
		{"name": "seed_set_b", "alt": 99, "moist": 101, "temp": 103, "items": 107, "water": 0.2, "sand": 0.25},
		{"name": "seed_set_c_high_water", "alt": 4242, "moist": 5252, "temp": 6262, "items": 7272, "water": 0.4, "sand": 0.48},
	]
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	if world == null:
		printerr("FAIL: World/worldMap missing")
		return 1

	for case in cases:
		var params = MapGenParams.make_defaults()
		params.altitude_seed = case["alt"]
		params.moisture_seed = case["moist"]
		params.temperature_seed = case["temp"]
		params.items_seed = case["items"]
		params.water_max_alt = case["water"]
		params.sand_max_alt = case["sand"]
		world.apply_map_params(params)
		world.generate_chunk(Vector2(0, 0))
		var bad := 0
		var tile_pos: Vector2i = world.local_to_map(Vector2(0, 0))
		for x in range(world.chunk_width):
			for y in range(world.chunk_height):
				var cell = Vector2i(
					tile_pos.x - world.chunk_width / 2 + x,
					tile_pos.y - world.chunk_height / 2 + y
				)
				var a1: Vector2i = world.get_cell_atlas_coords(1, cell)
				if a1 == Vector2i(-1, -1):
					continue
				if not world.is_walkable_land(cell):
					bad += 1
					printerr(
						"FAIL decorations_on_water case=%s cell=%s l0=%s l1=%s"
						% [case["name"], cell, world.get_cell_atlas_coords(0, cell), a1]
					)
		if bad > 0:
			fail += 1
		else:
			print("PASS no_decorations_on_water case=%s" % case["name"])

	scene.queue_free()
	return fail

func _test_combat_sfx() -> int:
	## Each combat event plays once per call on this peer; a repeat inside the
	## cooldown is dropped; player hooks fire swing, hit+hurt, and sting on 0 HP.
	print("-- test_combat_sfx")
	var fail := 0
	var sfx := CombatSfx.new()
	root.add_child(sfx)
	for event in ["swing", "hit", "hurt", "sting"]:
		if not sfx.play_event(event) or sfx.plays[event] != 1:
			printerr("FAIL combat_sfx: %s did not play once" % event)
			fail += 1
		if sfx.play_event(event) or sfx.plays[event] != 1:
			printerr("FAIL combat_sfx: %s played again inside cooldown" % event)
			fail += 1
	if sfx.play_event("unknown"):
		printerr("FAIL combat_sfx: unknown event played")
		fail += 1
	sfx.queue_free()

	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = "2"
	scene.get_node("World").add_child(player)
	var c: CombatSfx = player.combat_sfx
	player.attack_animation()
	player.receiveDamage()
	if c.plays["swing"] != 1 or c.plays["hurt"] != 1 or c.plays["sting"] != 0:
		printerr("FAIL combat_sfx: attack + damage plays %s" % c.plays)
		fail += 1
	# A hit from another player's sword: hit and hurt once each; at 1 HP it is a kill.
	c._last_ms.clear()
	player.currentHealth = 1
	var other = load("res://Player/character_body_2d.tscn").instantiate()
	other.name = "3"
	scene.get_node("World").add_child(other)
	player._on_hurt_box_area_entered(other.get_node("weapon/sword"))
	if c.plays["hit"] != 1 or c.plays["hurt"] != 2 or c.plays["sting"] != 1:
		printerr("FAIL combat_sfx: kill hit plays %s" % c.plays)
		fail += 1
	# Damage at 0 HP loses nothing: no hurt and no second sting.
	c._last_ms.clear()
	player.receiveDamage()
	if player.currentHealth != 0 or c.plays["hurt"] != 2 or c.plays["sting"] != 1:
		printerr("FAIL combat_sfx: damage at 0 HP plays %s" % c.plays)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_combat_sfx")
	return fail


func _test_footsteps() -> int:
	## Footsteps: none while idle or on a teleport; walking at top speed in
	## simulated 60 Hz frames plays exactly one step per STEP_DISTANCE on every
	## surface, and no step starts before the previous clip (real length / pitch)
	## has ended. Surfaces are chosen by TileCatalog name.
	print("-- test_footsteps")
	var fail := 0
	var speed: float = load("res://Scripts/player.gd").MAX_SPEED
	var longest := 0.0
	for surface in Footsteps.SOUNDS:
		for clip in Footsteps.SOUNDS[surface]:
			longest = maxf(longest, clip.get_length())
	var stride_s := Footsteps.STEP_DISTANCE / speed
	if stride_s < longest / Footsteps.PITCH_MIN:
		printerr("FAIL footsteps: stride %.3f s shorter than longest clip %.3f s" % [stride_s, longest / Footsteps.PITCH_MIN])
		fail += 1

	var steps := Footsteps.new()
	root.add_child(steps)
	for i in range(120):
		steps.advance(Vector2(10, 10))
	if steps.steps_played != 0:
		printerr("FAIL footsteps: %d steps while idle" % steps.steps_played)
		fail += 1
	steps.advance(Vector2(500, 10))
	if steps.steps_played != 0:
		printerr("FAIL footsteps: step on teleport")
		fail += 1

	var dt := 1.0 / 60.0
	var strides := 10
	var x := 500.0
	for surface in ["grass", "sand", "swamp"]:
		steps.surface_override = surface
		var before: int = steps.steps_played
		var t := 0.0
		var clip_end := -1.0
		var walked := 0.0
		# Walk just short of the 11th stride so float rounding cannot add one.
		while walked + speed * dt <= strides * Footsteps.STEP_DISTANCE + Footsteps.STEP_DISTANCE * 0.5:
			var count: int = steps.steps_played
			x += speed * dt
			walked += speed * dt
			t += dt
			steps.advance(Vector2(x, 10))
			if steps.steps_played != count:
				if t < clip_end:
					printerr("FAIL footsteps: %s step at %.3f s before clip end %.3f s" % [surface, t, clip_end])
					fail += 1
				clip_end = t + steps.stream.get_length() / steps.pitch_scale
				if steps.last_surface != surface:
					printerr("FAIL footsteps: played %s want %s" % [steps.last_surface, surface])
					fail += 1
		var got: int = steps.steps_played - before
		if got != strides:
			printerr("FAIL footsteps: %s %d steps over %d px, want %d" % [surface, got, int(walked), strides])
			fail += 1
		# Reset the stride counter between surfaces with a stop + teleport.
		x += 1000.0
		steps.advance(Vector2(x, 10))

	var after_walk: int = steps.steps_played
	for i in range(120):
		steps.advance(Vector2(x, 10))
	if steps.steps_played != after_walk:
		printerr("FAIL footsteps: steps continued after stopping")
		fail += 1
	if steps.volume_db > -8.0 or steps.volume_db < -12.0:
		printerr("FAIL footsteps: volume %s dB outside -12..-8" % steps.volume_db)
		fail += 1
	var cases := {
		TileCatalog.SAND: "sand", TileCatalog.SWAMP: "swamp", TileCatalog.SWAMP_SPECIAL: "swamp",
		TileCatalog.GRASS_C: "grass", TileCatalog.WATER: "grass", Vector2i(-1, -1): "grass",
	}
	for atlas in cases:
		var got := Footsteps.surface_for_atlas(atlas)
		if got != cases[atlas]:
			printerr("FAIL footsteps: surface for %s is %s want %s" % [atlas, got, cases[atlas]])
			fail += 1
	steps.queue_free()
	if fail == 0:
		print("PASS test_footsteps")
	return fail


func _test_audio_settings() -> int:
	## Music and SFX buses exist under Master; game sounds use SFX; the menu
	## sliders set bus volume_db, 0 mutes, and values persist across a reload.
	print("-- test_audio_settings")
	var fail := 0
	var audio = root.get_node("AudioSettings")
	var saved_path: String = audio.save_path
	audio.save_path = "user://test_audio_settings.cfg"
	DirAccess.remove_absolute(audio.save_path)
	# Start from defaults, whatever the real settings file held at launch.
	audio.load_from_disk()

	# Corrupt or hand-edited values: defaults or clamp, never a crash or mute.
	# [saved value, expected volume]; NaN cannot be a dictionary key.
	var bad := [["abc", 1.0], [[0.5], 1.0], [NAN, 1.0], [INF, 1.0], [-0.5, 1.0], [7, 1.0], [1.5, 1.0], [0.3, 0.3]]
	for pair in bad:
		var value = pair[0]
		var cfg := ConfigFile.new()
		cfg.set_value(audio.SECTION, "SFX", value)
		cfg.save(audio.save_path)
		audio.load_from_disk()
		var idx := AudioServer.get_bus_index("SFX")
		if not is_equal_approx(audio.get_volume("SFX"), pair[1]) or AudioServer.is_bus_mute(idx):
			printerr("FAIL audio_settings: saved %s loads as %s mute=%s, want %s" % [value, audio.get_volume("SFX"), AudioServer.is_bus_mute(idx), pair[1]])
			fail += 1
	DirAccess.remove_absolute(audio.save_path)
	audio.load_from_disk()
	for bus in ["Music", "SFX"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0 or AudioServer.get_bus_send(idx) != &"Master":
			printerr("FAIL audio_settings: bus %s missing or not sending to Master" % bus)
			fail += 1

	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	var sliders := {"Music": menu.music_volume, "SFX": menu.sfx_volume}
	for bus in sliders:
		var slider: HSlider = sliders[bus]
		var idx := AudioServer.get_bus_index(bus)
		if not is_equal_approx(slider.value, audio.DEFAULTS[bus]):
			printerr("FAIL audio_settings: %s slider starts at %s want %s" % [bus, slider.value, audio.DEFAULTS[bus]])
			fail += 1
		slider.value = 0.25
		var label: Label = menu.music_value if bus == "Music" else menu.sfx_value
		if label.text != "25%":
			printerr("FAIL audio_settings: %s label shows %s at 0.25" % [bus, label.text])
			fail += 1
		if not is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(0.25)) or AudioServer.is_bus_mute(idx):
			printerr("FAIL audio_settings: %s at 0.25 gives %s dB mute=%s" % [bus, AudioServer.get_bus_volume_db(idx), AudioServer.is_bus_mute(idx)])
			fail += 1
		slider.value = 0.0
		if not AudioServer.is_bus_mute(idx):
			printerr("FAIL audio_settings: %s at 0 is not muted" % bus)
			fail += 1
	menu.sfx_volume.value = 0.4
	# Reload from disk, as on the next launch.
	audio.reset_to_defaults()
	audio.load_from_disk()
	if not is_equal_approx(audio.get_volume("SFX"), 0.4) or not is_equal_approx(audio.get_volume("Music"), 0.0):
		printerr("FAIL audio_settings: reload gives SFX %s Music %s, want 0.4 and 0" % [audio.get_volume("SFX"), audio.get_volume("Music")])
		fail += 1
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")):
		printerr("FAIL audio_settings: Music saved at 0 is not muted after reload")
		fail += 1

	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = "2"
	scene.get_node("World").add_child(player)
	var routed: Array = [player.get_node("Footsteps")]
	routed.append_array(player.get_node("CombatSfx").get_children())
	for node in routed:
		if node.bus != &"SFX":
			printerr("FAIL audio_settings: %s plays on %s, not SFX" % [node.name, node.bus])
			fail += 1

	scene.queue_free()
	DirAccess.remove_absolute(audio.save_path)
	audio.save_path = saved_path
	audio.load_from_disk()
	if fail == 0:
		print("PASS test_audio_settings")
	return fail


func _test_music_player() -> int:
	## Music loops on the Music bus, asking for the playing track does not
	## restart it, a new track replaces the old one (crossfade), and reloading
	## the main menu does not start a second copy.
	print("-- test_music_player")
	var fail := 0
	var music = root.get_node("MusicPlayer")
	music.stop(0.0)
	for p in music.players():
		if p.bus != &"Music":
			printerr("FAIL music: %s plays on %s, not Music" % [p.name, p.bus])
			fail += 1
	var starts: int = music.starts
	music.play(music.MENU_TRACK, 0.0)
	if music.current_track() != music.MENU_TRACK or music.starts != starts + 1:
		printerr("FAIL music: menu track not playing (%s)" % music.current_track())
		fail += 1
	var first: AudioStreamPlayer = null
	for p in music.players():
		if p.playing:
			first = p
	if first == null or not first.stream.loop:
		printerr("FAIL music: menu track is not set to loop")
		fail += 1
	await create_timer(0.2).timeout
	var pos := first.get_playback_position() if first else 0.0
	music.play(music.MENU_TRACK)
	if music.starts != starts + 1 or not first.playing or first.get_playback_position() < pos:
		printerr("FAIL music: same track restarted")
		fail += 1

	music.play(music.GAME_TRACK, 0.3)
	var playing := 0
	for p in music.players():
		playing += 1 if p.playing else 0
	if music.current_track() != music.GAME_TRACK or playing != 2:
		printerr("FAIL music: crossfade should play both tracks briefly, %d playing" % playing)
		fail += 1
	await create_timer(0.6).timeout
	playing = 0
	for p in music.players():
		playing += 1 if p.playing else 0
	if playing != 1 or first.playing:
		printerr("FAIL music: after the crossfade %d players play, old one playing=%s" % [playing, first.playing])
		fail += 1

	# The main menu asks for the menu track; a second menu does not double it.
	music.stop(0.0)
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var after_first: int = music.starts
	var again = load("res://flagoria_main.tscn").instantiate()
	again.name = "FlagoriaAgain"
	root.add_child(again)
	playing = 0
	for p in music.players():
		playing += 1 if p.playing else 0
	if music.current_track() != music.MENU_TRACK or music.starts != after_first or playing != 1:
		printerr("FAIL music: menu reload starts=%d->%d playing=%d" % [after_first, music.starts, playing])
		fail += 1
	again.queue_free()
	scene.queue_free()
	music.stop(0.0)
	await process_frame
	if fail == 0:
		print("PASS test_music_player")
	return fail


func _test_tile_catalog() -> int:
	## Every TileCatalog.<NAME> used in Scripts/ is in TileCatalog.TILES, every
	## entry exists in the world TileSet, and map scripts pass no raw atlas
	## coords to set_cell.
	print("-- test_tile_catalog")
	var fail := 0
	var used := {}
	var name_re := RegEx.create_from_string("TileCatalog\\.([A-Z][A-Z0-9_]*)")
	var raw_re := RegEx.create_from_string("set_cell\\([^\\n]*Vector2i\\(")
	for file in DirAccess.get_files_at("res://Scripts"):
		if not file.ends_with(".gd") or file == "tile_catalog.gd":
			continue
		var text := FileAccess.get_file_as_string("res://Scripts/" + file)
		for m in name_re.search_all(text):
			used[m.get_string(1)] = file
		if raw_re.search(text) != null:
			printerr("FAIL tile_catalog: raw atlas coords in set_cell in %s" % file)
			fail += 1
	if used.is_empty():
		printerr("FAIL tile_catalog: no TileCatalog names found in Scripts/")
		fail += 1
	for n in used:
		if n == "SOURCE_ID" or n == "TILES":
			continue
		if not TileCatalog.TILES.has(n):
			printerr("FAIL tile_catalog: %s used in %s is missing from TILES" % [n, used[n]])
			fail += 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	var tile_set: TileSet = scene.get_node("World/worldMap").tile_set
	for n in TileCatalog.TILES:
		var entry: Dictionary = TileCatalog.TILES[n]
		var src = tile_set.get_source(entry["source_id"]) if tile_set.has_source(entry["source_id"]) else null
		if not src is TileSetAtlasSource or not src.has_tile(entry["atlas"]):
			printerr("FAIL tile_catalog: %s %s not in TileSet source %s" % [n, entry["atlas"], entry["source_id"]])
			fail += 1
	## The map fill tiles keep their cells across tileset versions, so saved
	## maps and the pinned tests stay valid.
	var pinned := {
		"WATER": Vector2i(5, 6), "SAND": Vector2i(5, 4), "SWAMP": Vector2i(14, 7),
		"SWAMP_SPECIAL": Vector2i(27, 7), "GRASS_A": Vector2i(5, 0), "GRASS_B": Vector2i(5, 1),
		"GRASS_C": Vector2i(6, 0), "GRASS_D": Vector2i(6, 1), "BUSH": Vector2i(7, 3),
		"TREE": Vector2i(7, 0), "FLOWER": Vector2i(9, 3), "STONES": Vector2i(0, 7),
	}
	for n in pinned:
		if not TileCatalog.TILES.has(n) or TileCatalog.TILES[n]["atlas"] != pinned[n]:
			printerr("FAIL tile_catalog: %s moved from %s" % [n, pinned[n]])
			fail += 1
	## STONES reuses the small-rocks art cell on purpose.
	var aliases := {"STONES": "ROCK_FLOAT_S"}
	var cells := {}
	for n in TileCatalog.TILES:
		var a: Vector2i = TileCatalog.TILES[n]["atlas"]
		if cells.has(a) and aliases.get(n, "") != cells[a] and aliases.get(cells[a], "") != n:
			printerr("FAIL tile_catalog: %s and %s share cell %s" % [cells[a], n, a])
			fail += 1
		cells[a] = n
	## Collision drives walkability: water blocks, ground fill does not.
	var src0: TileSetAtlasSource = tile_set.get_source(TileCatalog.SOURCE_ID)
	for n in ["WATER", "TREE", "BUSH"]:
		if src0.get_tile_data(TileCatalog.TILES[n]["atlas"], 0).get_collision_polygons_count(0) == 0:
			printerr("FAIL tile_catalog: %s has no collision polygon" % n)
			fail += 1
	for n in ["SAND", "SWAMP", "SWAMP_SPECIAL", "GRASS_A", "GRASS_B", "GRASS_C", "GRASS_D", "FLOWER", "STONES"]:
		if src0.get_tile_data(TileCatalog.TILES[n]["atlas"], 0).get_collision_polygons_count(0) != 0:
			printerr("FAIL tile_catalog: %s should be walkable" % n)
			fail += 1
	## Island terrain: one terrain set with every ISLAND_BLOB_ base piece in it.
	if tile_set.get_terrain_sets_count() <= TileCatalog.ISLAND_TERRAIN_SET \
			or tile_set.get_terrain_name(TileCatalog.ISLAND_TERRAIN_SET, TileCatalog.ISLAND_TERRAIN) != "Island":
		printerr("FAIL tile_catalog: no Island terrain in the world TileSet")
		fail += 1
	else:
		var bases := 0
		for n in TileCatalog.TILES:
			if not n.begins_with("ISLAND_BLOB_"):
				continue
			if not n.contains("_W"):
				bases += 1
			var td: TileData = src0.get_tile_data(TileCatalog.TILES[n]["atlas"], 0)
			if td.terrain_set != TileCatalog.ISLAND_TERRAIN_SET or td.terrain != TileCatalog.ISLAND_TERRAIN:
				printerr("FAIL tile_catalog: %s is not an Island terrain tile" % n)
				fail += 1
		if bases != 47:
			printerr("FAIL tile_catalog: expected 47 island blob pieces, got %d" % bases)
			fail += 1
	scene.free()
	if fail == 0:
		print("PASS test_tile_catalog")
	return fail


func _test_flowers() -> int:
	## Flowers (atlas 9,3) need walkable land, moisture above 0, altitude in
	## (flower_min_alt, flower_max_alt] and chance above flower_min_chance.
	## Bushes and trees win where bands overlap, and turning flowers off
	## leaves every bush and tree where it was.
	print("-- test_flowers")
	const FLOWER := Vector2i(9, 3)
	const BUSH := Vector2i(7, 3)
	const NONE := Vector2i(-1, -1)
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = MapGenParams.make_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	world.apply_map_params(params)
	var ground := Vector2i(500, 500)
	var water := Vector2i(501, 500)
	world.set_cell(0, ground, 0, Vector2i(5, 0))
	world.set_cell(0, water, 0, Vector2i(5, 6))
	# Flowers are walkable, so they must draw below the player (sprite z 0).
	if world.get_layer_z_index(world.GROUND_DECOR_LAYER) >= 0 or world.GROUND_DECOR_LAYER == 1:
		printerr("FAIL flowers: ground decor layer %s z=%s must be < 0 and not layer 1" % [world.GROUND_DECOR_LAYER, world.get_layer_z_index(world.GROUND_DECOR_LAYER)])
		fail += 1
	var L := 2
	# [name, cell, alt, moist, chance, expected layer-1 atlas, expected layer-2 atlas]
	var cases := [
		["in_band", ground, 0.28, 0.5, 0.9, NONE, FLOWER],
		["low_chance", ground, 0.28, 0.5, 0.1, NONE, NONE],
		["dry", ground, 0.28, -0.1, 0.9, NONE, NONE],
		["below_band", ground, 0.25, 0.5, 0.9, NONE, NONE],
		["bush_band", ground, 0.35, 0.5, 0.9, BUSH, NONE],
		["water", water, 0.28, 0.5, 0.9, NONE, NONE],
	]
	for c in cases:
		world.erase_cell(1, c[1])
		world.erase_cell(L, c[1])
		world.set_tile_type_z1(c[1], c[2], c[3], 0.0, c[4])
		var got1: Vector2i = world.get_cell_atlas_coords(1, c[1])
		var got2: Vector2i = world.get_cell_atlas_coords(L, c[1])
		if got1 != c[5] or got2 != c[6]:
			printerr("FAIL flowers case=%s got l1=%s l2=%s want %s %s" % [c[0], got1, got2, c[5], c[6]])
			fail += 1

	params.chunk_width = 64
	params.chunk_height = 64
	world.apply_map_params(params)
	world.generate_chunk(Vector2(0, 0))
	var with_flowers := {}
	var flowers := 0
	for x in range(-32, 32):
		for y in range(-32, 32):
			var cell := Vector2i(x, y)
			var a1: Vector2i = world.get_cell_atlas_coords(1, cell)
			var a2: Vector2i = world.get_cell_atlas_coords(L, cell)
			if a1 == FLOWER:
				printerr("FAIL flowers: flower on foliage layer 1 at %s" % cell)
				fail += 1
			with_flowers[cell] = [a1, a2]
			if a2 == FLOWER:
				flowers += 1
				if not world.is_walkable_land(cell):
					printerr("FAIL flowers: flower on non-walkable cell %s" % cell)
					fail += 1
	if flowers == 0:
		printerr("FAIL flowers: default params placed no flowers in a 64x64 chunk")
		fail += 1

	params.flower_min_chance = 1.0
	world.apply_map_params(params)
	world.generate_chunk(Vector2(0, 0))
	for cell in with_flowers.keys():
		var a1: Vector2i = world.get_cell_atlas_coords(1, cell)
		var a2: Vector2i = world.get_cell_atlas_coords(L, cell)
		if a1 != with_flowers[cell][0] or a2 != NONE:
			printerr("FAIL flowers: without flowers cell %s l1=%s l2=%s want %s %s" % [cell, a1, a2, with_flowers[cell][0], NONE])
			fail += 1
	if fail == 0:
		print("PASS test_flowers flowers=%s" % flowers)
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_island_falloff() -> int:
	## island_radius 0 leaves altitude alone; a set radius raises the origin,
	## keeps the radius unchanged, and sinks cells past 1.5 radii to water.
	print("-- test_island_falloff")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = MapGenParams.make_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	params.chunk_width = 64
	params.chunk_height = 64
	world.apply_map_params(params)
	if world.island_altitude(Vector2i(40, -25), 0.7) != 0.7:
		printerr("FAIL island_falloff: radius 0 changed altitude")
		fail += 1

	params.island_radius = 20
	params.island_falloff = 2.0
	world.apply_map_params(params)
	if not is_equal_approx(world.island_altitude(Vector2i(0, 0), 0.1), 2.1):
		printerr("FAIL island_falloff: origin not raised by island_falloff")
		fail += 1
	if not is_equal_approx(world.island_altitude(Vector2i(20, 0), 0.7), 0.7):
		printerr("FAIL island_falloff: altitude at the radius changed")
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	var land := 0
	for x in range(-32, 32):
		for y in range(-32, 32):
			var cell := Vector2i(x, y)
			var water: bool = world.get_cell_atlas_coords(0, cell) == Vector2i(5, 6)
			if Vector2(cell).length() >= 30.0 and not water:
				printerr("FAIL island_falloff: land at %s beyond 1.5 radii" % cell)
				fail += 1
			elif not water:
				land += 1
	if land == 0:
		printerr("FAIL island_falloff: no land inside the island")
		fail += 1
	if fail == 0:
		print("PASS test_island_falloff land_cells=%s" % land)
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_archipelago() -> int:
	## archipelago_spacing 0 leaves altitude alone; with a spacing, each grid
	## square's centre is raised, the sea between neighbouring centres sinks,
	## and jittered centres stay inside their square and repeat for a seed.
	print("-- test_archipelago")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = MapGenParams.make_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	world.apply_map_params(params)
	if world.archipelago_altitude(Vector2i(40, -25), 0.7) != 0.7:
		printerr("FAIL archipelago: spacing 0 changed altitude")
		fail += 1

	params.archipelago_spacing = 64
	params.archipelago_island_radius = 16
	params.archipelago_jitter = 0.0
	params.island_falloff = 2.0
	world.apply_map_params(params)
	for centre in [Vector2i(32, 32), Vector2i(96, 32), Vector2i(-32, -32)]:
		if not is_equal_approx(world.archipelago_altitude(centre, 0.1), 2.1):
			printerr("FAIL archipelago: centre %s not raised by island_falloff" % centre)
			fail += 1
	if world.archipelago_altitude(Vector2i(64, 32), 0.9) > params.water_max_alt:
		printerr("FAIL archipelago: cell between two centres is not sea")
		fail += 1

	params.archipelago_jitter = 1.0
	world.apply_map_params(params)
	var first: Vector2 = world.archipelago_centre(Vector2i(3, -2))
	world.apply_map_params(params)
	if world.archipelago_centre(Vector2i(3, -2)) != first:
		printerr("FAIL archipelago: centre changed for the same seed")
		fail += 1
	for sx in range(-3, 3):
		for sy in range(-3, 3):
			var c: Vector2 = world.archipelago_centre(Vector2i(sx, sy))
			var lo := Vector2(sx, sy) * 64.0
			if c.x < lo.x or c.y < lo.y or c.x > lo.x + 64.0 or c.y > lo.y + 64.0:
				printerr("FAIL archipelago: centre %s left square %s" % [c, Vector2i(sx, sy)])
				fail += 1
	if fail == 0:
		print("PASS test_archipelago")
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_archipelago_count() -> int:
	## count/extent 0 keep prior archipelago behaviour; with both set, exactly
	## N centres are active, selection is seed-stable, and spacing 0 stays a no-op.
	print("-- test_archipelago_count")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = MapGenParams.make_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	params.archipelago_spacing = 64
	params.archipelago_island_radius = 16
	params.archipelago_jitter = 0.0
	params.island_falloff = 2.0
	world.apply_map_params(params)
	# Prior behaviour: distant centre still raised when extent/count are 0.
	if not is_equal_approx(world.archipelago_altitude(Vector2i(96, 32), 0.1), 2.1):
		printerr("FAIL archipelago_count: extent/count 0 changed prior centre boost")
		fail += 1
	if not world.archipelago_square_active(Vector2i(5, 5)):
		printerr("FAIL archipelago_count: unbounded square should be active")
		fail += 1

	params.archipelago_world_extent = 200
	params.archipelago_island_count = 0
	world.apply_map_params(params)
	if not world.archipelago_square_active(Vector2i(0, 0)):
		printerr("FAIL archipelago_count: origin square should stay active with extent only")
		fail += 1
	if world.archipelago_square_active(Vector2i(20, 20)):
		printerr("FAIL archipelago_count: far square should be inactive with extent set")
		fail += 1

	params.archipelago_island_count = 5
	world.apply_map_params(params)
	var active: Array[Vector2i] = []
	var s: int = params.archipelago_spacing
	var e: int = params.archipelago_world_extent
	var sx0: int = int(floor(float(-e) / float(s))) - 1
	var sx1: int = int(floor(float(e) / float(s))) + 1
	for sx in range(sx0, sx1 + 1):
		for sy in range(sx0, sx1 + 1):
			var sq := Vector2i(sx, sy)
			if world.archipelago_square_active(sq):
				active.append(sq)
	if active.size() != 5:
		printerr("FAIL archipelago_count: expected 5 active centres, got %s" % active.size())
		fail += 1
	for sq in active:
		var centre_cell := Vector2i(
			int(floor((float(sq.x) + 0.5) * float(s))),
			int(floor((float(sq.y) + 0.5) * float(s)))
		)
		if not is_equal_approx(world.archipelago_altitude(centre_cell, 0.1), 2.1):
			printerr("FAIL archipelago_count: active centre %s not raised" % sq)
			fail += 1
	# A candidate square inside the extent that was not selected must not raise.
	var skipped: Variant = null
	for sx in range(sx0, sx1 + 1):
		for sy in range(sx0, sx1 + 1):
			var sq2 := Vector2i(sx, sy)
			var min_x: int = sq2.x * s
			var max_x: int = (sq2.x + 1) * s - 1
			var min_y: int = sq2.y * s
			var max_y: int = (sq2.y + 1) * s - 1
			if min_x <= e and max_x >= -e and min_y <= e and max_y >= -e:
				if not world.archipelago_square_active(sq2):
					skipped = sq2
					break
		if skipped != null:
			break
	if skipped == null:
		printerr("FAIL archipelago_count: no unselected candidate inside extent")
		fail += 1
	else:
		var skipped_cell := Vector2i(
			int(floor((float(skipped.x) + 0.5) * float(s))),
			int(floor((float(skipped.y) + 0.5) * float(s)))
		)
		if is_equal_approx(world.archipelago_altitude(skipped_cell, 0.1), 2.1):
			printerr("FAIL archipelago_count: unselected centre %s still fully raised" % skipped)
			fail += 1

	var first_active: Array = active.duplicate()
	world.apply_map_params(params)
	for sq3 in first_active:
		if not world.archipelago_square_active(sq3):
			printerr("FAIL archipelago_count: active set changed for the same seed")
			fail += 1
			break

	params.archipelago_spacing = 0
	world.apply_map_params(params)
	if world.archipelago_altitude(Vector2i(40, -25), 0.7) != 0.7:
		printerr("FAIL archipelago_count: spacing 0 changed altitude")
		fail += 1
	if world.archipelago_square_active(Vector2i(0, 0)):
		printerr("FAIL archipelago_count: spacing 0 should activate no squares")
		fail += 1

	if fail == 0:
		print("PASS test_archipelago_count")
	scene.queue_free()
	return 1 if fail > 0 else 0


func _archipelago_land_masses(world, half: int) -> int:
	## 4-connected land components in [-half, half)^2 using the chunk altitude.
	var land := {}
	for x in range(-half, half):
		for y in range(-half, half):
			var cell := Vector2i(x, y)
			var alt: float = world.archipelago_altitude(cell, world.island_altitude(cell, world.altitude.get_noise_2d(x, y)))
			if alt > world.water_max_alt:
				land[cell] = true
	var masses := 0
	var seen := {}
	for start in land.keys():
		if seen.has(start):
			continue
		masses += 1
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + step
				if land.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
	return masses


func _test_archipelago_count_land_masses() -> int:
	## archipelago_island_count works without archipelago_world_extent, the
	## spawn square is always kept, dropped squares are sea, and the number of
	## land masses grows with the count.
	print("-- test_archipelago_count_land_masses")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var params = MapGenParams.make_defaults()
	params.altitude_seed = 42
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	params.archipelago_spacing = 40
	params.archipelago_island_radius = 14
	params.island_falloff = 2.0
	var half := 120
	var previous := -1
	for count in [1, 2, 3, 4, 5, 6]:
		params.archipelago_island_count = count
		world.apply_map_params(params)
		var kept := 0
		for sx in range(-half / 40, half / 40):
			for sy in range(-half / 40, half / 40):
				var sq := Vector2i(sx, sy)
				if world.archipelago_square_active(sq):
					kept += 1
					continue
				for x in range(sx * 40, sx * 40 + 40, 3):
					for y in range(sy * 40, sy * 40 + 40, 3):
						var cell := Vector2i(x, y)
						if world.archipelago_altitude(cell, 1.0) > world.water_max_alt:
							printerr("FAIL archipelago_count_land_masses count=%s dropped square %s has land" % [count, sq])
							fail += 1
							break
					if fail > 0:
						break
		if kept != count:
			printerr("FAIL archipelago_count_land_masses count=%s kept %s squares" % [count, kept])
			fail += 1
		if not world.archipelago_square_active(Vector2i.ZERO):
			printerr("FAIL archipelago_count_land_masses count=%s dropped the spawn square" % count)
			fail += 1
		var centre := Vector2i(world.archipelago_centre(Vector2i.ZERO).round())
		if world.archipelago_altitude(centre, 0.0) <= world.water_max_alt:
			printerr("FAIL archipelago_count_land_masses count=%s spawn island is sea" % count)
			fail += 1
		var masses := _archipelago_land_masses(world, half)
		if masses < previous:
			printerr("FAIL archipelago_count_land_masses count=%s gave %s land masses, fewer than %s" % [count, masses, previous])
			fail += 1
		print("archipelago_count_land_masses count=%s masses=%s" % [count, masses])
		previous = masses
	if previous <= 1:
		printerr("FAIL archipelago_count_land_masses count=6 gave %s land masses" % previous)
		fail += 1
	if fail == 0:
		print("PASS test_archipelago_count_land_masses")
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_biomes() -> int:
	## biome_frequency 0 keeps TEMPERATE and prior archipelago squares; frequency
	## > 0 yields multiple biomes and thins OCEANIC archipelago squares vs dense.
	print("-- test_biomes")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = MapGenParams.make_defaults()
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


func _biome_terrain_params(arch: bool) -> MapGenParams:
	var p := MapGenParams.make_defaults()
	p.altitude_seed = 2
	p.moisture_seed = 7
	p.temperature_seed = 12
	p.items_seed = 17
	p.biome_seed = 31
	p.chunk_width = 96
	p.chunk_height = 96
	if arch:
		p.archipelago_spacing = 64
		p.archipelago_island_radius = 16
		p.archipelago_jitter = 0.35
		p.island_falloff = 2.0
	return p


func _chunk_digest(world, centre: Vector2i, w: int) -> String:
	## sha256 over layer 0, 1 and 2 atlas coords of a w x w square at centre.
	var parts := PackedStringArray()
	for x in range(centre.x - w / 2, centre.x + w / 2):
		for y in range(centre.y - w / 2, centre.y + w / 2):
			var c := Vector2i(x, y)
			parts.append("%s%s%s" % [world.get_cell_atlas_coords(0, c), world.get_cell_atlas_coords(1, c), world.get_cell_atlas_coords(2, c)])
	return ";".join(parts).sha256_text()


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
		var got: Vector2i = world.plant_tile(c[1], 0.5, c[2], c[3])
		if got != c[4]:
			printerr("FAIL biome_plants case=%s got %s want %s" % [c[0], got, c[4]])
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
	for b in BiomeCatalog.PLANTS:
		land[b] = 0
		trees[b] = 0
		bushes[b] = 0
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

	if fail == 0:
		print("PASS test_biome_plants land=%s trees=%s bushes=%s" % [land, trees, bushes])
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


func _test_forest_walls() -> int:
	## A row or column of adjacent TREE or BUSH cells is a wall: sweep the
	## player's shape across it in half-pixel lanes and require every lane to
	## stop. Half pixels matter: a gap 1 px wider than the player only opens
	## between whole-pixel lanes. With one free cell between plants the
	## player must still pass.
	print("-- test_forest_walls")
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	var body: CollisionShape2D = player.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body.shape
	query.collision_mask = player.collision_mask
	var offset: Vector2 = body.position
	player.free()
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	for tile_name in ["TREE", "BUSH"]:
		var tile: Vector2i = TileCatalog.TILES[tile_name]["atlas"]
		world.clear()
		for x in range(-2, 50):
			for y in range(-2, 50):
				world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
		for i in range(4, 16):
			world.set_cell(1, Vector2i(i, 10), TileCatalog.SOURCE_ID, tile)  # row
			world.set_cell(1, Vector2i(30, i), TileCatalog.SOURCE_ID, tile)  # column
		for i in range(4, 16, 2):
			world.set_cell(1, Vector2i(i, 30), TileCatalog.SOURCE_ID, tile)  # spaced row
			world.set_cell(1, Vector2i(40, i + 20), TileCatalog.SOURCE_ID, tile)  # spaced column
		await physics_frame
		await physics_frame
		var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
		var sweeps := [
			["row", Vector2i(5, 10), Vector2i(14, 10), Vector2(0, 1), true],
			["column", Vector2i(30, 5), Vector2i(30, 14), Vector2(1, 0), true],
			["spaced_row", Vector2i(5, 30), Vector2i(14, 30), Vector2(0, 1), false],
			["spaced_column", Vector2i(40, 25), Vector2i(40, 34), Vector2(1, 0), false],
		]
		for sw in sweeps:
			var a: Vector2 = world.to_global(world.map_to_local(sw[1]))
			var b: Vector2 = world.to_global(world.map_to_local(sw[2]))
			var dir: Vector2 = sw[3]
			var lanes := int((b - a).length() * 2.0)  # every 0.5 px
			var passes := 0
			for i in lanes:
				query.transform = Transform2D(0, a.lerp(b, float(i) / lanes) - dir * 40.0 + offset)
				query.motion = dir * 80.0
				if space.cast_motion(query)[0] >= 1.0:
					passes += 1
			if sw[4] and passes > 0:
				printerr("FAIL forest_walls: %s %s lets %d/%d lanes through" % [tile_name, sw[0], passes, lanes])
				fail += 1
			elif not sw[4] and passes == 0:
				printerr("FAIL forest_walls: %s %s has no gap the player fits through" % [tile_name, sw[0]])
				fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_forest_walls")
	return fail


func _test_water_blocks_player() -> int:
	## Any cell that is_walkable_land rejects must have its own collision under
	## the player's mask. TileMap bodies join the physics
	## space on the next physics frame, hence the await.
	print("-- test_water_blocks_player")
	var cases = [
		{"name": "default_seeds", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.2, "sand": 0.25},
		{"name": "high_water", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.45, "sand": 0.5},
		{"name": "seed_set_c_high_water", "alt": 4242, "moist": 5252, "temp": 6262, "items": 7272, "water": 0.4, "sand": 0.48},
	]
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	var point := PhysicsPointQueryParameters2D.new()
	point.collision_mask = player.collision_mask
	player.free()

	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state

	for case in cases:
		var params = MapGenParams.make_defaults()
		params.altitude_seed = case["alt"]
		params.moisture_seed = case["moist"]
		params.temperature_seed = case["temp"]
		params.items_seed = case["items"]
		params.water_max_alt = case["water"]
		params.sand_max_alt = case["sand"]
		world.apply_map_params(params)
		world.generate_chunk(Vector2(0, 0))
		await physics_frame
		var checked := 0
		var open := 0
		for cell in world.get_used_cells(0):
			if world.is_walkable_land(cell):
				continue
			checked += 1
			# Godot 4.5+ merges tile collision into one body per physics quadrant,
			# so get_coords_for_body_rid no longer names a single cell. Probe this
			# cell's centre instead: a TileMap hit there is this cell's own shape.
			point.position = world.to_global(world.map_to_local(cell))
			var blocked := false
			for hit in space.intersect_point(point, 8):
				if hit["collider"] == world:
					blocked = true
					break
			if not blocked:
				open += 1
				if open <= 3:
					printerr("FAIL water_blocks_player case=%s cell=%s is open" % [case["name"], cell])
		if checked == 0 or open > 0:
			printerr(
				"FAIL water_blocks_player case=%s checked=%s open=%s"
				% [case["name"], checked, open]
			)
			fail += 1
		else:
			print("PASS water_blocks_player case=%s checked=%s" % [case["name"], checked])

	scene.queue_free()
	return fail

func _test_map_settings_covers_params() -> int:
	## Every exported MapGenParams property must reach clients (to_dict) and
	## have a Map Settings control.
	print("-- test_map_settings_covers_params")
	var hand_wired := ["altitude_seed", "moisture_seed", "temperature_seed", "items_seed", "biome_seed", "noise_type"]
	var params = MapGenParams.make_defaults()
	var keys: Dictionary = params.to_dict()
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	var fail := 0
	var exported := 0
	for prop in params.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		exported += 1
		var key: String = prop["name"]
		if not keys.has(key):
			printerr("FAIL map_settings_covers_params %s missing from to_dict()" % key)
			fail += 1
		if not panel._spin_boxes.has(key) and not hand_wired.has(key):
			printerr("FAIL map_settings_covers_params %s has no panel control" % key)
			fail += 1

	params.chunk_refresh_frames = 7
	panel.load_from_params(params)
	panel._spin_boxes["chunk_refresh_frames"].value = 9
	panel.apply_to_params(params)
	if params.chunk_refresh_frames != 9:
		printerr(
			"FAIL map_settings_covers_params panel round-trip chunk_refresh_frames=%s want 9"
			% params.chunk_refresh_frames
		)
		fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_covers_params (%s properties)" % exported)
	return fail

func _test_map_settings_rows_from_hints() -> int:
	## Map Settings rows come from MapGenParams @export_range hints. Pins the
	## label, range and order of the rows that existed before that change;
	## rows for new parameters are allowed.
	print("-- test_map_settings_rows_from_hints")
	var expected := {
		"altitude_frequency": ["Altitude frequency", 0.001, 1.0, 0.001],
		"moisture_frequency": ["Moisture frequency", 0.001, 1.0, 0.001],
		"temperature_frequency": ["Temperature frequency", 0.001, 1.0, 0.001],
		"items_frequency": ["Items frequency", 0.01, 4.0, 0.01],
		"fractal_octaves": ["Fractal octaves", 1, 10, 1],
		"fractal_lacunarity": ["Fractal lacunarity", 0.1, 4.0, 0.1],
		"fractal_gain": ["Fractal gain", 0.0, 2.0, 0.05],
		"chunk_width": ["Chunk width", 8, 128, 1],
		"chunk_height": ["Chunk height", 8, 128, 1],
		"chunk_refresh_frames": ["Chunk refresh frames", 1, 120, 1],
		"water_max_alt": ["Water max altitude", -1.0, 1.0, 0.01],
		"sand_max_alt": ["Sand max altitude", -1.0, 1.0, 0.01],
		"swamp_special_alt": ["Swamp special altitude", -1.0, 1.0, 0.01],
		"ground_chance_a": ["Ground chance A", -1.0, 1.0, 0.05],
		"ground_chance_b": ["Ground chance B", -1.0, 1.0, 0.05],
		"ground_chance_c": ["Ground chance C", -1.0, 1.0, 0.05],
		"bush_min_alt": ["Bush min altitude", -1.0, 1.0, 0.01],
		"bush_max_alt": ["Bush max altitude", -1.0, 1.0, 0.01],
		"bush_min_chance": ["Bush min chance", -1.0, 1.0, 0.05],
		"tree_min_alt": ["Tree min altitude", -1.0, 1.0, 0.01],
		"tree_min_chance": ["Tree min chance", -1.0, 1.0, 0.05],
	}
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	var fail := 0
	var pinned_order: Array = panel._spin_boxes.keys().filter(func(k): return expected.has(k))
	if pinned_order != expected.keys():
		printerr(
			"FAIL map_settings_rows_from_hints row order=%s want %s"
			% [pinned_order, expected.keys()]
		)
		fail += 1
	for key in expected.keys():
		if not panel._spin_boxes.has(key):
			continue
		var want: Array = expected[key]
		var spin: SpinBox = panel._spin_boxes[key]
		var label: String = spin.get_parent().get_child(0).text
		var got := [label, spin.min_value, spin.max_value, spin.step]
		if label != want[0] or not is_equal_approx(spin.min_value, want[1]) \
				or not is_equal_approx(spin.max_value, want[2]) or not is_equal_approx(spin.step, want[3]):
			printerr("FAIL map_settings_rows_from_hints %s got %s want %s" % [key, got, want])
			fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_rows_from_hints (%s rows)" % expected.size())
	return fail

func _test_new_param_needs_no_ui_code() -> int:
	## A field added to MapGenParams reaches to_dict() and gets a Map Settings
	## row with no other edits. A runtime subclass stands in for that edit.
	print("-- test_new_param_needs_no_ui_code")
	var script := GDScript.new()
	script.source_code = (
		"extends MapGenParams\n"
		+ "@export_range(0, 9) var dummy_count: int = 3\n"
		+ "@export_range(-2.0, 2.0, 0.25) var dummy_ratio: float = 0.5\n"
	)
	if script.reload() != OK:
		printerr("FAIL new_param_needs_no_ui_code: dummy subclass does not compile")
		return 1
	var params = script.new()
	var expected := {
		"dummy_count": ["Dummy count", 0, 9, 1, 3],
		"dummy_ratio": ["Dummy ratio", -2.0, 2.0, 0.25, 0.5],
	}
	var fail := 0
	var data: Dictionary = params.to_dict()
	for key in expected.keys():
		if not data.has(key) or data[key] != expected[key][4]:
			printerr("FAIL new_param_needs_no_ui_code to_dict() %s=%s want %s" % [key, data.get(key), expected[key][4]])
			fail += 1

	var map_gen = root.get_node("MapGen")
	var saved_params = map_gen.params
	map_gen.params = params
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	map_gen.params = saved_params
	for key in expected.keys():
		var want: Array = expected[key]
		if not panel._spin_boxes.has(key):
			printerr("FAIL new_param_needs_no_ui_code %s has no Map Settings row" % key)
			fail += 1
			continue
		var spin: SpinBox = panel._spin_boxes[key]
		var got := [spin.get_parent().get_child(0).text, spin.min_value, spin.max_value, spin.step, spin.value]
		if got[0] != want[0] or not is_equal_approx(got[1], want[1]) or not is_equal_approx(got[2], want[2]) \
				or not is_equal_approx(got[3], want[3]) or not is_equal_approx(got[4], want[4]):
			printerr("FAIL new_param_needs_no_ui_code %s row %s want %s" % [key, got, want])
			fail += 1

	if fail == 0:
		panel._spin_boxes["dummy_count"].value = 7
		panel._spin_boxes["dummy_ratio"].value = -1.25
		panel.apply_to_params(params)
		var copy = script.new()
		copy.from_dict(params.to_dict())
		if copy.dummy_count != 7 or not is_equal_approx(copy.dummy_ratio, -1.25):
			printerr(
				"FAIL new_param_needs_no_ui_code round-trip dummy_count=%s dummy_ratio=%s"
				% [copy.dummy_count, copy.dummy_ratio]
			)
			fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_new_param_needs_no_ui_code")
	return fail

func _test_biome_seed_panel_round_trip() -> int:
	## A biome_seed above 2^31 - 1 (randi() returns up to 2^32 - 1) survives the
	## Map Settings panel unchanged and has its own seed row, not a SpinBox.
	print("-- test_biome_seed_panel_round_trip")
	var fail := 0
	var big := 4000000000
	var params = MapGenParams.make_defaults()
	params.biome_seed = big
	var map_gen = root.get_node("MapGen")
	var saved_params = map_gen.params
	map_gen.params = params
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	map_gen.params = saved_params
	panel.load_from_params(params)
	if panel._spin_boxes.has("biome_seed"):
		printerr("FAIL biome_seed_panel: biome_seed has a SpinBox row")
		fail += 1
	if panel.seed_biome.text != str(big):
		printerr("FAIL biome_seed_panel: row shows %s want %s" % [panel.seed_biome.text, big])
		fail += 1
	var out = MapGenParams.make_defaults()
	panel.apply_to_params(out)
	if out.biome_seed != big:
		printerr("FAIL biome_seed_panel: round-trip %s want %s" % [out.biome_seed, big])
		fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_biome_seed_panel_round_trip")
	return fail


func _test_chunk_refresh_frames() -> int:
	## chunk_refresh_frames sets how many _process calls pass before the chunk
	## under the local player is generated.
	print("-- test_chunk_refresh_frames")
	# Let earlier tests' queue_free() run so this instance is /root/Flagoria,
	# the path TileMap._process uses to find the player.
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	if scene.get_path() != NodePath("/root/Flagoria"):
		printerr("FAIL chunk_refresh_frames scene at %s, not /root/Flagoria" % scene.get_path())
		scene.queue_free()
		return 1
	var world = scene.get_node("World/worldMap")
	var far_cell := Vector2i(500, 500)
	var player := Node2D.new()
	player.name = str(world.multiplayer.get_unique_id())
	player.position = world.map_to_local(far_cell)
	scene.get_node("World").add_child(player)
	world.player_spawned = true

	var fail := 0
	for frames in [15, 4]:
		var params = MapGenParams.make_defaults()
		params.chunk_refresh_frames = frames
		world.apply_map_params(params)
		world.count = 0
		for i in range(frames - 1):
			world._process(0.0)
		if world.get_cell_source_id(0, far_cell) != -1:
			printerr("FAIL chunk_refresh_frames=%s generated before frame %s" % [frames, frames])
			fail += 1
			continue
		world._process(0.0)
		if world.get_cell_source_id(0, far_cell) == -1:
			printerr("FAIL chunk_refresh_frames=%s not generated on frame %s" % [frames, frames])
			fail += 1
			continue
		print("PASS chunk_refresh_frames=%s" % frames)

	scene.queue_free()
	return fail

func _test_map_save_round_trip() -> int:
	## Every MapGenParams value survives save + load exactly, and the loaded
	## inputs regenerate the same origin chunk on layers 0 and 1. Float inputs
	## use all 17 significant digits.
	print("-- test_map_save_round_trip")
	var fail := 0
	var params = MapGenParams.make_defaults()
	var defaults: Dictionary = params.to_dict()
	for key in defaults.keys():
		if typeof(defaults[key]) == TYPE_INT:
			params.set(key, defaults[key] + 3)
		else:
			params.set(key, defaults[key] + 1.0 / 3.0)
	var saved = MapSave.save_map(params, "test_round_trip")
	var loaded = MapSave.load_map(saved["path"])
	if saved["error"] != "" or loaded["error"] != "":
		printerr("FAIL map_save_round_trip save=%s load=%s" % [saved["error"], loaded["error"]])
		return 1
	var want: Dictionary = params.to_dict()
	var got: Dictionary = loaded["params"].to_dict()
	for key in want.keys():
		if typeof(got[key]) != typeof(want[key]) or got[key] != want[key]:
			printerr("FAIL map_save_round_trip %s saved=%s loaded=%s" % [key, want[key], got[key]])
			fail += 1
	DirAccess.remove_absolute(saved["path"])

	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var map_gen = root.get_node("MapGen")
	var active_params = map_gen.params
	var original = MapGenParams.make_defaults()
	original.altitude_seed = 4242
	original.moisture_seed = 5252
	original.temperature_seed = 6262
	original.items_seed = 7272
	original.water_max_alt = 0.4
	original.sand_max_alt = 0.48
	map_gen.params = original
	var save_error: String = map_gen.save_map_inputs("test_same_map")
	map_gen.params = MapGenParams.make_defaults()
	var load_error: String = map_gen.load_map_inputs(MapSave.path_for("test_same_map"))
	var reloaded: MapGenParams = map_gen.params
	map_gen.params = active_params
	DirAccess.remove_absolute(MapSave.path_for("test_same_map"))
	if save_error != "" or load_error != "":
		printerr("FAIL map_save_round_trip save=%s load=%s" % [save_error, load_error])
		scene.queue_free()
		return fail + 1

	var cells := {}
	world.apply_map_params(original)
	world.generate_chunk(Vector2(0, 0))
	for cell in world.get_used_cells(0):
		cells[cell] = [world.get_cell_atlas_coords(0, cell), world.get_cell_atlas_coords(1, cell)]
	world.apply_map_params(reloaded)
	world.generate_chunk(Vector2(0, 0))
	var mismatched := 0
	for cell in cells.keys():
		if cells[cell] != [world.get_cell_atlas_coords(0, cell), world.get_cell_atlas_coords(1, cell)]:
			mismatched += 1
	if cells.size() == 0 or mismatched > 0 or world.get_used_cells(0).size() != cells.size():
		printerr("FAIL map_save_round_trip regenerated chunk: %s of %s cells differ" % [mismatched, cells.size()])
		fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_map_save_round_trip (%s values, %s cells)" % [want.size(), cells.size()])
	return fail

func _test_map_save_rejects_bad_files() -> int:
	## Unknown versions, malformed files and unresolved seeds give clear errors.
	print("-- test_map_save_rejects_bad_files")
	var fail := 0
	var unresolved = MapSave.save_map(MapGenParams.make_defaults(), "test_unresolved")
	if not "unresolved" in unresolved["error"] or FileAccess.file_exists(MapSave.path_for("test_unresolved")):
		printerr("FAIL map_save_rejects_bad_files unresolved seeds: %s" % unresolved["error"])
		fail += 1

	var cases := {
		"test_future_version": ['{"format_version": 99, "params": {}}', "version 99"],
		"test_no_version": ['{"params": {}}', "no format_version"],
		"test_not_json": ["not json", "invalid JSON"],
		"test_no_params": ['{"format_version": 1}', "no params"],
	}
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	for save_name in cases.keys():
		var path := MapSave.path_for(save_name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(cases[save_name][0])
		file.close()
		var result = MapSave.load_map(path)
		DirAccess.remove_absolute(path)
		if result["params"] != null or not cases[save_name][1] in result["error"]:
			printerr(
				"FAIL map_save_rejects_bad_files %s error=%s want it to mention %s"
				% [save_name, result["error"], cases[save_name][1]]
			)
			fail += 1
	if fail == 0:
		print("PASS test_map_save_rejects_bad_files")
	return fail


func _test_player_spawn_no_missing_nodes() -> int:
	## Spawning a player must not log "Node not found" (stale @onready paths).
	## Runs tests/spawn_player_probe.gd in a separate headless process, because
	## engine errors cannot be read back in-process. --quit-after bounds the run.
	print("-- test_player_spawn_no_missing_nodes")
	var output := []
	var code := OS.execute(
		OS.get_executable_path(),
		[
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--quit-after", "600", "--script", "res://tests/spawn_player_probe.gd",
		],
		output,
		true
	)
	var log_text: String = "".join(output)
	var fail := 0
	if code != 0 or not log_text.contains("SPAWN_PROBE_OK"):
		printerr("FAIL player_spawn_no_missing_nodes probe exit=%s" % code)
		fail += 1
	for line in log_text.split("\n"):
		if line.contains("Node not found"):
			printerr("FAIL player_spawn_no_missing_nodes: %s" % line.strip_edges())
			fail += 1
	if fail == 0:
		print("PASS test_player_spawn_no_missing_nodes")
	return fail


func _test_server_port_from_args() -> int:
	## `-- --server [--port N]` picks the dedicated-server port; 0 means GUI launch.
	print("-- test_server_port_from_args")
	var main_script = load("res://flagoria_main.gd")
	var cases := [
		[[], 0],
		[["--port", "9799"], 0],
		[["--server"], 9786],
		[["--server", "--port", "9799"], 9799],
		[["--server", "--port=9799"], 9799],
		[["--server", "--port", "abc"], -1],
		[["--server", "--port"], -1],
		[["--server", "--port=0"], -1],
		[["--server", "--port", "65536"], -1],
	]
	var fail := 0
	for case in cases:
		var got: int = main_script.server_port_from_args(PackedStringArray(case[0]))
		if got != case[1]:
			printerr("FAIL server_port_from_args %s = %s, want %s" % [case[0], got, case[1]])
			fail += 1
	if fail == 0:
		print("PASS test_server_port_from_args (%s cases)" % cases.size())
	return fail


func _free_udp_port() -> int:
	## A random UDP port in 20000-59999 that ENet can bind right now, or 0.
	## Fixed ports fail when another run or service holds them.
	for attempt in range(50):
		var port := randi_range(20000, 59999)
		var probe := ENetMultiplayerPeer.new()
		var err := probe.create_server(port)
		probe.close()
		if err == OK:
			return port
	return 0


func _test_dedicated_server_join() -> int:
	## Boot `-- --server` as a second headless process, join it through the
	## main scene's normal Join path, and check that the client gets the map
	## params and its own player, and that the host spawned no local player.
	print("-- test_dedicated_server_join")
	var timeout_ms := 30000
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL dedicated_server_join found no free UDP port")
		return 1
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("FAIL dedicated_server_join could not start the server process")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var fail := 0
	var client_id := 0
	var world: Node = scene.get_node("World")
	if scene.get_path() != NodePath("/root/Flagoria"):
		printerr("FAIL dedicated_server_join scene at %s, not /root/Flagoria" % scene.get_path())
		fail += 1
	else:
		# ENet retries the handshake, so joining before the server binds is fine.
		scene.add_player_joined(port)
		var deadline := Time.get_ticks_msec() + timeout_ms
		while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
			client_id = scene.multiplayer.get_unique_id()
			var params_ok: bool = scene.world_params != null and scene.world_params.altitude_seed != 0
			if params_ok and world.has_node(str(client_id)):
				break
			await process_frame
		var params: MapGenParams = scene.world_params
		if not OS.is_process_running(pid):
			printerr("FAIL dedicated_server_join server process exited early")
			fail += 1
		elif params == null or params.altitude_seed == 0 or params.items_seed == 0:
			printerr("FAIL dedicated_server_join no map params from server within %s ms" % timeout_ms)
			fail += 1
		elif not world.has_node(str(client_id)):
			printerr("FAIL dedicated_server_join server did not spawn player %s" % client_id)
			fail += 1
		elif world.has_node("1"):
			printerr("FAIL dedicated_server_join server spawned a local player")
			fail += 1

	OS.kill(pid)
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	if fail == 0:
		print("PASS test_dedicated_server_join (client %s)" % client_id)
	return fail
