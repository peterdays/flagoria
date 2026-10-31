extends SceneTree
## Headless test entry point for CI.
## Run all:  godot --headless --path . --script res://tests/run_tests.gd
## Run some: godot --headless --path . --script res://tests/run_tests.gd -- --only=map_zoom[,mob_chase]
## List:     godot --headless --path . --script res://tests/run_tests.gd -- --list
## Every `func _test_*() -> int` in this file and in every `tests/**/test_*.gd`
## file is registered automatically: files sorted by path, tests in source
## order. A test name used twice fails the run.
## Exit 0 on success, 1 on failure or an unknown test name. A SCRIPT ERROR
## logged while a test runs, even inside a helper it goes on past, fails it.

const TestHelpers = preload("res://tests/helpers/test_helpers.gd")
const TESTS_DIR := "res://tests"

## Shared helpers live in tests/helpers/test_helpers.gd. Test files extend it;
## the tests still in this file reach it through the forwarders below, which
## go away once those tests have moved to their own files.
var _helpers := TestHelpers.new()


func _initialize() -> void:
	call_deferred("_run")


class _ScriptErrorCount extends Logger:
	## Godot may log from any thread.
	var _count := 0
	var _lock := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			_lock.lock()
			_count += 1
			_lock.unlock()

	func count() -> int:
		_lock.lock()
		var n := _count
		_lock.unlock()
		return n


func _run() -> void:
	_helpers.tree = self
	var skipped := {}
	var names: Array[String] = []
	var owners := {}  # test name -> the object whose method it is
	var files := {}  # test name -> the file that defines it
	var duplicates: Array[String] = []
	var runner_path := (get_script() as GDScript).resource_path
	var paths := _find_test_files(TESTS_DIR)
	paths.append(runner_path)
	paths.sort()
	for path in paths:
		var script: GDScript = get_script() if path == runner_path else load(path)
		var found := _registered_tests(script.source_code, skipped, path.trim_prefix("res://"))
		if found.is_empty():
			continue
		var target: Object = self
		if path != runner_path:
			target = script.new()
			target.tree = self
		for test_name in found:
			if test_name in owners:
				duplicates.append("%s is defined in %s and in %s" % [test_name.trim_prefix("_"), files[test_name], path])
				continue
			names.append(test_name)
			owners[test_name] = target
			files[test_name] = path
	for test_name in skipped:
		printerr("WARNING: skipped %s: %s" % [test_name, skipped[test_name]])
	if not duplicates.is_empty():
		for line in duplicates:
			printerr("Duplicate test name: " + line)
		printerr("Test names must be unique across all test files.")
		quit(1)
		return
	var picked := names
	for arg in OS.get_cmdline_user_args():
		if arg == "--list":
			for test_name in names:
				print(test_name.trim_prefix("_"))
			quit(0)
			return
		if arg.begins_with("--only="):
			var wanted := arg.trim_prefix("--only=").split(",", false)
			if wanted.is_empty():
				printerr("--only= needs at least one test name, e.g. --only=map_zoom (use --list to see the names)")
				quit(1)
				return
			picked = _filter_tests(names, wanted, skipped)
			if picked.is_empty():
				quit(1)
				return
		else:
			printerr("Unknown argument: %s (expected --only=<name>[,<name>] or --list)" % arg)
			quit(1)
			return
	var failures := 0
	var script_errors := _ScriptErrorCount.new()
	OS.add_logger(script_errors)
	for test_name in picked:
		var before := script_errors.count()
		var result = await (owners[test_name] as Object).call(test_name)
		# Let nodes the test queued for freeing leave the tree, so the next
		# test's scene keeps its own name (for example /root/Flagoria).
		await process_frame
		var raised := script_errors.count() - before
		if raised > 0:
			printerr("FAIL %s logged %d SCRIPT ERROR(s)" % [test_name.trim_prefix("_"), raised])
		failures += (result if result is int else 1) + raised
	print("Ran %d of %d tests." % [picked.size(), names.size()])
	if failures == 0:
		print("All tests passed.")
		quit(0)
	else:
		print("Tests failed: %s" % failures)
		quit(1)


