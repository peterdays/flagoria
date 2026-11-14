extends "res://tests/helpers/test_helpers.gd"
## Footprint structure rotation before placement (#493).


func _guard_post() -> Structure:
	return StructurePlacer.load_named("guard_post")


func _footprint_cells(structure: Structure, anchor: Vector2i, quarter_turns: int) -> Array:
	var placed := Structure.rotated(structure, quarter_turns)
	return StructurePlacer.footprint(placed, anchor).keys()


func _test_structure_rotation_four_turns() -> int:
	## guard_post (5x4) footprints differ for quarter turns 0–3; a full loop
	## returns the turn-0 footprint.
	print("-- test_structure_rotation_four_turns")
	var structure := _guard_post()
	if structure == null:
		printerr("FAIL structure_rotation_four_turns: guard_post missing")
		return 1
	var anchor := Vector2i(20, 20)
	var turn0: Array = _footprint_cells(structure, anchor, 0)
	var seen := {}
	for turn in 4:
		var foot: Array = _footprint_cells(structure, anchor, turn)
		if foot.size() != turn0.size():
			printerr("FAIL structure_rotation_four_turns: turn %d size %d, want %d"
					% [turn, foot.size(), turn0.size()])
			return 1
		seen[str(foot)] = true
	if seen.size() != 4:
		printerr("FAIL structure_rotation_four_turns: only %d distinct footprints in four turns" % seen.size())
		return 1
	var again: Array = _footprint_cells(structure, anchor, 4)
	if str(again) != str(turn0):
		printerr("FAIL structure_rotation_four_turns: turn 4 did not match turn 0")
		return 1
	print("PASS test_structure_rotation_four_turns")
	return 0


func _test_structure_rotation_blocked() -> int:
	## A rotated guard_post that overlaps its own unrotated footprint is refused.
	print("-- test_structure_rotation_blocked")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var structure := _guard_post()
	world.apply_map_params(_spawn_params(42, 0.0))
	world.generate_chunk(Vector2(0, 0))
	var anchor: Variant = null
	for cell in world.get_used_cells(0):
		if world.can_place_structure(structure, cell).is_empty():
			anchor = cell
			break
	if anchor == null:
		printerr("FAIL structure_rotation_blocked: no anchor on seed 42")
		scene.queue_free()
		return 1
	var id: int = world.place_structure(structure, anchor, 1)
	if id <= 0:
		printerr("FAIL structure_rotation_blocked: place failed at %s" % anchor)
		scene.queue_free()
		return 1
	for turn in [1, 2, 3]:
		if world.can_place_structure(structure, anchor, turn).is_empty():
			printerr("FAIL structure_rotation_blocked: turn %d should refuse overlap at %s" % [turn, anchor])
			fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_structure_rotation_blocked")
	return fail


func _test_structure_rotation_save_roundtrip() -> int:
	## A rotated placement round-trips through StructureSaves.
	print("-- test_structure_rotation_save_roundtrip")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var structure := _guard_post()
	var anchor: Variant = null
	for sv in [11, 42, 7, 99]:
		var params := _spawn_params(sv, 0.0)
		params.ensure_seeds()
		scene._apply_params_to_world(params)
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if world.can_place_structure(structure, cell, 1).is_empty():
				anchor = cell
				break
		if anchor != null:
			break
	if anchor == null:
		printerr("FAIL structure_rotation_save_roundtrip: no clear spot on seed 11")
		scene.queue_free()
		return 1
	if world.place_structure(structure, anchor, 1, 1) <= 0:
		printerr("FAIL structure_rotation_save_roundtrip: place at %s failed" % anchor)
		scene.queue_free()
		return 1
	var want: Array = world.structures_for_sync()
	var section: Dictionary = StructureSaves.to_changes(world)
	world._structures.clear()
	var placed := StructureSaves.restore(section, world)
	if placed != 1:
		printerr("FAIL structure_rotation_save_roundtrip: restore returned %s" % placed)
		fail += 1
	elif str(world.structures_for_sync()) != str(want):
		printerr("FAIL structure_rotation_save_roundtrip: want %s got %s" % [want, world.structures_for_sync()])
		fail += 1
	else:
		var p: Dictionary = world.placed_structures().values()[0]
		if int(p.get("rotation", 0)) != 1:
			printerr("FAIL structure_rotation_save_roundtrip: rotation %s, want 1" % p.get("rotation"))
			fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_structure_rotation_save_roundtrip")
	return fail