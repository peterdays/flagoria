extends "res://tests/helpers/test_helpers.gd"
## WFC solver: compatibility, determinism, failure and timing (#24).


func _test_wfc_solver() -> int:
	## Time cost: ~8–20 s in tools/verify.sh (500 seeds × four grid sizes).
	print("-- test_wfc_solver")
	var fail := 0
	var pieces: Array = []
	for p: BuildingBlockPiece in BuildingBlockCatalog.all():
		pieces.append(p)
	fail += _deterministic(pieces)
	fail += _seed_sweep(pieces)
	fail += _impossible_set_fails_fast()
	fail += _time_16x16(pieces)
	if fail == 0:
		print("PASS test_wfc_solver")
	return fail


func _solve(w: int, h: int, pieces: Array, seed: int, max_attempts: int = -1) -> Dictionary:
	if max_attempts < 0:
		return WfcSolver.solve(w, h, pieces, seed)
	return WfcSolver.solve(w, h, pieces, seed, max_attempts)


func _deterministic(pieces: Array) -> int:
	var fail := 0
	for seed in [0, 1, 42, 999_001]:
		var a := _solve(8, 8, pieces, seed)
		var b := _solve(8, 8, pieces, seed)
		if not a.ok or not b.ok:
			printerr("FAIL wfc_solver: deterministic run failed seed %s" % seed)
			fail += 1
			continue
		if a.grid != b.grid:
			printerr("FAIL wfc_solver: seed %s not deterministic" % seed)
			fail += 1
	return fail


func _seed_sweep(pieces: Array) -> int:
	var sizes: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 5), Vector2i(7, 6), Vector2i(16, 16)]
	var fail := 0
	for size: Vector2i in sizes:
		for seed in 500:
			var result := _solve(size.x, size.y, pieces, seed)
			if not result.ok:
				printerr(
						"FAIL wfc_solver: size %dx%d seed %s: %s"
						% [size.x, size.y, seed, result.get("error", "")]
				)
				fail += 1
				continue
			fail += _grid_compatible(result.grid)
	return fail


func _grid_compatible(grid: Array) -> int:
	var h := grid.size()
	if h == 0:
		return 1
	var w: int = grid[0].size()
	var fail := 0
	for y in h:
		for x in w:
			var id: String = grid[y][x]
			var piece := BuildingBlockCatalog.by_id(id)
			if piece == null:
				printerr("FAIL wfc_solver: unknown id %s at %d,%d" % [id, x, y])
				fail += 1
				continue
			for i in WfcSolver.STEPS.size():
				var nx := x + WfcSolver.STEPS[i].x
				var ny := y + WfcSolver.STEPS[i].y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var other := BuildingBlockCatalog.by_id(grid[ny][nx])
				if not BuildingBlockCatalog.edge_compatible(
						piece, BuildingBlockCatalog.SIDES[i], other):
					printerr(
							"FAIL wfc_solver: incompatible %s %s vs %s at %d,%d"
							% [id, BuildingBlockCatalog.SIDES[i], grid[ny][nx], x, y]
					)
					fail += 1
	return fail


func _impossible_piece_set() -> Array:
	var left := BuildingBlockPiece.new()
	left.id = "iso_left"
	left.sockets = {"N": "only_a", "E": "only_a", "S": "only_a", "W": "only_a"}
	var right := BuildingBlockPiece.new()
	right.id = "iso_right"
	right.sockets = {"N": "only_b", "E": "only_b", "S": "only_b", "W": "only_b"}
	return [left, right]


func _impossible_set_fails_fast() -> int:
	var pieces := _impossible_piece_set()
	var t0 := Time.get_ticks_usec()
	var result := _solve(2, 2, pieces, 12345, 8)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if result.ok:
		printerr("FAIL wfc_solver: impossible set should not succeed")
		return 1
	if result.error == "":
		printerr("FAIL wfc_solver: impossible set missing error message")
		return 1
	if ms > 2000.0:
		printerr("FAIL wfc_solver: impossible set took %.1f ms (hang?)" % ms)
		return 1
	return 0


func _time_16x16(pieces: Array) -> int:
	var t0 := Time.get_ticks_usec()
	var result := _solve(16, 16, pieces, 42)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if not result.ok:
		printerr("FAIL wfc_solver: 16x16 benchmark failed: %s" % result.get("error", ""))
		return 1
	print("wfc_solver: 16x16 seed 42 solved in %.2f ms" % ms)
	return 0