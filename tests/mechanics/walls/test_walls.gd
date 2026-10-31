extends "res://tests/helpers/test_helpers.gd"
## Wall piece choice (WallSolver) and wall collision.


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
