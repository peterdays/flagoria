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


func _pre_biome_defaults() -> MapGenParams:
	return _helpers._pre_biome_defaults()


func _spawn_params(seed_value: int, biome_frequency: float) -> MapGenParams:
	return _helpers._spawn_params(seed_value, biome_frequency)


func _spawn_session(mode: String, joiners: int) -> int:
	return await _helpers._spawn_session(mode, joiners)


func _remove_dir(dir: String) -> void:
	_helpers._remove_dir(dir)


func _body_rect(player: Node) -> Rect2:
	return _helpers._body_rect(player)


func _respawn_follow_case(label: String, death: Vector2, spawn: Vector2, walk: Vector2,
		drop_ms: int, prior: int = 0) -> int:
	return await _helpers._respawn_follow_case(label, death, spawn, walk, drop_ms, prior)


func _walls_from_rows(rows: Array, family: String = WallSolver.STONE) -> Dictionary:
	return _helpers._walls_from_rows(rows, family)


func _structure_errors(text: String) -> Array[String]:
	return _helpers._structure_errors(text)


func _archipelago_land_masses(world, half: int) -> int:
	return _helpers._archipelago_land_masses(world, half)


func _biome_terrain_params(arch: bool) -> MapGenParams:
	return _helpers._biome_terrain_params(arch)


func _chunk_digest(world, centre: Vector2i, w: int) -> String:
	return _helpers._chunk_digest(world, centre, w)


func _tap_sequence(pos: Vector2, steps: Array) -> void:
	_helpers._tap_sequence(pos, steps)


func _free_udp_port() -> int:
	return _helpers._free_udp_port()


func _client_connected(smp: SceneMultiplayer, cpeer: ENetMultiplayerPeer) -> bool:
	return await _helpers._client_connected(smp, cpeer)


func _chase_spot(world, mob: Mob, tiles: int) -> Variant:
	return _helpers._chase_spot(world, mob, tiles)


func _contact_player(world_root: Node) -> CharacterBody2D:
	return _helpers._contact_player(world_root)


func _sword_on(player: Node2D, mob: Mob) -> void:
	_helpers._sword_on(player, mob)


func _ui_plays_since(ui, before: Dictionary) -> Dictionary:
	return _helpers._ui_plays_since(ui, before)


func _test_smoke_true() -> int:
	## Trivial sanity check that the headless runner executes and reports.
	print("-- test_smoke_true")
	if true:
		print("PASS test_smoke_true")
		return 0
	printerr("FAIL test_smoke_true")
	return 1