func _find_test_files(dir: String) -> Array[String]:
	## Every `test_*.gd` under dir, at any depth.
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_find_test_files(dir.path_join(sub)))
	return found


func _registered_tests(source: String, skipped: Dictionary, file := "") -> Array[String]:
	## Every `func _test_*() -> int` in source, in source order. Adding a
	## test is just writing the function; nothing else needs to list it.
	## A test-like function that does not match is left out and recorded in
	## skipped ("name (<file> line N)" -> reason), so it cannot silently drop
	## out of the run.
	var found: Array[String] = []
	var pattern := RegEx.create_from_string("(?m)^func (_test_[a-z0-9_]+)\\(\\)")
	for m in pattern.search_all(source):
		found.append(m.get_string(1))
	var loose := RegEx.create_from_string("(?mi)^([ \\t]*)(static[ \\t]+)?func[ \\t]+(_?test_\\w*)[ \\t]*\\(([^)]*)\\)")
	var exact := RegEx.create_from_string("^func _test_[a-z0-9_]+\\(\\)$")
	for m in loose.search_all(source):
		if exact.search(m.get_string(0)) != null:
			continue
		var test_name := m.get_string(3)
		var reasons: Array[String] = []
		if m.get_string(1) != "":
			reasons.append("it is indented; tests must be top-level")
		if m.get_string(2) != "":
			reasons.append("it is static; drop `static`")
		if not test_name.to_lower().begins_with("_test_"):
			reasons.append("the name must start with `_test_`")
		if test_name != test_name.to_lower():
			reasons.append("the name has uppercase letters; use lowercase")
		if m.get_string(4).strip_edges() != "":
			reasons.append("it takes parameters; tests take none")
		if reasons.is_empty():
			reasons.append("write it exactly as `func _test_<lowercase_name>()`")
		if test_name in found:
			reasons.append("the top-level %s is the one that runs" % test_name)
		var line := source.substr(0, m.get_start()).count("\n") + 1
		var where := "line %d" % line if file == "" else "%s line %d" % [file, line]
		skipped["%s (%s)" % [test_name, where]] = "; ".join(reasons)
	return found


func _only_problem(names: Array[String], raw: String, skipped: Dictionary) -> String:
	## Why `--only=<raw>` cannot run, or "" when it names a registered test.
	## Matches with or without the `test_` prefix, and points a name that only
	## a skipped function has at that function's WARNING.
	var key := _only_key(raw)
	if key in names:
		return ""
	for label: String in skipped:
		if _only_key(label.get_slice(" ", 0).to_lower()) == key.to_lower():
			return "Test %s is not run: see the WARNING for %s above." % [raw, label]
	return "No test named %s." % raw


func _only_key(raw: String) -> String:
	## The function name `--only=<raw>` asks for: `x`, `test_x` and `_test_x`
	## all mean `_test_x`.
	return "_test_" + raw.trim_prefix("_").trim_prefix("test_")


func _filter_tests(names: Array[String], wanted: PackedStringArray, skipped: Dictionary) -> Array[String]:
	## The tests named in wanted (with or without the `test_` prefix), in run
	## order. Empty, after printing why, if one does not match.
	var keys: Array[String] = []
	for raw in wanted:
		var problem := _only_problem(names, raw, skipped)
		if problem != "":
			printerr(problem)
			if problem.begins_with("No test named"):
				printerr("Known tests:")
				for test_name in names:
					printerr("  " + test_name.trim_prefix("_"))
			return []
		keys.append(_only_key(raw))
	var picked: Array[String] = []
	for test_name in names:
		if test_name in keys:
			picked.append(test_name)
	return picked


func _spawn_params(seed_value: int, biome_frequency: float) -> MapGenParams:
	return _helpers._spawn_params(seed_value, biome_frequency)


func _tap_sequence(pos: Vector2, steps: Array) -> void:
	_helpers._tap_sequence(pos, steps)


