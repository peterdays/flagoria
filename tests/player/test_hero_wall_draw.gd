extends "res://tests/helpers/test_helpers.gd"
## The hero draws over a wall until most of the body is on the wall.


func _test_hero_draws_over_wall_face() -> int:
	## A body that only overlaps the face of a wall stays above the wall caps.
	## Once about two thirds of the body is on the wall, the wall draws over
	## the hero. Time cost: about 0.3 s in tools/verify.sh (~1.5 s alone).
	print("-- test_hero_draws_over_wall_face")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(6, 16):
		for y in range(6, 14):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	var wall := Vector2i(10, 8)
	world.set_cell(1, wall, TileCatalog.SOURCE_ID, TileCatalog.WALL_H)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	scene.get_node("World").add_child(player)
	await process_frame
	var center: Vector2 = world.to_global(world.map_to_local(wall))
	var bottom := center.y + 8.0
	var front_z: int = world.get_layer_z_index(4) + 1
	# 6 px of the 16 px body on the wall: the head overlaps, the hero stays in front.
	player.position = Vector2(center.x, bottom + 10.0)
	await process_frame
	if player.z_index != front_z:
		printerr("FAIL hero_draws_over_wall_face: head overlap z %s, want %s" % [player.z_index, front_z])
		fail += 1
	# 12 px of the body on the wall: most of the hero is inside, the wall covers them.
	player.position = Vector2(center.x, bottom + 4.0)
	await process_frame
	if player.z_index != 0:
		printerr("FAIL hero_draws_over_wall_face: deep overlap z %s, want 0" % player.z_index)
		fail += 1
	# Clear ground does not lift the hero over the trees.
	player.position = Vector2(center.x, bottom + 40.0)
	await process_frame
	if player.z_index != 0:
		printerr("FAIL hero_draws_over_wall_face: open ground z %s" % player.z_index)
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_hero_draws_over_wall_face")
	return fail
