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