func _test_two_player_smoke() -> int:
	## The multiplayer gate (#45): a dedicated server and two clients, each its
	## own headless process (tests/late_join_probe.gd). Every peer sees both
	## players; then client A walks by holding an input action and both the
	## server and client B see A move to where A has it.
	print("-- test_two_player_smoke")
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL two_player_smoke found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("smoke_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var outs: Array[String] = []
	var pids: Array[int] = []
	for extra in [["--dedicated"], [], []]:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		# Each probe quits by itself after 90 s, whatever happens to this run.
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://tests/late_join_probe.gd", "--", "--port=%d" % port, "--out=" + outs[-1]]
		args.append_array(extra)
		pids.append(OS.create_process(OS.get_executable_path(), args))
		if outs.size() == 1:
			# Clients join once the server is up, so their spots are picked.
			var up := Time.get_ticks_msec() + 30000
			while Time.get_ticks_msec() < up and not FileAccess.file_exists(outs[0]):
				await process_frame
	var read := func(i: int) -> Dictionary:
		var text := FileAccess.get_file_as_string(outs[i])
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var seen := func(viewer: int, id: String) -> Vector2:
		## Where peer `viewer` sees player `id`, or Vector2.INF.
		var p = read.call(viewer).get("players", {}).get(id)
		return Vector2(p["pos"][0], p["pos"][1]) if p != null else Vector2.INF
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()

	var fail := 0
	var both_seen := func() -> bool:
		var ids := [read.call(1).get("id", ""), read.call(2).get("id", "")]
		for viewer in 3:
			for id in ids:
				if id in ["", "0", "1"] or seen.call(viewer, id) == Vector2.INF:
					return false
		return true
	var waited: bool = await wait_for.call(both_seen, 45000)
	var a: String = read.call(1).get("id", "")
	var b: String = read.call(2).get("id", "")
	if not waited:
		printerr("FAIL two_player_smoke not every peer sees both players: server %s, A %s, B %s"
				% [read.call(0), read.call(1), read.call(2)])
		fail += 1
	else:
		await wait_for.call(func() -> bool: return false, 500)  # let spawn landing settle
		var start: Vector2 = seen.call(1, a)
		var b_start: Vector2 = seen.call(2, a)
		# Walk until A has moved 4 px; a wall, water or the other player may
		# block a way, so try each in turn.
		var moved := false
		for action in ["ui_right", "ui_left", "ui_down", "ui_up"]:
			var walk := FileAccess.open(outs[1] + ".walk", FileAccess.WRITE)
			walk.store_string(action)
			walk.close()
			moved = await wait_for.call(func() -> bool:
				var own: Vector2 = seen.call(1, a)
				return own != Vector2.INF and own.distance_to(start) >= 4.0, 1500)
			DirAccess.remove_absolute(outs[1] + ".walk")
			if moved:
				break
		if not moved:
			printerr("FAIL two_player_smoke player %s did not move from %s in any direction: A %s"
					% [a, start, read.call(1)])
			fail += 1
		else:
			# Once A stops, both other peers see it where A has it.
			var synced := func() -> bool:
				var own: Vector2 = seen.call(1, a)
				return own != Vector2.INF and own.distance_to(seen.call(0, a)) < 1.0 \
						and own.distance_to(seen.call(2, a)) < 1.0 and own.distance_to(b_start) >= 4.0
			if not await wait_for.call(synced, 5000):
				printerr("FAIL two_player_smoke A %s is at %s on A, %s on the server, %s on B (was %s on B)"
						% [a, seen.call(1, a), seen.call(0, a), seen.call(2, a), b_start])
				fail += 1
		for i in 3:
			var errors: Array = read.call(i).get("errors", [])
			if not errors.is_empty():
				printerr("FAIL two_player_smoke peer %s logged errors: %s" % [i, errors])
				fail += 1

	for out in outs:
		FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	await wait_for.call(func() -> bool:
		for pid in pids:
			if OS.is_process_running(pid):
				return false
		return true, 10000)
	for pid in pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_remove_dir(dir)
	if fail == 0:
		print("PASS test_two_player_smoke (%s walked, seen by server and %s)" % [a, b])
	return fail


func _test_ingame_menu_open_resume() -> int:
	## During a match the HUD's three-bar menu button, or Esc, opens the in-game menu
	## and Resume, or Esc again, closes it. On the main menu Esc does nothing.
	## A closed menu leaves the open map to pinch zoom; an open one covers it.
	print("-- test_ingame_menu_open_resume")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var cam := Camera2D.new()
	var zoom := Node.new()
	zoom.set_script(load("res://Scripts/map_zoom.gd"))
	cam.add_child(zoom)
	root.add_child(cam)
	await process_frame
	var menu = scene.get_node_or_null("CanvasLayer1/InGameMenu")
	if menu == null:
		printerr("FAIL ingame_menu_open_resume: no in-game menu in the HUD")
		cam.queue_free()
		scene.queue_free()
		await process_frame
		return 1
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	if menu.is_open() or menu.menu_button.is_visible_in_tree():
		printerr("FAIL ingame_menu_open_resume: menu reachable from the main menu")
		fail += 1
	scene.get_node("CanvasLayer1").show()  # as Host and Join do
	var centre: Vector2 = scene.get_viewport().get_visible_rect().get_center()
	var corner: Vector2 = menu.menu_button.get_global_rect().get_center()
	if not menu.menu_button.is_visible_in_tree() or not zoom.starts_on_hud(corner) or zoom.starts_on_hud(centre):
		printerr("FAIL ingame_menu_open_resume: Menu button not shown, or the closed menu covers the map")
		fail += 1
	# A compact three-bar icon button, still a phone-sized tap target at
	# 1280x720, clear of the hearts and points in the other corner.
	var button_rect: Rect2 = menu.menu_button.get_global_rect()
	var tap_px: float = button_rect.size.x * 1280.0 / scene.get_viewport().get_visible_rect().size.x
	var hearts_rect: Rect2 = scene.get_node("CanvasLayer1/HeartsHud").get_global_rect()
	var score_rect: Rect2 = scene.get_node("CanvasLayer1/ScoreHud").get_global_rect()
	if menu.menu_button.text != "" or menu.menu_button.icon == null \
			or button_rect.size.x != button_rect.size.y or tap_px < 40.0 or tap_px > 48.5 \
			or button_rect.intersects(hearts_rect) or button_rect.intersects(score_rect):
		printerr(
			"FAIL ingame_menu_open_resume: menu button text=%s icon=%s rect=%s (%s px at 1280x720)"
			% [menu.menu_button.text, menu.menu_button.icon, button_rect, tap_px]
		)
		fail += 1
	menu.menu_button.pressed.emit()
	if not menu.is_open() or not zoom.starts_on_hud(centre):
		printerr("FAIL ingame_menu_open_resume: Menu button did not open the panel over the map")
		fail += 1
	menu.resume_button.pressed.emit()
	if menu.is_open() or not menu.menu_button.visible:
		printerr("FAIL ingame_menu_open_resume: Resume did not close the panel")
		fail += 1
	menu._unhandled_input(esc)
	var opened_by_esc: bool = menu.is_open()
	menu._unhandled_input(esc)
	if not opened_by_esc or menu.is_open():
		printerr("FAIL ingame_menu_open_resume: Esc open=%s, second Esc open=%s" % [opened_by_esc, menu.is_open()])
		fail += 1
	cam.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_ingame_menu_open_resume")
	return fail


func _test_ingame_menu_leave() -> int:
	## Main menu in the in-game menu returns to the main menu with no network
	## peer, players or errors left, and a second game hosts on the same port.
	## Runs tests/ingame_menu_probe.gd in its own process: leaving reloads the
	## current scene, which this test runner does not have.
	print("-- test_ingame_menu_leave")
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL ingame_menu_leave found no free UDP port")
		return 1
	var output := []
	var code := OS.execute(
		OS.get_executable_path(),
		[
			"--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "3000",
			"--script", "res://tests/ingame_menu_probe.gd", "--", "--port=%d" % port,
		],
		output,
		true
	)
	var log_text: String = "".join(output)
	if code != 0 or not log_text.contains("INGAME_MENU_PROBE_OK"):
		for line in log_text.split("\n"):
			if line.contains("ingame_menu_probe"):
				printerr(line)
		printerr("FAIL ingame_menu_leave probe exit=%s" % code)
		return 1
	print("PASS test_ingame_menu_leave")
	return 0


func _test_ingame_menu_save() -> int:
	## Save in the in-game menu writes the world being played as a world save
	## that load_world reads back with the same generation inputs, says so
	## under the buttons and keeps the menu open. A second save never
	## replaces the first; before the world has loaded nothing is written.
	print("-- test_ingame_menu_save")
	var fail := 0
	var ui = root.get_node("UiSfx")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer1/InGameMenu")
	scene.get_node("CanvasLayer1").show()  # as Host and Join do
	var before_saves := MapSave.list_saves().size()

	menu.menu_button.pressed.emit()
	var panel: Control = menu.get_node("Pause/Panel")
	var empty_height: float = panel.get_combined_minimum_size().y

	# The world as Host or Join leaves it: resolved seeds in world_params.
	var params := MapGenParams.make_defaults()
	params.altitude_seed = 4242
	params.ensure_seeds()
	params.water_max_alt = 0.37
	scene.world_params = params
	ui._last_ms.clear()
	var before_sfx: Dictionary = ui.plays.duplicate()
	menu.save_button.pressed.emit()
	var saves := MapSave.list_saves()
	var paths: Array[String] = []
	for row in saves:
		paths.append(row["path"])
	if saves.size() != before_saves + 1:
		printerr("FAIL ingame_menu_save: Save wrote %d files, want 1" % (saves.size() - before_saves))
		fail += 1
	else:
		var loaded := MapSave.load_world(saves[0]["path"])
		if loaded["error"] != "" or loaded["version"] != MapSave.FORMAT_VERSION \
				or loaded["world"].params.to_dict() != params.to_dict():
			printerr("FAIL ingame_menu_save: load_world error=%s version=%s same inputs=%s"
					% [loaded["error"], loaded["version"], loaded["world"] != null and loaded["world"].params.to_dict() == params.to_dict()])
			fail += 1
		var save_name: String = saves[0]["name"]
		var want := "Saved: %s %s" % [save_name.substr(5, 5), save_name.substr(11, 5).replace("-", ":")]
		if menu.status_label.text != want or not menu.status_label.is_visible_in_tree():
			printerr("FAIL ingame_menu_save: status '%s' for save %s, want '%s'" % [menu.status_label.text, save_name, want])
			fail += 1
		# One line, and the panel keeps the height it had before the save.
		var height: float = panel.get_combined_minimum_size().y
		if menu.status_label.get_line_count() != 1 or height != empty_height:
			printerr("FAIL ingame_menu_save: status on %d lines, panel %s tall, %s before the save"
					% [menu.status_label.get_line_count(), height, empty_height])
			fail += 1
	if not menu.is_open() or _ui_plays_since(ui, before_sfx).get("saved", 0) != 1:
		printerr("FAIL ingame_menu_save: menu open=%s, sounds %s" % [menu.is_open(), _ui_plays_since(ui, before_sfx)])
		fail += 1

	# A second save in the same second gets its own name.
	var again: Dictionary = menu.save_world()
	paths.append(again["path"])
	if again["error"] != "" or MapSave.list_saves().size() != before_saves + 2:
		printerr("FAIL ingame_menu_save: second save error=%s, %d files" % [again["error"], MapSave.list_saves().size() - before_saves])
		fail += 1
	var stamp: String = menu.auto_save_name({"year": 2026, "month": 3, "day": 4, "hour": 5, "minute": 6, "second": 7})
	if stamp != "2026-03-04 05-06-07" or stamp.validate_filename() != stamp:
		printerr("FAIL ingame_menu_save: auto name %s" % stamp)
		fail += 1

	# Before the world has loaded nothing is written.
	scene.world_params = null
	var early: Dictionary = menu.save_world()
	if early["error"] == "" or MapSave.list_saves().size() != before_saves + 2 or not menu.status_label.text.begins_with("Not saved"):
		printerr("FAIL ingame_menu_save: save before the world loaded error=%s status=%s" % [early["error"], menu.status_label.text])
		fail += 1

	menu.resume_button.pressed.emit()
	if menu.status_label.text != "":
		printerr("FAIL ingame_menu_save: status '%s' kept after Resume" % menu.status_label.text)
		fail += 1
	for path in paths:
		DirAccess.remove_absolute(path)
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_ingame_menu_save")
	return fail


func _test_quit_prompt_on_back() -> int:
	## Back (Android) or closing the window asks "Do you want to quit?"
	## instead of exiting, on the main menu and in a match. Cancel, Esc or a
	## second back closes the prompt and the game carries on; Quit closes the
	## network session and quits. The world is not paused behind the prompt.
	print("-- test_quit_prompt_on_back")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var prompt = scene.get_node_or_null("QuitLayer/QuitPrompt")
	if prompt == null:
		printerr("FAIL quit_prompt_on_back: no quit prompt in the main scene")
		scene.queue_free()
		await process_frame
		return 1
	var quits := []
	scene.quit_hook = func() -> void: quits.append(true)

	# Main menu: back opens the prompt, a second back closes it.
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if not prompt.is_open() or not quits.is_empty():
		printerr("FAIL quit_prompt_on_back: back on the main menu open=%s quits=%d" % [prompt.is_open(), quits.size()])
		fail += 1
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if prompt.is_open() or not quits.is_empty():
		printerr("FAIL quit_prompt_on_back: second back did not just close the prompt (open=%s quits=%d)" % [prompt.is_open(), quits.size()])
		fail += 1
	# Window close opens it too; Cancel closes it.
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var opened_by_close: bool = prompt.is_open()
	prompt.cancel_button.pressed.emit()
	if not opened_by_close or prompt.is_open() or not quits.is_empty():
		printerr("FAIL quit_prompt_on_back: window close open=%s, after Cancel open=%s quits=%d" % [opened_by_close, prompt.is_open(), quits.size()])
		fail += 1

	# In a match (a hosted session): Esc closes the prompt without opening the
	# in-game menu, the world keeps running, and Quit closes the session.
	var port := _free_udp_port()
	scene.enet_peer.create_server(port)
	scene.multiplayer.multiplayer_peer = scene.enet_peer
	scene.get_node("CanvasLayer1").show()  # as Host and Join do
	var menu = scene.get_node("CanvasLayer1/InGameMenu")
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	if prompt.is_open() or menu.is_open():
		printerr("FAIL quit_prompt_on_back: Esc in a match left prompt open=%s, in-game menu open=%s" % [prompt.is_open(), menu.is_open()])
		fail += 1
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if not prompt.is_open() or paused or not quits.is_empty():
		printerr("FAIL quit_prompt_on_back: back in a match open=%s paused=%s quits=%d" % [prompt.is_open(), paused, quits.size()])
		fail += 1
	prompt.quit_button.pressed.emit()
	if quits.size() != 1 or not scene.multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
			or scene.enet_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		printerr("FAIL quit_prompt_on_back: Quit quits=%d peer=%s" % [quits.size(), scene.multiplayer.multiplayer_peer])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_quit_prompt_on_back")
	return fail


func _test_resource_hud_in_scene() -> int:
	## In the real main scene, the local player's spawn shows the wood counter
	## centred at the top at the hearts' scale, starting at 0, and wood added
	## to the inventory updates it.
	print("-- test_resource_hud_in_scene")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.add_player(scene.multiplayer.get_unique_id())
	await process_frame
	var hud: ResourceHud = scene.get_node("CanvasLayer1/ResourceHud")
	var hearts: Control = scene.get_node("CanvasLayer1/HeartsHud")
	var menu_rect: Rect2 = scene.get_node("CanvasLayer1/InGameMenu").menu_button.get_global_rect()
	hud.follow_hearts()
	var hud_rect := hud.get_global_rect()
	var mid: float = scene.get_viewport().get_visible_rect().get_center().x
	if not hud.visible or hud.label.text != "0" or hud.scale != hearts.scale \
			or absf(hud_rect.get_center().x - mid) > 1.0 or hud_rect.intersects(menu_rect):
		printerr("FAIL resource_hud_in_scene: counter visible %s text '%s' at %s x%s"
				% [hud.visible, hud.label.text, hud_rect, hud.scale])
		fail += 1
	var inventory: Inventory = scene.get_node("Inventory")
	if inventory.add(Inventory.WOOD, 3) != 3 or inventory.count_of(Inventory.WOOD) != 3 or hud.label.text != "3":
		printerr("FAIL resource_hud_in_scene: counter '%s' after 3 wood" % hud.label.text)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_resource_hud_in_scene")
	return fail


func _test_explored_map() -> int:
	## Revealing marks every cell within 10 cells (Euclidean) of the hero, in
	## 32 x 32 chunks of 128-byte bitsets, across negative coordinates; a
	## second reveal at the same spot changes nothing and clear() forgets all.
	print("-- test_explored_map")
	var fail := 0
	var map := ExploredMap.new()
	var changed := map.reveal(Vector2i.ZERO)
	var want_chunks := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]
	if changed.size() != 4 or want_chunks.any(func(c): return not c in changed):
		printerr("FAIL explored_map changed chunks %s" % [changed])
		fail += 1
	if map.explored_count() != 317:  # lattice points with x^2 + y^2 <= 100
		printerr("FAIL explored_map %s cells explored, want 317" % map.explored_count())
		fail += 1
	for c in [[Vector2i(10, 0), true], [Vector2i(-10, 0), true], [Vector2i(8, -6), true],
			[Vector2i(-8, 7), false], [Vector2i(11, 0), false], [Vector2i(0, -11), false]]:
		if map.is_explored(c[0]) != c[1]:
			printerr("FAIL explored_map is_explored(%s) != %s" % c)
			fail += 1
	if ExploredMap.chunk_of(Vector2i(-1, -33)) != Vector2i(-1, -2) or ExploredMap.chunk_of(Vector2i(31, 32)) != Vector2i(0, 1):
		printerr("FAIL explored_map chunk_of")
		fail += 1
	if map.chunk_bits(Vector2i.ZERO).size() != ExploredMap.CHUNK_BYTES or not map.chunk_bits(Vector2i(5, 5)).is_empty():
		printerr("FAIL explored_map chunk_bits sizes")
		fail += 1
	var again := map.reveal(Vector2i.ZERO)
	var step := map.reveal(Vector2i(1, 0))  # only the new east edge, all at x >= 0
	if not again.is_empty() or step.size() != 2 or not Vector2i(0, -1) in step or not Vector2i(0, 0) in step:
		printerr("FAIL explored_map repeat reveal changed chunks")
		fail += 1
	map.clear()
	if map.explored_count() != 0 or map.is_explored(Vector2i.ZERO):
		printerr("FAIL explored_map clear")
		fail += 1
	if fail == 0:
		print("PASS test_explored_map")
	return fail


