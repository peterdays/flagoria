extends "res://tests/helpers/test_helpers.gd"
## Building WFC constraint rules and seeded solves (#25).


const BUILDING_W := 6
const BUILDING_H := 5


func _test_wfc_building_constraints() -> int:
	## Time cost: ~15–35 s in tools/verify.sh (1000 seeds + rule negatives).
	print("-- test_wfc_building_constraints")
	var fail := 0
	fail += _rule_negative_tests()
	fail += _seed_sweep()
	if fail == 0:
		print("PASS test_wfc_building_constraints")
	return fail


func _pieces() -> Array:
	var out: Array = []
	for piece: BuildingBlockPiece in BuildingBlockCatalog.all():
		out.append(piece)
	return out


func _seed_sweep() -> int:
	var fail := 0
	for seed in 1000:
		var result := WfcBuildingConstraints.solve_building(
				BUILDING_W, BUILDING_H, seed, _pieces())
		if not result.ok:
			printerr(
					"FAIL wfc_building_constraints: seed %s: %s"
					% [seed, result.get("error", "")]
			)
			fail += 1
			continue
		var err := WfcBuildingConstraints.validate_all(result.grid)
		if err != "":
			printerr("FAIL wfc_building_constraints: seed %s post-check %s" % [seed, err])
			fail += 1
	return fail


func _rule_negative_tests() -> int:
	var fail := 0
	fail += _expect_rule_fail(
			"outer_ring", _bad_outer_ring(), WfcBuildingConstraints.rule_outer_ring_walls)
	fail += _expect_rule_fail(
			"one_door", _bad_one_door(), WfcBuildingConstraints.rule_one_door_on_ring)
	fail += _expect_rule_fail(
			"reachability",
			_bad_reachability(),
			WfcBuildingConstraints.rule_floor_reachable_from_door,
	)
	fail += _expect_rule_fail(
			"roof", _bad_roof(), WfcBuildingConstraints.rule_roof_over_interior)
	fail += _expect_rule_fail(
			"min_interior", _bad_min_interior(), WfcBuildingConstraints.rule_min_interior_size)
	return fail


func _expect_rule_fail(rule_name: String, grid: Array, rule: Callable) -> int:
	var err: String = rule.call(grid)
	if err == "":
		printerr("FAIL wfc_building_constraints: %s grid should break rule" % rule_name)
		return 1
	return 0


func _layout_6x5() -> Array:
	## Valid-shaped grid: roof row, walls, single door south, floors covered.
	return [
		["wall_corner", "roof_fill", "roof_fill", "roof_fill", "roof_fill", "wall_corner"],
		["wall_straight", "floor", "floor", "floor", "floor", "wall_straight"],
		["wall_straight", "floor", "floor", "floor", "floor", "wall_straight"],
		["wall_straight", "floor", "floor", "floor", "floor", "wall_straight"],
		[
				"wall_corner", "wall_straight", "door", "wall_straight", "wall_straight",
				"wall_corner",
		],
	]


func _bad_outer_ring() -> Array:
	var g := _layout_6x5()
	g[2][3] = "wall_straight"
	return g


func _bad_one_door() -> Array:
	var g := _layout_6x5()
	g[4][4] = "door"
	return g


func _bad_reachability() -> Array:
	var g := _layout_6x5()
	for y in range(1, BUILDING_H - 1):
		g[y][2] = "wall_straight"
	return g


func _bad_roof() -> Array:
	var g := _layout_6x5()
	for y in g.size():
		if g[y][2] in WfcBuildingConstraints.ROOF_IDS:
			g[y][2] = "wall_straight"
	return g


func _bad_min_interior() -> Array:
	var g := _layout_6x5()
	for y in range(1, BUILDING_H - 1):
		for x in range(1, BUILDING_W - 1):
			g[y][x] = "wall_straight"
	g[2][2] = "floor"
	g[2][3] = "floor"
	g[3][2] = "floor"
	return g