func _test_smoke_true() -> int:
	## Trivial sanity check that the headless runner executes and reports.
	print("-- test_smoke_true")
	if true:
		print("PASS test_smoke_true")
		return 0
	printerr("FAIL test_smoke_true")
	return 1


func _test_chop_bush() -> int:
	## A bush chops like a tree (#267): two hits at 140 ms and 460 ms, each
	## with a bush hit sound, the hit sheet drawn in place of the hidden bush
	## tile (its collision kept) and the leaves fx. At 560 ms it becomes a
	## walkable BUSH_STUMP with the break sound and the falling leaves, no
	## puff, and gives the bush's wood, less than a tree's. The hero boxed in
	## by bushes can then walk out through the cut one.
	print("-- test_chop_bush")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(4, 16):
		for y in range(4, 14):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	var home := Vector2i(10, 10)
	for x in range(9, 12):
		for y in range(9, 12):
			if Vector2i(x, y) != home:
				world.set_cell(1, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.BUSH)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(home))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)  # the test steps the chop clock itself
	var inventory: Inventory = scene.get_node("Inventory")
	var bush_type := InteractableCatalog.by_id("bush")
	var bush_wood := bush_type.amount_of(Inventory.WOOD)
	if bush_wood < 1 or bush_wood >= InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL chop_bush: bush wood %s is not less than a tree's" % bush_wood)
		fail += 1
	var bush := Vector2i(10, 9)
	var run_to := func(t: float) -> void:
		interaction.step_chop(t - maxf(interaction.chop_time, 0.0))
	var walks_up := func() -> bool:
		await physics_frame
		await physics_frame
		var body: CollisionShape2D = player.get_node("CollisionShape2D")
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = body.shape
		query.collision_mask = player.collision_mask
		query.exclude = [player.get_rid()]
		query.transform = Transform2D(0, player.global_position + body.position)
		query.motion = Vector2(0, -32)
		return world.get_world_2d().direct_space_state.cast_motion(query)[0] >= 1.0
	if await walks_up.call():
		printerr("FAIL chop_bush: the bush at %s does not block before the chop" % bush)
		fail += 1

	interaction.set_mode(Interaction.Mode.INTERACT)
	if not interaction.start_chop(bush) or interaction.chop_type != bush_type:
		printerr("FAIL chop_bush: could not start chopping the bush at %s" % bush)
		fail += 1
	run_to.call(0.15)
	if world.choppable(bush) != bush_type or world.get_cell_alternative_tile(1, bush) != Interaction.HIDDEN_ALT \
			or not interaction._hit.visible or interaction._hit.frame != 0 or not interaction._fx.visible \
			or interaction._fx.frame != 0 or interaction.sfx_log.size() != 1 \
			or not bush_type.hit_sounds.has(interaction.sfx_log[0]):
		printerr("FAIL chop_bush: first hit: alt %s, hit %s/%s, fx %s/%s, sounds %s"
				% [world.get_cell_alternative_tile(1, bush), interaction._hit.visible, interaction._hit.frame,
				interaction._fx.visible, interaction._fx.frame, interaction.sfx_log])
		fail += 1
	if await walks_up.call():
		printerr("FAIL chop_bush: the hidden bush tile lost its collision")
		fail += 1
	run_to.call(0.2)
	if interaction._hit.frame != 1 or interaction._fx.frame != 1:
		printerr("FAIL chop_bush: at 200 ms hit frame %s, fx frame %s" % [interaction._hit.frame, interaction._fx.frame])
		fail += 1
	run_to.call(0.3)
	if interaction._hit.visible or interaction._fx.visible or world.get_cell_alternative_tile(1, bush) != 0:
		printerr("FAIL chop_bush: the hit did not end by 300 ms")
		fail += 1
	run_to.call(0.55)
	if world.choppable(bush) != bush_type or inventory.count_of(Inventory.WOOD) != 0 or interaction.sfx_log.size() != 2:
		printerr("FAIL chop_bush: before 560 ms bush %s, wood %s, sounds %s"
				% [world.choppable(bush), inventory.count_of(Inventory.WOOD), interaction.sfx_log.size()])
		fail += 1
	run_to.call(0.57)
	if world.choppable(bush) != null or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, bush) != TileCatalog.BUSH_STUMP \
			or inventory.count_of(Inventory.WOOD) != bush_wood or interaction._puff.visible \
			or not interaction._fx.visible or interaction._fx.frame != 2 or interaction._hit.visible \
			or interaction.sfx_log.size() != 3 or interaction.sfx_log[2] != bush_type.fell_sounds[0]:
		printerr("FAIL chop_bush: at 560 ms decor %s, wood %s, puff %s, fx %s/%s, sounds %s"
				% [world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, bush), inventory.count_of(Inventory.WOOD),
				interaction._puff.visible, interaction._fx.visible, interaction._fx.frame, interaction.sfx_log])
		fail += 1
	run_to.call(0.75)
	if not interaction._fx.visible or interaction._fx.frame != 3:
		printerr("FAIL chop_bush: at 750 ms fx %s/%s, want frame 3" % [interaction._fx.visible, interaction._fx.frame])
		fail += 1
	interaction.step_chop(1.0)
	if interaction.chopping() or interaction._fx.visible or inventory.count_of(Inventory.WOOD) != bush_wood:
		printerr("FAIL chop_bush: after the chop: chopping %s, fx %s, wood %s"
				% [interaction.chopping(), interaction._fx.visible, inventory.count_of(Inventory.WOOD)])
		fail += 1
	if not world.is_clear_ground(bush) or not await walks_up.call():
		printerr("FAIL chop_bush: the hero is still blocked by the BUSH_STUMP at %s" % bush)
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_bush")
	return fail