func _test_minimap_panel_in_scene() -> int:
	## In the real main scene the wood panel shows in the top right once the
	## local hero spawns, below the HUD buttons and clear of the attack
	## button, counts as HUD for touches, reveals once two samples agree, draws
	## the explored cells around the hero in the map colours, M hides it, and
	## a new world clears what was explored.
	print("-- test_minimap_panel_in_scene")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	await process_frame
	var panel: MinimapPanel = scene.get_node("CanvasLayer1/MinimapPanel")
	panel.set_physics_process(false)  # ticks run by hand below
	panel.tick()
	if panel.visible:
		printerr("FAIL minimap_panel visible before the hero spawns")
		fail += 1
	scene.add_player(scene.multiplayer.get_unique_id())
	await process_frame
	panel.tick()
	if panel.explored.explored_count() != 0:
		printerr("FAIL minimap_panel revealed on a single sample")
		fail += 1
	panel.tick()
	var rect: Rect2 = panel.get_global_rect()
	var mode_rect: Rect2 = scene.get_node("CanvasLayer1/ModeButton").get_global_rect()
	var attack: TouchScreenButton = scene.get_node("CanvasLayer1/TouchScreenButton")
	var attack_rect := Rect2(attack.position, attack.texture_normal.get_size() * attack.scale)
	var view_w: float = scene.get_viewport().get_visible_rect().size.x
	if not panel.visible or absf(rect.end.x - (view_w - MinimapPanel.MARGIN * panel.scale.x)) > 1.0 \
			or rect.size.round() != (Vector2(224, 144) * panel.scale).round() or rect.intersects(mode_rect) \
			or rect.intersects(attack_rect):
		printerr("FAIL minimap_panel visible %s at %s (mode button %s, attack button %s)"
				% [panel.visible, rect, mode_rect, attack_rect])
		fail += 1
	scene.get_node("CanvasLayer1").show()  # as Host and Join do
	var zoom = scene.get_node("World/%d/Camera2D/MapZoom" % scene.multiplayer.get_unique_id())
	if not zoom.starts_on_hud(rect.get_center()):
		printerr("FAIL minimap_panel touches on the panel are not HUD touches")
		fail += 1
	var hero: Vector2i = panel.hero_cell
	var tex: ImageTexture = panel.chunk_texture(ExploredMap.chunk_of(hero))
	if not panel.explored.is_explored(hero) or panel.explored.explored_count() != 317 or tex == null:
		printerr("FAIL minimap_panel explored %s cells around %s" % [panel.explored.explored_count(), hero])
		fail += 1
	else:
		var img := tex.get_image()
		var local := (hero - ExploredMap.chunk_of(hero) * ExploredMap.CHUNK) * MinimapPanel.CELL_PX + Vector2i.ONE
		var p: Array = world.predict_cell(hero)
		var want := MinimapPanel.cell_colour(p, false, hero, hero.x * 2 + 1, hero.y * 2 + 1)
		var got := img.get_pixelv(local)
		var far := Vector2i(hero.x + 12, hero.y)
		var far_px := (far - ExploredMap.chunk_of(far) * ExploredMap.CHUNK) * MinimapPanel.CELL_PX
		var far_tex: ImageTexture = panel.chunk_texture(ExploredMap.chunk_of(far))
		if got != want and got != MinimapPanel.INK:
			printerr("FAIL minimap_panel hero cell drawn %s, want %s" % [got, want])
			fail += 1
		if far_tex and far_tex.get_image().get_pixelv(far_px).a != 0.0:
			printerr("FAIL minimap_panel unexplored cell %s is not left to the mist" % far)
			fail += 1
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	panel._unhandled_key_input(key)
	panel.tick()
	if panel.visible:
		printerr("FAIL minimap_panel still visible after M")
		fail += 1
	panel._unhandled_key_input(key)
	panel.tick()
	if not panel.visible:
		printerr("FAIL minimap_panel hidden after a second M")
		fail += 1
	world.apply_map_params(_spawn_params(7, 0.003))
	if panel.explored.explored_count() != 0 or panel.chunk_texture(ExploredMap.chunk_of(hero)) != null:
		printerr("FAIL minimap_panel kept %s cells after a new world" % panel.explored.explored_count())
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_minimap_panel_in_scene")
	return fail


func _test_minimap_incremental_render() -> int:
	## Painting only the newly revealed cells (and the ring around them) gives
	## the same chunk images, pixel for pixel, as drawing each chunk from
	## scratch, across chunk edges and coast lines, and reuses each chunk's
	## texture.
	print("-- test_minimap_incremental_render")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	await process_frame
	var panel: MinimapPanel = scene.get_node("CanvasLayer1/MinimapPanel")
	panel.set_physics_process(false)
	var cell := Vector2i(-40, -40)
	var first_tex: ImageTexture = null
	for leg in [Vector2i(3, 0), Vector2i(0, 3), Vector2i(-2, 1), Vector2i(1, -3)]:
		for i in 25:
			panel.reveal_around(cell)
			if first_tex == null:
				first_tex = panel.chunk_texture(ExploredMap.chunk_of(cell))
			cell += leg
	if panel.chunk_texture(ExploredMap.chunk_of(Vector2i(-40, -40))) != first_tex:
		printerr("FAIL minimap_incremental_render: a chunk texture was replaced, not updated")
		fail += 1
	var ink := 0
	var water := 0
	for chunk in panel.explored.chunks():
		var got := panel.chunk_image(chunk)  # the headless renderer keeps no texture pixels
		var want := panel.render_chunk(chunk)
		if got.get_data() != want.get_data():
			printerr("FAIL minimap_incremental_render: chunk %s differs from a full render" % chunk)
			fail += 1
		for y in want.get_height():
			for x in want.get_width():
				var c := want.get_pixel(x, y)
				ink += int(c == MinimapPanel.INK)
				water += int(c == MinimapPanel.SKY or c == MinimapPanel.SKY_DEEP)
	if ink == 0 or water == 0 or panel.explored.chunks().size() < 6:
		printerr("FAIL minimap_incremental_render: walk too plain (%d ink, %d water px, %d chunks)"
				% [ink, water, panel.explored.chunks().size()])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_minimap_incremental_render")
	return fail


func _test_interact_mode_toggle() -> int:
	## The HUD mode button, the menu button's size and just left of it,
	## switches between combat (the default) and interact mode and shows the
	## current mode's icon.
	print("-- test_interact_mode_toggle")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.add_player(scene.multiplayer.get_unique_id())
	scene.get_node("CanvasLayer1").show()
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var button: Button = scene.get_node("CanvasLayer1/ModeButton")
	var menu_rect: Rect2 = scene.get_node("CanvasLayer1/InGameMenu").menu_button.get_global_rect()
	if interaction.mode != Interaction.Mode.COMBAT or button.icon != Interaction.ICONS[Interaction.Mode.COMBAT]:
		printerr("FAIL interact_mode_toggle: does not start in combat mode with its icon")
		fail += 1
	var rect := button.get_global_rect()
	if rect.size != menu_rect.size or rect.intersects(menu_rect) or rect.end.x > menu_rect.position.x \
			or not interaction.player.get_node("Camera2D/MapZoom").starts_on_hud(rect.get_center()):
		printerr("FAIL interact_mode_toggle: mode button at %s, menu button at %s" % [rect, menu_rect])
		fail += 1
	button.pressed.emit()
	if interaction.mode != Interaction.Mode.INTERACT or button.icon != Interaction.ICONS[Interaction.Mode.INTERACT] \
			or not button.button_pressed:
		printerr("FAIL interact_mode_toggle: the button did not switch to interact mode")
		fail += 1
	button.pressed.emit()
	if interaction.mode != Interaction.Mode.COMBAT or button.icon != Interaction.ICONS[Interaction.Mode.COMBAT]:
		printerr("FAIL interact_mode_toggle: the button did not switch back to combat mode")
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_interact_mode_toggle")
	return fail


func _test_touch_controls_look() -> int:
	## Castle Stone touch controls (#231): the attack button shows its idle,
	## pressed and aim art as the finger lands, leaves the dead zone and comes
	## back; the move stick shows its active knob only while dragged. The cone
	## fill pulses 0.40 -> 0.55 -> 0.40 alpha every 0.8 s, and its lines are
	## one screen pixel at any camera zoom.
	print("-- test_touch_controls_look")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	scene.get_node("World").add_child(player)
	player.position = player.spawn_position()
	await process_frame
	await process_frame
	var aim: AttackAim = player.get_node("AttackAim")
	var button = aim.attack_button()
	var stick = scene.get_node("CanvasLayer1/player_joystick")
	var c: Vector2 = button.aim_center()
	var vp: Viewport = scene.get_viewport()
	var touch := func(index: int, pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.index = index
		e.position = pos
		e.pressed = pressed
		vp.push_input(e, true)
	var drag := func(index: int, pos: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = pos
		vp.push_input(e, true)

	if c.distance_to(Vector2(398, 202)) > 0.5:
		printerr("FAIL touch_controls_look attack button centre %s, want (398, 202)" % c)
		fail += 1
	var steps := [
		["idle", func(): pass, button.texture_idle],
		["down", func(): touch.call(1, c, true), button.texture_down],
		["aim", func(): drag.call(1, c + Vector2(-30, 0)), button.texture_aim],
		["back in the dead zone", func(): drag.call(1, c), button.texture_down],
		["lifted", func(): touch.call(1, c, false), button.texture_idle],
	]
	for step in steps:
		step[1].call()
		if step[2] == null or button.texture_normal != step[2]:
			printerr("FAIL touch_controls_look attack button %s shows %s" % [step[0], button.texture_normal])
			fail += 1
	var knob: TouchScreenButton = stick.touch
	touch.call(0, stick.global_position + Vector2(25, 0), true)  # on the base's rim: starts a drag
	if stick.ongoing_drag != 0 or knob.texture_normal != stick.stick_active:
		printerr("FAIL touch_controls_look stick dragged: finger %s, knob %s" % [stick.ongoing_drag, knob.texture_normal])
		fail += 1
	touch.call(0, stick.global_position, false)
	if knob.texture_normal != stick.stick:
		printerr("FAIL touch_controls_look stick released still shows %s" % knob.texture_normal)
		fail += 1

	var style := aim.style
	for t in [[0.0, 0.40], [0.2, 0.475], [0.4, 0.55], [0.8, 0.40]]:
		var fill: Color = style.fill_at(t[0])
		if not is_equal_approx(fill.a, t[1]) or fill.to_html(false) != "3d3a5c":
			printerr("FAIL touch_controls_look fill at %.1f s is %s, want 3d3a5c at %.3f" % [t[0], fill, t[1]])
			fail += 1
	var camera: Camera2D = player.get_node("Camera2D")
	for z in [0.7, 1.4]:
		camera.zoom = Vector2(z, z)
		await process_frame
		if not is_equal_approx(aim.screen_px() * z, 1.0):
			printerr("FAIL touch_controls_look at zoom %s a screen px is %s world px" % [z, aim.screen_px()])
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_touch_controls_look")
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


func _test_wall_solver() -> int:
	## WallSolver picks pieces from N/E/S/W neighbours, turns only the corners
	## of a notch in an enclosure into CORNER_IN, joins palisade runs to stone,
	## and only returns names that exist in TileCatalog.TILES.
	print("-- test_wall_solver")
	var fail := 0
	var cases := [
		# A loop with a notch and a gate: the corners of the loop stay OUT,
		# the notch corner turns IN.
		["loop with notch", _walls_from_rows([
			"#######....",
			"#..#..#....",
			"#..#..#####",
			"#.........#",
			"#.........#",
			"####g######",
		]), {
			Vector2i(0, 0): "WALL_CORNER_OUT_NW", Vector2i(6, 0): "WALL_CORNER_OUT_NE",
			Vector2i(6, 2): "WALL_CORNER_IN_SW", Vector2i(10, 2): "WALL_CORNER_OUT_NE",
			Vector2i(0, 5): "WALL_CORNER_OUT_SW", Vector2i(10, 5): "WALL_CORNER_OUT_SE",
			Vector2i(3, 0): "WALL_T_N", Vector2i(3, 1): "WALL_V", Vector2i(3, 2): "WALL_END_S", Vector2i(1, 0): "WALL_H",
			Vector2i(0, 3): "WALL_V", Vector2i(4, 5): "WALL_GATE_H",
		}],
		# A corner that encloses nothing keeps its OUT piece.
		["open L", _walls_from_rows(["###", "#..", "#.."], WallSolver.PALISADE), {
			Vector2i(0, 0): "PALISADE_CORNER_OUT_NW", Vector2i(2, 0): "PALISADE_END_E",
			Vector2i(0, 2): "PALISADE_END_S",
		}],
		["lone post", {Vector2i(5, 5): {"family": WallSolver.PALISADE}}, {
			Vector2i(5, 5): "PALISADE_POST",
		}],
		# Gates: N+S neighbours make a vertical gate. Stone has no GATE_V_OPEN
		# art, so it falls back to the closed piece.
		["palisade gates", _walls_from_rows(["#.#", "o.#", "#.o", "..#", ".#o#"], WallSolver.PALISADE), {
			Vector2i(0, 1): "PALISADE_GATE_V_OPEN", Vector2i(2, 2): "PALISADE_GATE_V_OPEN",
			Vector2i(2, 4): "PALISADE_GATE_H_OPEN",
		}],
		["stone gates", _walls_from_rows(["#..", "o..", "#..", "#o#"]), {
			Vector2i(0, 1): "WALL_GATE_V", Vector2i(1, 3): "WALL_GATE_H_OPEN",
		}],
	]
	# A palisade run meeting a stone column: the stone cell becomes a T, the
	# palisade cell next to it a join, the rest plain pieces.
	var mixed := {
		Vector2i(0, -1): {}, Vector2i(0, 0): {}, Vector2i(0, 1): {},
		Vector2i(1, 0): {"family": WallSolver.PALISADE}, Vector2i(2, 0): {"family": WallSolver.PALISADE},
		Vector2i(3, 0): {"family": WallSolver.PALISADE},
		Vector2i(5, -1): {"family": WallSolver.PALISADE}, Vector2i(5, 0): {"family": WallSolver.PALISADE},
		Vector2i(5, 1): {},
	}
	cases.append(["palisade meets stone", mixed, {
		Vector2i(0, 0): "WALL_T_W", Vector2i(1, 0): "PALISADE_H_JOIN_W", Vector2i(2, 0): "PALISADE_H",
		Vector2i(3, 0): "PALISADE_END_E", Vector2i(5, 0): "PALISADE_V_JOIN_S", Vector2i(5, 1): "WALL_END_S",
	}])
	# Damage shows on plain H and V only; a missing variant keeps the plain piece.
	var damaged := _walls_from_rows(["####", "#...", "#..."], WallSolver.PALISADE)
	damaged[Vector2i(1, 0)]["damage"] = "CHUNK"
	damaged[Vector2i(0, 1)]["damage"] = "CRACK"
	damaged[Vector2i(0, 2)]["damage"] = "CHUNK"
	damaged[Vector2i(0, 0)]["damage"] = "CRACK"
	cases.append(["damage", damaged, {
		Vector2i(1, 0): "PALISADE_H_DMG_CHUNK", Vector2i(0, 1): "PALISADE_V_DMG_CRACK",
		Vector2i(0, 2): "PALISADE_END_S", Vector2i(0, 0): "PALISADE_CORNER_OUT_NW",
		Vector2i(2, 0): "PALISADE_H",
	}])
	for c in cases:
		var got := WallSolver.solve(c[1])
		if got.size() != c[1].size():
			printerr("FAIL wall_solver %s: %d cells in, %d out" % [c[0], c[1].size(), got.size()])
			fail += 1
		for cell in got:
			if not TileCatalog.TILES.has(got[cell]):
				printerr("FAIL wall_solver %s: %s at %s is not in TileCatalog.TILES" % [c[0], got[cell], cell])
				fail += 1
		for cell in c[2]:
			if got.get(cell, "") != c[2][cell]:
				printerr("FAIL wall_solver %s: %s should be %s, got %s" % [c[0], cell, c[2][cell], got.get(cell, "")])
				fail += 1
	if fail == 0:
		print("PASS test_wall_solver")
	return fail


func _test_wall_collision() -> int:
	## Every stone and palisade wall piece blocks, straight pieces span the
	## cell along their run, and open gates leave a 12 px gap for the player.
	print("-- test_wall_collision")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	var src0: TileSetAtlasSource = scene.get_node("World/worldMap").tile_set.get_source(TileCatalog.SOURCE_ID)
	var walls := 0
	for n: String in TileCatalog.TILES:
		if not (n.begins_with("WALL_") or n.begins_with("PALISADE_")):
			continue
		walls += 1
		var td: TileData = src0.get_tile_data(TileCatalog.TILES[n]["atlas"], 0)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var gap_blocked := false
		for i in td.get_collision_polygons_count(0):
			for p in td.get_collision_polygon_points(0, i):
				lo = lo.min(p)
				hi = hi.max(p)
				if n.ends_with("GATE_H_OPEN") and absf(p.x) < 6.0 or n.ends_with("GATE_V_OPEN") and absf(p.y) < 6.0:
					gap_blocked = true
		if td.get_collision_polygons_count(0) == 0:
			printerr("FAIL wall_collision: %s has no collision polygon" % n)
			fail += 1
		elif gap_blocked:
			printerr("FAIL wall_collision: %s blocks its 12 px gate gap" % n)
			fail += 1
		elif n.ends_with("_H") and (lo.x != -8.0 or hi.x != 8.0) or n.ends_with("_V") and (lo.y != -8.0 or hi.y != 8.0):
			printerr("FAIL wall_collision: %s does not span its cell (%s..%s)" % [n, lo, hi])
			fail += 1
	if walls != 57:
		printerr("FAIL wall_collision: expected 26 stone + 31 palisade pieces, got %d" % walls)
		fail += 1
	scene.free()
	if fail == 0:
		print("PASS test_wall_collision")
	return fail


func _test_structure_round_trip() -> int:
	## Every shipped res://structures/*.txt parses with no errors, its name
	## matches the file name, and it re-exports byte for byte.
	print("-- test_structure_round_trip")
	var fail := 0
	var files := Array(DirAccess.get_files_at("res://structures")).filter(func(f): return f.ends_with(".txt"))
	if not "guard_post.txt" in files:
		printerr("FAIL structure_round_trip: res://structures/guard_post.txt is missing")
		fail += 1
	for file in files:
		var text := FileAccess.get_file_as_string("res://structures/" + file)
		var result := Structure.parse(text)
		if result["structure"] == null:
			printerr("FAIL structure_round_trip %s: %s" % [file, "; ".join(result["errors"])])
			fail += 1
			continue
		var s: Structure = result["structure"]
		if s.name + ".txt" != file:
			printerr("FAIL structure_round_trip %s: name is %s" % [file, s.name])
			fail += 1
		if s.to_text() != text:
			printerr("FAIL structure_round_trip %s is not canonical, re-export:\n%s" % [file, s.to_text()])
			fail += 1
	if fail == 0:
		print("PASS test_structure_round_trip (%d files)" % files.size())
	return fail


func _test_structure_lenient_paste() -> int:
	## CRLF, ``` fences, tab indentation and blank lines parse to the same structure.
	print("-- test_structure_lenient_paste")
	var text := FileAccess.get_file_as_string("res://structures/guard_post.txt")
	var pasted := "\n\n```\n" + text.replace("\n  ", "\n\t").replace("\n", "\r\n") + "```\n\n"
	var result := Structure.parse(pasted)
	if result["structure"] == null or result["structure"].to_text() != text:
		printerr("FAIL structure_lenient_paste: %s" % "; ".join(result["errors"]))
		return 1
	print("PASS test_structure_lenient_paste")
	return 0


func _test_structure_rejects() -> int:
	## Each broken variant of the guard post gives one error naming the problem.
	print("-- test_structure_rejects")
	var fail := 0
	var good := FileAccess.get_file_as_string("res://structures/guard_post.txt")
	var cases := [
		["# = WALL_H auto", "# = WALL_NOPE auto", "unknown tile WALL_NOPE"],
		["# = WALL_H auto", "# = WALL_V auto", "WALL_V is not allowed on the object layer"],
		["s = SAND", "s = TREE", "TREE is not allowed on the ground layer"],
		["  #...#", "  #..#", "object row 2: 4 characters"],
		["  #...#", "  #.X.#", "object row 2: 'X' is not in the legend"],
		["  T = WALL_POST", "  T = WALL_POST\n  T = BUSH", "'T' is defined twice"],
		["  T = WALL_POST", "  T = WALL_POST\n  . = BUSH", "legend character '.'"],
		["  T = WALL_POST", "  T = WALL_POST\n  b = BUSH", "'b' is never used"],
		["# = WALL_H auto", "# = WALL_H solid", "unknown attribute 'solid'"],
		["size: 5x4", "size: 17x4", "size must be WxH"],
		["anchor: 2,3", "anchor: 2,4", "anchor 2,4 is outside"],
		["flagoria-structure 1", "flagoria-structure 2", "expected 'flagoria-structure 1'"],
		["name: guard_post", "name: Guard Post", "name must match"],
		["anchor: 2,3\n", "", "missing 'anchor:'"],
		["  ##G##\n", "  ##G##\n  #####\n", "object: 5 rows, size says 4"],
	]
	for c in cases:
		var errors := _structure_errors(good.replace(c[0], c[1]))
		if errors.size() != 1 or not c[2] in errors[0]:
			printerr("FAIL structure_rejects want '%s', got %s" % [c[2], errors])
			fail += 1
	var empty := _structure_errors("flagoria-structure 1\nname: x\nversion: 1\nsize: 1x1\nanchor: 0,0\nlegend:\nobject:\n  .\n")
	if empty.size() != 1 or not "object layer is empty" in empty[0]:
		printerr("FAIL structure_rejects want 'object layer is empty', got %s" % [empty])
		fail += 1
	if fail == 0:
		print("PASS test_structure_rejects (%d cases)" % (cases.size() + 1))
	return fail


func _test_structure_export_filter() -> int:
	## Android exports use "all_resources", which leaves .txt files out of the
	## APK unless every preset includes structures/*.txt.
	print("-- test_structure_export_filter")
	var presets := ConfigFile.new()
	if presets.load("res://export_presets.cfg") != OK:
		printerr("FAIL structure_export_filter: cannot read export_presets.cfg")
		return 1
	var fail := 0
	for section in presets.get_sections():
		if section.count(".") != 1:
			continue
		var filters := str(presets.get_value(section, "include_filter", "")).split(",", false)
		if not "structures/*.txt" in Array(filters).map(func(f): return f.strip_edges()):
			printerr("FAIL structure_export_filter: %s include_filter lacks structures/*.txt" % section)
			fail += 1
	if fail == 0:
		print("PASS test_structure_export_filter")
	return fail


func _test_interact_cut_trees() -> int:
	## In interact mode a drag across a row of trees and a bush cuts the plants
	## in the range that are within reach of the player, and only those: trees
	## out of reach or outside the range stay. Each cut tree becomes a walkable
	## stump and the bush a BUSH_STUMP, each giving its type's wood, shown on
	## the HUD. A tap chops down the nearest
	## tree next to it, a pinch cuts nothing, and combat mode cuts nothing.
	print("-- test_interact_cut_trees")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(-2, 30):
		for y in range(-2, 20):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	for x in range(4, 21):
		world.set_cell(1, Vector2i(x, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	world.set_cell(1, Vector2i(12, 8), TileCatalog.SOURCE_ID, TileCatalog.BUSH)
	world.set_cell(1, Vector2i(13, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE_PINE_SMALL)
	world.set_cell(1, Vector2i(10, 6), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	var at := func(cell: Vector2) -> Vector2:  # cell units (0.5 = centre) to viewport px
		return interaction.get_canvas_transform() * world.to_global(cell * 16.0)
	var touch := func(index: int, pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.index = index
		e.position = pos
		e.pressed = pressed
		vp.push_input(e, true)
	var drag := func(index: int, pos: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = pos
		vp.push_input(e, true)
	var row := func() -> Array:  # x of the cells in row 8 that still have a tree
		var out := []
		for x in range(4, 21):
			if world.has_tree(Vector2i(x, 8)):
				out.append(x)
		return out
	var swipe := func() -> void:  # drag from the right end of row 8 to x=5
		touch.call(0, at.call(Vector2(16.5, 8.4)), true)
		drag.call(0, at.call(Vector2(11.0, 8.6)))
		drag.call(0, at.call(Vector2(5.5, 8.6)))
		touch.call(0, at.call(Vector2(5.5, 8.6)), false)

	# Combat mode: the same drag cuts nothing.
	swipe.call()
	if row.call().size() != 16 or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL interact_cut_trees: combat mode cut %s" % [row.call()])
		fail += 1
	interaction.set_mode(Interaction.Mode.INTERACT)
	# A pinch is not a selection.
	touch.call(0, at.call(Vector2(16.5, 8.4)), true)
	touch.call(1, at.call(Vector2(6.5, 8.4)), true)
	drag.call(0, at.call(Vector2(5.5, 8.6)))
	touch.call(0, at.call(Vector2(5.5, 8.6)), false)
	touch.call(1, at.call(Vector2(6.5, 8.4)), false)
	if row.call().size() != 16:
		printerr("FAIL interact_cut_trees: a pinch cut %s" % [row.call()])
		fail += 1
	# Reach is 80 px: from (10, 10) that is x 6..14 on row 8 (12 is a bush).
	swipe.call()
	var want_cut := [6, 7, 8, 9, 10, 11, 13, 14]
	var tree_wood := InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD)
	var want_wood := want_cut.size() * tree_wood + InteractableCatalog.by_id("bush").amount_of(Inventory.WOOD)
	var left: Array = row.call()
	for x in want_cut:
		var cell := Vector2i(x, 8)
		if left.has(x) or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell) != TileCatalog.STUMP:
			printerr("FAIL interact_cut_trees: %s is not a stump after the drag" % cell)
			fail += 1
	if left != [4, 5, 15, 16, 17, 18, 19, 20] or world.choppable(Vector2i(12, 8)) != null \
			or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, Vector2i(12, 8)) != TileCatalog.BUSH_STUMP \
			or not world.has_tree(Vector2i(10, 6)):
		printerr("FAIL interact_cut_trees: trees left after the drag %s" % [left])
		fail += 1
	var hud: ResourceHud = scene.get_node("CanvasLayer1/ResourceHud")
	if inventory.count_of(Inventory.WOOD) != want_wood or hud.label.text != str(want_wood):
		printerr("FAIL interact_cut_trees: wood %s, HUD '%s' after cutting %s trees and a bush, want %s"
				% [inventory.count_of(Inventory.WOOD), hud.label.text, want_cut.size(), want_wood])
		fail += 1
	# Stumps are walkable; an uncut tree still blocks.
	await physics_frame
	await physics_frame
	var body: CollisionShape2D = player.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body.shape
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	for x in [8, 17]:
		query.transform = Transform2D(0, world.to_global(world.map_to_local(Vector2i(x, 6))) + body.position)
		query.motion = Vector2(0, 64)
		var passes: bool = space.cast_motion(query)[0] >= 1.0
		if passes != (x == 8):
			printerr("FAIL interact_cut_trees: walking through column %s passes=%s" % [x, passes])
			fail += 1
	# A tap on the empty cell next to the tree at (10, 6) chops it down.
	touch.call(0, at.call(Vector2(11.3, 6.5)), true)
	touch.call(0, at.call(Vector2(11.3, 6.5)), false)
	interaction.step_chop(1.0)
	if world.has_tree(Vector2i(10, 6)) or inventory.count_of(Inventory.WOOD) != want_wood + tree_wood:
		printerr("FAIL interact_cut_trees: the tap did not cut the tree at (10, 6)")
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_interact_cut_trees")
	return fail


func _test_chop_tree_two_hits() -> int:
	## A tap chops one tree (#237): the hero faces it and swings twice, each
	## impact (140 ms and 460 ms) is a hit, and one hit does not fell it. At
	## 560 ms the tree becomes a stump under the puff and gives its wood, once.
	## Moving away or leaving interact mode mid-chop leaves the tree and gives
	## nothing; a tap mid-chop starts no second chop. Interact mode is off in
	## multiplayer, and a peer joining forces combat mode, which cancels too.
	print("-- test_chop_tree_two_hits")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(4, 16):
		for y in range(4, 14):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	world.set_cell(1, Vector2i(10, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	world.set_cell(1, Vector2i(12, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE_PINE_SMALL)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)  # the test steps the chop clock itself
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	var hits: Array = []
	interaction.chop_hit.connect(func(cell: Vector2i, hit: int) -> void: hits.append([cell, hit]))
	var tap := func(cell: Vector2) -> void:
		for pressed in [true, false]:
			var e := InputEventScreenTouch.new()
			e.position = interaction.get_canvas_transform() * world.to_global(cell * 16.0)
			e.pressed = pressed
			vp.push_input(e, true)
	var tree := Vector2i(10, 8)
	var pine := Vector2i(12, 8)
	var run_to := func(t: float) -> void:  # step the chop clock up to t s
		interaction.step_chop(t - maxf(interaction.chop_time, 0.0))
	var chop_sprite: Sprite2D = player.get_node("ChopSprite")
	var walk_sprite: Sprite2D = player.get_node("Sprite2D")
	var tree_wood := InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD)

	interaction.set_mode(Interaction.Mode.INTERACT)
	tap.call(Vector2(10.5, 8.5))
	if not interaction.chopping() or interaction.chop_cell != tree or not world.has_tree(tree):
		printerr("FAIL chop_tree_two_hits: the tap did not start chopping %s (or cut it at once)" % tree)
		fail += 1
	run_to.call(0.13)
	if not hits.is_empty():
		printerr("FAIL chop_tree_two_hits: a hit before the first impact: %s" % [hits])
		fail += 1
	run_to.call(0.15)
	# Up at the tree, on the impact column of the chop sheet.
	if hits != [[tree, 1]] or not world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != 0 \
			or not chop_sprite.visible or walk_sprite.visible or chop_sprite.frame_coords != Vector2i(2, 3):
		printerr("FAIL chop_tree_two_hits: after one hit: hits %s, tree %s, wood %s, chop pose %s %s"
				% [hits, world.has_tree(tree), inventory.count_of(Inventory.WOOD), chop_sprite.visible, chop_sprite.frame_coords])
		fail += 1
	tap.call(Vector2(12.5, 8.5))  # mid-chop: no second chop
	run_to.call(0.47)
	if hits != [[tree, 1], [tree, 2]] or interaction.chop_cell != tree:
		printerr("FAIL chop_tree_two_hits: second impact hits %s, chopping %s" % [hits, interaction.chop_cell])
		fail += 1
	run_to.call(0.55)
	if not world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL chop_tree_two_hits: the tree fell before 560 ms")
		fail += 1
	run_to.call(0.57)
	if world.has_tree(tree) or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, tree) != TileCatalog.STUMP \
			or inventory.count_of(Inventory.WOOD) != tree_wood or not interaction._puff.visible:
		printerr("FAIL chop_tree_two_hits: at 560 ms tree %s, wood %s, puff %s"
				% [world.has_tree(tree), inventory.count_of(Inventory.WOOD), interaction._puff.visible])
		fail += 1
	run_to.call(0.6)  # the hero is still recovering from the second chop
	if not interaction.chopping() or not chop_sprite.visible or chop_sprite.frame_coords != Vector2i(3, 3):
		printerr("FAIL chop_tree_two_hits: no recover pose at 600 ms: %s %s" % [chop_sprite.visible, chop_sprite.frame_coords])
		fail += 1
	run_to.call(0.7)
	interaction.step_chop(1.0)
	if interaction.chopping() or chop_sprite.visible or not walk_sprite.visible or interaction._puff.visible \
			or inventory.count_of(Inventory.WOOD) != tree_wood or hits.size() != 2 \
			or not world.has_tree(pine):
		printerr("FAIL chop_tree_two_hits: after the chop: chopping %s, chop pose %s, wood %s, hits %s"
				% [interaction.chopping(), chop_sprite.visible, inventory.count_of(Inventory.WOOD), hits])
		fail += 1
	# Moving away mid-chop cancels: no stump, no wood.
	tap.call(Vector2(12.5, 8.5))
	run_to.call(0.2)
	player.global_position += Vector2(8, 0)
	interaction.step_chop(1.0)
	if interaction.chopping() or not world.has_tree(pine) or inventory.count_of(Inventory.WOOD) != tree_wood or chop_sprite.visible:
		printerr("FAIL chop_tree_two_hits: moving away did not cancel the chop")
		fail += 1
	# Leaving interact mode mid-chop cancels too.
	if not interaction.start_chop(pine):
		printerr("FAIL chop_tree_two_hits: could not chop %s again" % pine)
		fail += 1
	run_to.call(0.5)
	interaction.set_mode(Interaction.Mode.COMBAT)
	interaction.step_chop(1.0)
	if interaction.chopping() or not world.has_tree(pine) or inventory.count_of(Inventory.WOOD) != tree_wood:
		printerr("FAIL chop_tree_two_hits: leaving interact mode did not cancel the chop")
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_tree_two_hits")
	return fail


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


func _test_interact_off_in_multiplayer() -> int:
	## Interact mode is single-player only (cuts are not synced, #223). Alone
	## (offline or hosting with no peer) the mode button shows and a tap cuts.
	## With a peer connected to the host, and on a client, the button is
	## hidden and disabled, the mode is forced to and stays combat, and a tap
	## or a drag cuts nothing.
	print("-- test_interact_off_in_multiplayer")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL interact_off_in_multiplayer found no free UDP port")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(-2, 20):
		for y in range(-2, 20):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	for x in range(6, 15):
		world.set_cell(1, Vector2i(x, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var button: Button = scene.get_node("CanvasLayer1/ModeButton")
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	var at := func(cell: Vector2) -> Vector2:  # cell units (0.5 = centre) to viewport px
		return interaction.get_canvas_transform() * world.to_global(cell * 16.0)
	var touch := func(pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.position = pos
		e.pressed = pressed
		vp.push_input(e, true)
	var drag := func(pos: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.position = pos
		vp.push_input(e, true)
	var trees := func() -> int:
		var n := 0
		for x in range(6, 15):
			n += int(world.has_tree(Vector2i(x, 8)))
		return n
	var frames := func() -> void:
		for i in 3:
			await process_frame
	# Gated: hidden, disabled, combat even when asked for interact, and map
	# input cuts nothing. Returns the failures.
	var check_gated := func(label: String) -> int:
		var f := 0
		for x in range(6, 15):  # a full row, so a wrong cut shows
			world.set_cell(1, Vector2i(x, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
		var before: int = trees.call()
		if button.visible or not button.disabled or interaction.mode != Interaction.Mode.COMBAT:
			printerr("FAIL interact_off_in_multiplayer %s: button visible %s, disabled %s, mode %s"
					% [label, button.visible, button.disabled, interaction.mode])
			f += 1
		button.pressed.emit()
		interaction.toggle_mode()
		interaction.set_mode(Interaction.Mode.INTERACT)
		if interaction.mode != Interaction.Mode.COMBAT:
			printerr("FAIL interact_off_in_multiplayer %s: switched to interact mode" % label)
			f += 1
		touch.call(at.call(Vector2(9.5, 8.5)), true)
		touch.call(at.call(Vector2(9.5, 8.5)), false)
		touch.call(at.call(Vector2(14.5, 8.5)), true)
		drag.call(at.call(Vector2(10.0, 8.6)))
		drag.call(at.call(Vector2(6.5, 8.6)))
		touch.call(at.call(Vector2(6.5, 8.6)), false)
		if trees.call() != before or interaction.cut_range(Rect2(at.call(Vector2(6, 8)), Vector2(160, 16))) != 0:
			printerr("FAIL interact_off_in_multiplayer %s: cut %s trees" % [label, before - trees.call()])
			f += 1
		return f

	# Offline: the button shows and a tap cuts.
	if not button.visible or button.disabled:
		printerr("FAIL interact_off_in_multiplayer offline: button visible %s, disabled %s" % [button.visible, button.disabled])
		fail += 1
	interaction.set_mode(Interaction.Mode.INTERACT)
	touch.call(at.call(Vector2(10.5, 8.5)), true)
	touch.call(at.call(Vector2(10.5, 8.5)), false)
	interaction.step_chop(1.0)
	if world.has_tree(Vector2i(10, 8)) or inventory.count_of(Inventory.WOOD) != InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL interact_off_in_multiplayer offline: the tap did not cut (10, 8)")
		fail += 1

	# Host: alone it is still single-player; a joining peer forces combat.
	var smp := SceneMultiplayer.new()
	set_multiplayer(smp, interaction.get_path())
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer
	await frames.call()
	if interaction.mode != Interaction.Mode.INTERACT or not button.visible:
		printerr("FAIL interact_off_in_multiplayer hosting alone: mode %s, button visible %s" % [interaction.mode, button.visible])
		fail += 1
	var client_root := Node.new()
	client_root.name = "InteractClient"
	root.add_child(client_root)
	var cmp := SceneMultiplayer.new()
	set_multiplayer(cmp, client_root.get_path())
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	cmp.multiplayer_peer = cpeer
	if not await _client_connected(smp, cpeer):
		printerr("FAIL interact_off_in_multiplayer client did not connect to the host")
		fail += 1
	else:
		await frames.call()
		fail += check_gated.call("host with a peer")
	cpeer.close()
	speer.close()
	set_multiplayer(null, client_root.get_path())
	set_multiplayer(null, interaction.get_path())
	await frames.call()
	if not button.visible or button.disabled:
		printerr("FAIL interact_off_in_multiplayer back offline: button visible %s, disabled %s" % [button.visible, button.disabled])
		fail += 1

	# Client: gated while connecting and once connected.
	var port2 := _free_udp_port()
	var smp2 := SceneMultiplayer.new()
	set_multiplayer(smp2, client_root.get_path())
	var speer2 := ENetMultiplayerPeer.new()
	speer2.create_server(port2)
	smp2.multiplayer_peer = speer2
	var cmp2 := SceneMultiplayer.new()
	set_multiplayer(cmp2, interaction.get_path())
	interaction.set_mode(Interaction.Mode.INTERACT)
	var cpeer2 := ENetMultiplayerPeer.new()
	cpeer2.create_client("127.0.0.1", port2)
	cmp2.multiplayer_peer = cpeer2
	await frames.call()
	if interaction.mode != Interaction.Mode.COMBAT or button.visible:
		printerr("FAIL interact_off_in_multiplayer connecting client: mode %s, button visible %s" % [interaction.mode, button.visible])
		fail += 1
	if not await _client_connected(smp2, cpeer2):
		printerr("FAIL interact_off_in_multiplayer client did not connect")
		fail += 1
	else:
		await frames.call()
		fail += check_gated.call("client")
	cpeer2.close()
	speer2.close()
	set_multiplayer(null, interaction.get_path())
	set_multiplayer(null, client_root.get_path())
	client_root.queue_free()
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_interact_off_in_multiplayer")
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


func _test_server_params_from_args() -> int:
	## `--params <file>` gives the dedicated server a map save to host; no
	## --params means the active params (null); a bad value is an error.
	print("-- test_server_params_from_args")
	var main_script = load("res://flagoria_main.gd")
	var params := MapGenParams.make_defaults()
	params.altitude_seed = 1101
	params.moisture_seed = 1102
	params.temperature_seed = 1103
	params.items_seed = 1104
	params.biome_seed = 1105
	params.water_max_alt = 0.125
	var saved := MapSave.save_map(params, "test_server_params")
	var path: String = saved["path"]
	var fail := 0
	for case in [
		[["--server"], ""],
		[["--server", "--params", path], ""],
		[["--server", "--params=" + ProjectSettings.globalize_path(path)], ""],
		[["--server", "--params"], "needs a map save"],
		[["--server", "--params", "--port=9799"], "needs a map save"],
		[["--server", "--params="], "needs a map save"],
		[["--server", "--params", "user://no_such_save.json"], "no map save"],
	]:
		var got: Dictionary = main_script.server_params_from_args(PackedStringArray(case[0]))
		var has_file: bool = case[0].size() > 1 and case[1] == ""
		var ok: bool = (got["error"] == "" if case[1] == "" else case[1] in got["error"])
		if ok and has_file:
			ok = got["params"] != null and got["params"].to_dict() == params.to_dict()
		elif ok:
			ok = got["params"] == null
		if not ok:
			printerr("FAIL server_params_from_args %s = %s" % [case[0], got])
			fail += 1
	DirAccess.remove_absolute(path)
	if fail == 0:
		print("PASS test_server_params_from_args")
	return fail


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


func _test_dedicated_server_params_file() -> int:
	## `-- --server --params <file>` hosts the map in that save: a client that
	## joins gets exactly its params. A missing file stops the server with
	## exit 1 before it listens. Both server runs have a hard `timeout`.
	print("-- test_dedicated_server_params_file")
	var fail := 0
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL dedicated_server_params_file found no free UDP port")
		return 1
	var out := []
	var code := OS.execute("timeout", ["-k", "5", "30", exe, "--headless", "--path", project,
		"--", "--server", "--port=%d" % port, "--params=user://no_such_save.json"], out, true)
	if code != 1 or not "no map save" in "".join(out):
		printerr("FAIL dedicated_server_params_file missing file: exit %s, want 1 and 'no map save'" % code)
		fail += 1

	var params := MapGenParams.make_defaults()
	params.altitude_seed = 2201
	params.moisture_seed = 2202
	params.temperature_seed = 2203
	params.items_seed = 2204
	params.biome_seed = 2205
	params.water_max_alt = 0.125
	var saved := MapSave.save_map(params, "test_dedicated_server_params")
	if saved["error"] != "":
		printerr("FAIL dedicated_server_params_file save: %s" % saved["error"])
		return fail + 1
	# `timeout` forwards the TERM below to the server and kills it after 90 s
	# whatever happens to this run.
	var pid := OS.create_process("timeout", ["-k", "5", "90", exe, "--headless", "--path", project,
		"--", "--server", "--port=%d" % port, "--params=" + ProjectSettings.globalize_path(saved["path"])])
	if pid <= 0:
		printerr("FAIL dedicated_server_params_file could not start the server process")
		return fail + 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.add_player_joined(port)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		if scene.world_params != null and scene.world_params.altitude_seed != 0:
			break
		await process_frame
	var got: MapGenParams = scene.world_params
	if got == null or got.to_dict() != params.to_dict():
		printerr("FAIL dedicated_server_params_file client got %s, want %s" % [
			got.to_dict() if got != null else null, params.to_dict()])
		fail += 1
	OS.execute("kill", ["-TERM", str(pid)])
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	DirAccess.remove_absolute(saved["path"])
	if fail == 0:
		print("PASS test_dedicated_server_params_file")
	return fail


func _test_cut_tree_stays_stump() -> int:
	## A cut tree stays a stump when its chunk is drawn again, and predict_cell
	## and predicted_clear see the stump, so mobs treat the cell as open ground.
	print("-- test_cut_tree_stays_stump")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	var tree := Vector2i(1 << 20, 0)
	var seed_value := 0
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(1):
			if world.has_tree(cell):
				tree = cell
				seed_value = s
				break
		if seed_value != 0:
			break
	if tree.x == 1 << 20:
		printerr("FAIL cut_tree_stays_stump: no tree near the origin on any seed")
		scene.queue_free()
		return 1
	world.predict_cell(tree)  # cached before the cut
	if not world.cut_choppable(tree) or world.cut_choppable(tree):
		printerr("FAIL cut_tree_stays_stump: cut_choppable did not cut %s exactly once" % tree)
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	if world.has_tree(tree) or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, tree) != TileCatalog.STUMP:
		printerr("FAIL cut_tree_stays_stump: %s grew back after the chunk was drawn again" % tree)
		fail += 1
	if world.predict_cell(tree)[1] != TileCatalog.STUMP or not world.predicted_clear(tree) or not world.is_clear_ground(tree):
		printerr("FAIL cut_tree_stays_stump: predict_cell %s for the stump" % [world.predict_cell(tree)])
		fail += 1
	world.apply_map_params(_spawn_params(seed_value, 0.0))
	world.generate_chunk(Vector2(0, 0))
	if not world.has_tree(tree):
		printerr("FAIL cut_tree_stays_stump: a new map kept the stump at %s" % tree)
		fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_cut_tree_stays_stump")
	return fail


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


func _test_tree_regrows() -> int:
	## A stump turns back into its tree once regrow_delay seconds of play have
	## passed since the cut, not before, and not while a player stands on it:
	## the same tree, with its collision, and predict_cell sees it again.
	print("-- test_tree_regrows")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	var tree := Vector2i(1 << 20, 0)
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(1):
			if world.has_tree(cell):
				tree = cell
				break
		if tree.x != 1 << 20:
			break
	if tree.x == 1 << 20:
		printerr("FAIL tree_regrows: no tree near the origin on any seed")
		scene.queue_free()
		return 1
	var atlas: Vector2i = world.get_cell_atlas_coords(1, tree)
	var is_stump := func() -> bool:
		return not world.has_tree(tree) and world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, tree) == TileCatalog.STUMP
	world.regrow_delay = 30.0
	world.play_time = 100.0
	world.cut_choppable(tree)
	# Not before the delay.
	world.play_time = 129.9
	if world.regrow_due() != 0 or not is_stump.call():
		printerr("FAIL tree_regrows: %s regrew before the delay" % tree)
		fail += 1
	# Not while a player stands on the stump.
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(tree))
	scene.get_node("World").add_child(player)
	await process_frame
	world.play_time = 200.0
	if not world.player_on_cell(tree) or world.regrow_due() != 0 or not is_stump.call():
		printerr("FAIL tree_regrows: %s regrew under the player" % tree)
		fail += 1
	# After the delay, once the player has moved off.
	player.position = world.to_global(world.map_to_local(tree + Vector2i(6, 6)))
	if world.player_on_cell(tree) or world.regrow_due() != 1:
		printerr("FAIL tree_regrows: %s did not regrow after the delay" % tree)
		fail += 1
	var top = world.get_cell_tile_data(1, tree)
	if world.get_cell_atlas_coords(1, tree) != atlas or world.get_cell_source_id(world.GROUND_DECOR_LAYER, tree) != -1 \
			or top == null or top.get_collision_polygons_count(0) == 0:
		printerr("FAIL tree_regrows: %s is %s after regrowing, want %s with collision and no stump"
				% [tree, world.get_cell_atlas_coords(1, tree), atlas])
		fail += 1
	if world.predict_cell(tree)[1] != atlas or world.predicted_clear(tree):
		printerr("FAIL tree_regrows: predict_cell %s after regrowing" % [world.predict_cell(tree)])
		fail += 1
	# It can be cut again, and the chunk keeps it a tree once regrown.
	world.generate_chunk(Vector2(0, 0))
	if not world.has_tree(tree) or not world.cut_choppable(tree):
		printerr("FAIL tree_regrows: %s cannot be cut again after regrowing" % tree)
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_tree_regrows")
	return fail


func _test_joystick_hold_keeps_moving() -> int:
	## Touch joystick: a finger held still at one offset, with no further
	## touch or drag events, keeps the player moving at the joystick's top
	## speed every physics frame; letting go brings the player to rest.
	print("-- test_joystick_hold_keeps_moving")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var local = load("res://Player/character_body_2d.tscn").instantiate()
	local.name = str(scene.multiplayer.get_unique_id())
	scene.get_node("World").add_child(local)
	local.collision_mask = 0  # input to velocity only; terrain is not under test
	await process_frame
	var joystick = scene.get_node("CanvasLayer1/player_joystick")
	var vp: Viewport = scene.get_viewport()
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = joystick.global_position
	touch.pressed = true
	vp.push_input(touch, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = joystick.global_position + Vector2(40, 0) * joystick.global_scale
	vp.push_input(drag, true)
	var top: float = local.JOYSTICK_MAX_SPEED
	for i in range(60):
		await physics_frame
	var held: Vector2 = local.velocity
	if not (held.x > top * 0.9 and held.length() <= top + 0.01 and absf(held.y) < 0.01):
		printerr("FAIL joystick_hold velocity after 60 frames held still: %s (want ~%s, +x)" % [held, top])
		fail += 1
	if local.lastAnimDirection != "Right":
		printerr("FAIL joystick_hold facing %s, want Right" % local.lastAnimDirection)
		fail += 1
	touch.pressed = false
	touch.position = drag.position
	vp.push_input(touch, true)
	for i in range(60):
		await physics_frame
	var at: Vector2 = local.position
	await physics_frame
	if local.velocity != Vector2.ZERO or local.position != at:
		printerr("FAIL joystick_hold still moving after release: v %s" % local.velocity)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_joystick_hold_keeps_moving (held %s)" % held)
	return fail


func _test_ui_sfx_clips() -> int:
	## Every UI event maps to a clip that exists and loads, with a volume, a
	## cooldown and a counter, on a local (non-positional) SFX player; every
	## clip under art/audio/sfx/ui/ is used.
	print("-- test_ui_sfx_clips")
	var fail := 0
	var ui = root.get_node_or_null("UiSfx")
	if ui == null:
		printerr("FAIL ui_sfx_clips: no UiSfx autoload")
		return 1
	var want := ["click", "back", "menu_open", "menu_close", "saved"]
	if ui.SOUNDS.keys() != want:
		printerr("FAIL ui_sfx_clips: events %s, want %s" % [ui.SOUNDS.keys(), want])
		fail += 1
	var used := []
	for event in ui.SOUNDS:
		var clips: Array = ui.SOUNDS[event]
		if clips.is_empty():
			printerr("FAIL ui_sfx_clips: %s has no clips" % event)
			fail += 1
		for clip in clips:
			var wav := clip as AudioStreamWAV
			if wav == null or wav.get_length() <= 0.03 or not ResourceLoader.exists(wav.resource_path):
				printerr("FAIL ui_sfx_clips: %s clip %s missing or empty" % [event, clip])
				fail += 1
				continue
			used.append(wav.resource_path.get_file())
			if not wav.resource_path.get_file().begins_with(event + "_"):
				printerr("FAIL ui_sfx_clips: %s maps to %s" % [event, wav.resource_path])
				fail += 1
		if not ui.VOLUME_DB.has(event) or not ui.COOLDOWN.has(event) or not ui.plays.has(event):
			printerr("FAIL ui_sfx_clips: %s lacks a volume, cooldown or counter" % event)
			fail += 1
			continue
		var p = ui.players().get(event)
		if not p is AudioStreamPlayer or p.bus != &"SFX" or not is_equal_approx(p.volume_db, ui.VOLUME_DB[event]):
			printerr("FAIL ui_sfx_clips: %s player %s on %s" % [event, p, p.bus if p else ""])
			fail += 1
	for file in DirAccess.get_files_at("res://art/audio/sfx/ui"):
		if file.ends_with(".wav") and file not in used:
			printerr("FAIL ui_sfx_clips: %s is not used" % file)
			fail += 1
	if ui.process_mode != Node.PROCESS_MODE_ALWAYS:
		printerr("FAIL ui_sfx_clips: UiSfx stops when the game pauses")
		fail += 1
	if FileAccess.get_file_as_string("res://Scripts/ui_sfx.gd").contains("rpc"):
		printerr("FAIL ui_sfx_clips: UI sounds must stay local (no RPCs)")
		fail += 1
	if fail == 0:
		print("PASS test_ui_sfx_clips")
	return fail


func _test_ui_sfx_presses() -> int:
	## Each press plays exactly once: click on every button in the main menu
	## and map settings panel, back on Back. The sound starts before the
	## button's own handler and outlives the button. A "ui_menu" Control
	## plays menu_open/menu_close when it shows or hides; a map save that
	## succeeds plays saved, a failed one nothing. (Cooldowns are cleared
	## between steps; they only guard against a double fire.)
	print("-- test_ui_sfx_presses")
	var fail := 0
	var ui = root.get_node("UiSfx")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame  # the map settings panel is added deferred
	var layer: Node = scene.get_node("CanvasLayer2")
	var buttons := layer.find_children("*", "BaseButton", true, false)
	var names := []
	for b in buttons:
		names.append(str(b.name))
		var first: Callable = b.pressed.get_connections()[0]["callable"] if b.pressed.get_connections().size() > 0 else Callable()
		if first.get_object() != ui:
			printerr("FAIL ui_sfx_presses: %s press sound is not connected first" % b.name)
			fail += 1
		var want := "back" if b.name == "Back" else "click"
		if ui.sound_for(b) != want:
			printerr("FAIL ui_sfx_presses: %s plays %s, want %s" % [b.name, ui.sound_for(b), want])
			fail += 1
	for n in ["MapSettingsButton", "HostButton", "JoinButton", "RandomSeed", "Reset", "Back", "Start", "NoiseType"]:
		if n not in names:
			printerr("FAIL ui_sfx_presses: no %s button found" % n)
			fail += 1
	# Real presses that stay local (Host and Join start networking).
	var menu = layer.get_node("MainMenu")
	var panel = menu.admin_panel
	var presses := [
		[menu.get_node("MarginContainer/VBoxContainer/MapSettingsButton"), "click"],
		[panel.get_node("Margin/VBox/Buttons/RandomSeed"), "click"],
		[panel.get_node("Margin/VBox/Buttons/Reset"), "click"],
		[panel.get_node("Margin/VBox/Buttons2/Back"), "back"],
	]
	for press in presses:
		ui._last_ms.clear()  # cooldowns are wall-clock; each step is a new press
		var before: Dictionary = ui.plays.duplicate()
		press[0].pressed.emit()
		await process_frame
		var got := _ui_plays_since(ui, before)
		if got != {press[1]: 1}:
			printerr("FAIL ui_sfx_presses: %s press played %s, want {%s: 1}" % [press[0].name, got, press[1]])
			fail += 1
	if not menu.visible or panel.visible:
		printerr("FAIL ui_sfx_presses: Back did not return to the main menu")
		fail += 1
	scene.queue_free()
	await process_frame

	# A handler that blocks, then frees the button's scene (like a scene
	# change): the click has already started and keeps playing.
	var fake := Node.new()
	var button := Button.new()
	fake.add_child(button)
	var seen := {}
	button.pressed.connect(func() -> void:
		seen["click"] = ui.plays["click"]
		seen["playing"] = ui.players()["click"].playing
		OS.delay_msec(100)
		fake.queue_free())
	root.add_child(fake)
	ui._last_ms.clear()  # cooldowns are wall-clock; each step is a new press
	var start: int = ui.plays["click"]
	button.pressed.emit()
	await process_frame
	await process_frame
	if seen.get("click", start) != start + 1 or ui.plays["click"] != start + 1:
		printerr("FAIL ui_sfx_presses: click %s before the handler, %s after; want %s" % [seen.get("click"), ui.plays["click"], start + 1])
		fail += 1
	if not seen.get("playing", false) or is_instance_valid(fake) or not ui.players()["click"].is_inside_tree():
		printerr("FAIL ui_sfx_presses: click not playing before the handler, or gone with the button's scene")
		fail += 1

	# A button that leaves and re-enters the tree still plays once per press.
	var holder := Node.new()
	root.add_child(holder)
	var again := Button.new()
	holder.add_child(again)
	holder.remove_child(again)
	holder.add_child(again)
	for i in 2:
		ui._last_ms.clear()  # cooldowns are wall-clock; each step is a new press
		var before: Dictionary = ui.plays.duplicate()
		again.pressed.emit()
		if _ui_plays_since(ui, before) != {"click": 1}:
			printerr("FAIL ui_sfx_presses: re-added button press %d played %s" % [i, _ui_plays_since(ui, before)])
			fail += 1

	# Menu open and close follow visibility in the tree, once per change.
	var parent := Control.new()
	holder.add_child(parent)
	var menu_panel := Control.new()
	menu_panel.add_to_group(&"ui_menu")
	var steps := [
		["add visible", func() -> void: parent.add_child(menu_panel), {}],
		["hide", func() -> void: menu_panel.hide(), {"menu_close": 1}],
		["hide again", func() -> void: menu_panel.hide(), {}],
		["show", func() -> void: menu_panel.show(), {"menu_open": 1}],
		["parent hidden", func() -> void: parent.hide(), {"menu_close": 1}],
		["parent shown", func() -> void: parent.show(), {"menu_open": 1}],
		["parent hidden again", func() -> void: parent.hide(), {"menu_close": 1}],
		["hidden under hidden parent", func() -> void: menu_panel.hide(), {}],
		["shown under hidden parent", func() -> void: menu_panel.show(), {}],
		["parent shown again", func() -> void: parent.show(), {"menu_open": 1}],
	]
	for step in steps:
		ui._last_ms.clear()
		var before: Dictionary = ui.plays.duplicate()
		step[1].call()
		if _ui_plays_since(ui, before) != step[2]:
			printerr("FAIL ui_sfx_presses: menu %s played %s, want %s" % [step[0], _ui_plays_since(ui, before), step[2]])
			fail += 1
	holder.queue_free()

	# Saved: once for a map save that succeeds, nothing for one that fails.
	var map_gen = root.get_node("MapGen")
	var kept: MapGenParams = map_gen.params
	map_gen.params = kept.duplicate_params()
	map_gen.params.ensure_seeds()
	var before_save: Dictionary = ui.plays.duplicate()
	var err: String = map_gen.save_map_inputs("test_ui_saved")
	DirAccess.remove_absolute(MapSave.path_for("test_ui_saved"))
	if err != "" or _ui_plays_since(ui, before_save) != {"saved": 1}:
		printerr("FAIL ui_sfx_presses: save (%s) played %s, want {saved: 1}" % [err, _ui_plays_since(ui, before_save)])
		fail += 1
	ui._last_ms.clear()
	map_gen.params.altitude_seed = 0
	before_save = ui.plays.duplicate()
	err = map_gen.save_map_inputs("test_ui_saved")
	if err == "" or _ui_plays_since(ui, before_save) != {}:
		printerr("FAIL ui_sfx_presses: failed save (%s) played %s" % [err, _ui_plays_since(ui, before_save)])
		fail += 1
	map_gen.params = kept
	await process_frame
	if fail == 0:
		print("PASS test_ui_sfx_presses (%d buttons)" % buttons.size())
	return fail


func _test_rejoin_sees_every_death() -> int:
	## A joiner's process dies with no goodbye and starts again, so it joins
	## under a new peer id while the server still holds the old one until
	## ENet times it out. Every death the server then deals the new player
	## reaches its own client, followed by the respawn (#171), each time, and
	## nothing meant for the old peer reaches the new one.
	print("-- test_rejoin_sees_every_death")
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL rejoin_sees_every_death found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("rejoin_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var pids: Array[int] = []
	var outs: Array[String] = []
	var start := func(extra: Array) -> void:
		var out := dir.path_join("p%d.json" % outs.size())
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://tests/late_join_probe.gd", "--", "--port=%d" % port, "--out=" + out]
		args.append_array(extra)
		pids.append(OS.create_process(OS.get_executable_path(), args))
		outs.append(out)
	var read := func(i: int) -> Dictionary:
		var text := FileAccess.get_file_as_string(outs[i])
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	var joined := func(i: int) -> bool:
		var s: Dictionary = read.call(i)
		return s.get("origin") != null and s.get("players", {}).has(s.get("id")) \
				and read.call(0).get("players", {}).has(s.get("id"))

	var fail := 0
	start.call(["--host"])
	if not await wait_for.call(func() -> bool: return read.call(0).get("origin") != null, 30000):
		printerr("FAIL rejoin_sees_every_death the host did not start")
		fail += 1
	if fail == 0:
		start.call([])
		if not await wait_for.call(joined.bind(1), 30000):
			printerr("FAIL rejoin_sees_every_death the first joiner did not join: %s" % read.call(1))
			fail += 1
	var old_id: String = read.call(1).get("id", "") if fail == 0 else ""
	if fail == 0:
		OS.kill(pids[1])
		pids[1] = 0
		start.call([])
		if not await wait_for.call(joined.bind(2), 30000):
			printerr("FAIL rejoin_sees_every_death the restarted joiner did not join: %s" % read.call(2))
			fail += 1
	if fail == 0:
		var new_id: String = read.call(2)["id"]
		var stale: bool = read.call(0).get("players", {}).has(old_id)
		for k in range(1, 4):
			FileAccess.open(outs[0] + ".kill", FileAccess.WRITE).store_string(str(k))
			var seen := func() -> bool:
				var own: Dictionary = read.call(2)
				return own.get("deaths", 0) >= k and own.get("players", {}).get(new_id, {}).get("respawns", 0) >= k
			if not await wait_for.call(seen, 10000):
				var own: Dictionary = read.call(2)
				printerr("FAIL rejoin_sees_every_death death %d: its own client saw %s deaths and %s respawns, the server %s respawns"
						% [k, own.get("deaths"), own.get("players", {}).get(new_id, {}).get("respawns"),
						read.call(0).get("players", {}).get(new_id, {}).get("respawns")])
				fail += 1
				break
		if fail == 0 and not read.call(2).get("errors", []).is_empty():
			printerr("FAIL rejoin_sees_every_death the restarted joiner logged errors, so traffic for the old peer reached it: %s"
					% [read.call(2)["errors"]])
			fail += 1
		if fail == 0:
			print("PASS test_rejoin_sees_every_death (3 deaths and respawns; old peer %s)"
					% ("still held at the first" if stale else "already gone"))

	for out in outs:
		FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	await wait_for.call(func() -> bool:
		for pid in pids:
			if pid > 0 and OS.is_process_running(pid):
				return false
		return true, 10000)
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_remove_dir(dir)
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


func _test_main_menu_input_no_log_spam() -> int:
	## Unhandled input on the main menu must not log InputMap errors (the menu
	## checks a "quit" action that is not mapped). Runs tests/menu_input_probe.gd
	## in a separate headless process, because engine errors cannot be read back
	## in-process. --quit-after bounds the run.
	print("-- test_main_menu_input_no_log_spam")
	var output := []
	var code := OS.execute(
		OS.get_executable_path(),
		[
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--quit-after", "600", "--script", "res://tests/menu_input_probe.gd",
		],
		output,
		true
	)
	var log_text: String = "".join(output)
	var fail := 0
	if code != 0 or not log_text.contains("MENU_INPUT_PROBE_OK"):
		printerr("FAIL main_menu_input_no_log_spam probe exit=%s" % code)
		fail += 1
	var errors := 0
	for line in log_text.split("\n"):
		if line.contains("InputMap action"):
			errors += 1
	if errors > 0:
		printerr("FAIL main_menu_input_no_log_spam: %s InputMap errors in the log" % errors)
		fail += 1
	if fail == 0:
		print("PASS test_main_menu_input_no_log_spam")
	return fail