func _test_cut_bush_stays_stump_and_regrows() -> int:
	## A cut bush keeps its BUSH_STUMP when its chunk is drawn again (and
	## predict_cell sees it as open ground), then regrows into the same bush,
	## with its collision, once regrow_delay seconds of play have passed.
	print("-- test_cut_bush_stays_stump_and_regrows")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	var bush_type := InteractableCatalog.by_id("bush")
	var bush := Vector2i(1 << 20, 0)
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(1):
			if world.choppable(cell) == bush_type:
				bush = cell
				break
		if bush.x != 1 << 20:
			break
	if bush.x == 1 << 20:
		printerr("FAIL cut_bush_stays_stump_and_regrows: no bush near the origin on any seed")
		scene.queue_free()
		return 1
	world.predict_cell(bush)  # cached before the cut
	world.regrow_delay = 30.0
	world.play_time = 100.0
	if world.cut_choppable(bush) != bush_type or world.cut_choppable(bush) != null:
		printerr("FAIL cut_bush_stays_stump_and_regrows: cut_choppable did not cut %s exactly once" % bush)
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	if world.choppable(bush) != null or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, bush) != TileCatalog.BUSH_STUMP:
		printerr("FAIL cut_bush_stays_stump_and_regrows: %s grew back when the chunk was drawn again" % bush)
		fail += 1
	if world.predict_cell(bush)[1] != TileCatalog.BUSH_STUMP or not world.predicted_clear(bush) or not world.is_clear_ground(bush):
		printerr("FAIL cut_bush_stays_stump_and_regrows: predict_cell %s for the stump" % [world.predict_cell(bush)])
		fail += 1
	world.play_time = 129.9
	if world.regrow_due() != 0 or world.choppable(bush) != null:
		printerr("FAIL cut_bush_stays_stump_and_regrows: %s regrew before the delay" % bush)
		fail += 1
	world.play_time = 130.1
	if world.regrow_due() != 1:
		printerr("FAIL cut_bush_stays_stump_and_regrows: %s did not regrow after the delay" % bush)
		fail += 1
	var top = world.get_cell_tile_data(1, bush)
	if world.get_cell_atlas_coords(1, bush) != TileCatalog.BUSH or world.get_cell_source_id(world.GROUND_DECOR_LAYER, bush) != -1 \
			or top == null or top.get_collision_polygons_count(0) == 0 or world.predict_cell(bush)[1] != TileCatalog.BUSH:
		printerr("FAIL cut_bush_stays_stump_and_regrows: %s is %s after regrowing, want a BUSH with collision"
				% [bush, world.get_cell_atlas_coords(1, bush)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_cut_bush_stays_stump_and_regrows")
	return fail


func _test_number_pad_first_key_replaces() -> int:
	## Opening the pad selects the field's text, so the first key replaces the
	## old value instead of adding to it; later keys add as usual. A field left
	## holding only "-" or "." when the pad closes gets its old value back.
	print("-- test_number_pad_first_key_replaces")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var pad = panel.get_node("NumberPad")
	var fail := 0
	var seed_field: LineEdit = panel.find_child("ItemsSeed")
	for how in ["focus", "tap"]:
		seed_field.release_focus()
		pad.close()
		await process_frame
		seed_field.text = "4295"
		if how == "focus":
			seed_field.grab_focus()
		else:
			_tap_sequence(seed_field.get_global_rect().get_center(), ["mouse_down", "touch_down", "mouse_up", "touch_up"])
		await process_frame
		await process_frame
		if not pad.visible or seed_field.get_selected_text() != "4295":
			printerr("FAIL number_pad_first_key %s: pad open=%s selected=%s" % [how, pad.visible, seed_field.get_selected_text()])
			fail += 1
		for key in ["Digit7", "Digit1"]:
			pad.find_child(key, true, false).pressed.emit()
		if seed_field.text != "71":
			printerr("FAIL number_pad_first_key %s: typed 7 1 over 4295 gave %s want 71" % [how, seed_field.text])
			fail += 1
	pad.close()
	seed_field.release_focus()
	var spin: SpinBox = panel._spin_boxes["ground_chance_a"]
	var field := spin.get_line_edit()
	for lone in ["-", "."]:
		spin.value = 0.25
		await process_frame  # the SpinBox shows a new value a frame later
		field.grab_focus()
		await process_frame
		var old_text := field.text
		field.text = lone
		pad.find_child("OK", true, false).pressed.emit()
		if field.text != old_text or not is_equal_approx(spin.value, 0.25):
			printerr("FAIL number_pad_first_key lone %s gave text=%s value=%s want %s" % [lone, field.text, spin.value, old_text])
			fail += 1
		field.release_focus()
		await process_frame
	panel.queue_free()
	if fail == 0:
		print("PASS test_number_pad_first_key_replaces")
	return fail

func _test_number_pad_keycap_style() -> int:
	## The pad has its own keyboard look from the menu theme: keycaps for the
	## digits, a red Delete and a gold OK key, and a framed panel.
	print("-- test_number_pad_keycap_style")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var pad = panel.get_node("NumberPad")
	var fail := 0
	var theme: Theme = load("res://art/ui/main_menu_theme.tres")
	for type in ["KeyCap", "KeyCapDelete", "KeyCapOK"]:
		if not theme.get_type_variation_list(&"Button").has(StringName(type)):
			printerr("FAIL number_pad_keycap_style theme has no %s button style" % type)
			fail += 1
	panel.find_child("ItemsSeed").grab_focus()
	await process_frame
	var want := {"Digit5": &"KeyCap", "Delete": &"KeyCapDelete", "OK": &"KeyCapOK"}
	for key in want:
		var b: Button = pad.find_child(key, true, false)
		if b == null or b.theme_type_variation != want[key]:
			printerr("FAIL number_pad_keycap_style %s style %s want %s" % [key, b.theme_type_variation if b else "missing", want[key]])
			fail += 1
	if pad.get_node("Panel").theme_type_variation != &"KeyboardPanel":
		printerr("FAIL number_pad_keycap_style panel is not a KeyboardPanel")
		fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_number_pad_keycap_style")
	return fail

func _test_main_menu_letter_keyboard() -> int:
	## The join address field uses the in-game letter keyboard, in the same
	## keycap style as the number pad, instead of the OS keyboard: its keys
	## type letters, digits, "." and ":", the first key replaces the old text,
	## OK closes it, and a physical keyboard still types there.
	print("-- test_main_menu_letter_keyboard")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	var field: LineEdit = menu.address_entry
	var kb = menu.get_node_or_null("LetterKeyboard")
	var fail := 0
	if kb == null or field.virtual_keyboard_enabled:
		printerr("FAIL letter_keyboard address field has no in-game keyboard (os keyboard=%s)" % field.virtual_keyboard_enabled)
		scene.queue_free()
		return 1
	field.text = "old.host"
	field.grab_focus()
	await process_frame
	if not kb.visible or kb.target != field:
		printerr("FAIL letter_keyboard focusing the address field did not open the keyboard")
		fail += 1
	for key in ["Digit1", "Point", "Digit2", "Colon", "Digit9", "Digit0", "Delete", "Digit1"]:
		var b: Button = kb.find_child(key, true, false)
		if b == null:
			printerr("FAIL letter_keyboard no %s key" % key)
			fail += 1
			continue
		b.pressed.emit()
	if field.text != "1.2:91":
		printerr("FAIL letter_keyboard keys gave %s want 1.2:91" % field.text)
		fail += 1
	field.text = ""
	for key in ["l", "o", "c", "a", "l", "h", "o", "s", "t"]:
		kb.find_child(key, true, false).pressed.emit()
	if field.text != "localhost":
		printerr("FAIL letter_keyboard letter keys gave %s want localhost" % field.text)
		fail += 1
	for key in ["l", "Digit5", "Delete", "OK"]:
		var want_style: StringName = {"Delete": &"KeyCapDelete", "OK": &"KeyCapOK"}.get(key, &"KeyCap")
		if kb.find_child(key, true, false).theme_type_variation != want_style:
			printerr("FAIL letter_keyboard %s key is not styled %s" % [key, want_style])
			fail += 1
	kb.find_child("OK", true, false).pressed.emit()
	if kb.visible:
		printerr("FAIL letter_keyboard OK did not close the keyboard")
		fail += 1
	field.caret_column = field.text.length()
	for ch in ":7":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		root.push_input(ev)
	await process_frame
	if field.text != "localhost:7":
		printerr("FAIL letter_keyboard physical keys gave %s want localhost:7" % field.text)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_main_menu_letter_keyboard")
	return fail


func _test_discovery_messages() -> int:
	## A misnamed test, and an indented copy of a real test's name, are
	## reported by line, and `--only=` points at the WARNING for them instead
	## of saying there is no such test (or that a test that runs is skipped).
	print("-- test_discovery_messages")
	var fail := 0
	var source := "\n".join([
		"func _test_ok() -> int:",
		"func test_qa_x() -> int:",
		"class Inner:",
		"\tfunc _test_ok() -> int:",
	])
	var skipped := {}
	var names := _registered_tests(source, skipped)
	if names.size() != 1 or names[0] != "_test_ok":
		printerr("FAIL discovery_messages: registered %s, want [_test_ok]" % [names])
		fail += 1
	var want := {
		"test_qa_x (line 2)": "the name must start with `_test_`",
		"_test_ok (line 4)": "it is indented; tests must be top-level; the top-level _test_ok is the one that runs",
	}
	if skipped != want:
		printerr("FAIL discovery_messages: skipped %s, want %s" % [skipped, want])
		fail += 1
	for case in [
		["qa_x", "Test qa_x is not run: see the WARNING for test_qa_x (line 2) above."],
		["test_qa_x", "Test test_qa_x is not run: see the WARNING for test_qa_x (line 2) above."],
		["ok", ""],
		["nope", "No test named nope."],
	]:
		var got := _only_problem(names, case[0], skipped)
		if got != case[1]:
			printerr("FAIL discovery_messages: --only=%s says %s, want %s" % [case[0], got, case[1]])
			fail += 1
	if fail == 0:
		print("PASS test_discovery_messages")
	return fail

