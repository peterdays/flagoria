extends "res://tests/helpers/test_helpers.gd"
## A dead hero cuts nothing in interact mode (#349). The client case, with
## the host's own check, is test_dead_cut_client (tests/net/test_cut_sync.gd).


func _test_dead_cut_alone() -> int:
	## Alone, with the hero dead: a drag over a tree in reach and a tap on it
	## leave the tree and add no wood. After the respawn the same drag, one tree
	## in the box, plays the chop; stepping it fells the tree.
	## Time cost: about 0.5 s alone with --only=dead_cut_alone (~2 s runner
	## start-up). Isolation: the painted patch must survive respawn (#359).
	print("-- test_dead_cut_alone")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	var world = scene.get_node("World/worldMap")
	# Painted scenes: freeze chunk redraw and pin spawn so respawn's
	# resolve_player_spawn does not generate_chunk over the paint (#359).
	root.get_node("MapGen").reset_to_defaults()
	world.set_process(false)
	world.clear()
	for x in range(4, 16):
		for y in range(4, 14):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	var tree := Vector2i(10, 8)
	world.set_cell(1, tree, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var stand := Vector2i(10, 10)
	world.spawn_point = stand
	world._castle_front = stand
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	var below: Vector2 = world.to_global(world.map_to_local(stand))
	player.position = below
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)
	interaction.set_mode(Interaction.Mode.INTERACT)
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	var at := func(cell: Vector2) -> Vector2:  # cell units (0.5 = centre) to viewport px
		return interaction.get_canvas_transform() * world.to_global(cell * 16.0)
	var touch := func(pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.position = pos
		e.pressed = pressed
		vp.push_input(e, true)
	var swipe := func() -> void:  # aim from the hero up through the tree
		touch.call(at.call(Vector2(10.5, 10.5)), true)
		var e := InputEventScreenDrag.new()
		e.position = at.call(Vector2(10.5, 8.2))
		vp.push_input(e, true)
		touch.call(at.call(Vector2(10.5, 8.2)), false)
	var health: PlayerHealth = player.health
	health.set_health_now(0)
	swipe.call()
	touch.call(at.call(Vector2(10.5, 8.5)), true)
	touch.call(at.call(Vector2(10.5, 8.5)), false)
	interaction.step_chop(1.0)
	if not world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != 0 or interaction.chopping():
		printerr("FAIL dead_cut_alone: dead, the drag and tap left tree %s, wood %s, chopping %s"
				% [world.has_tree(tree), inventory.count_of(Inventory.WOOD), interaction.chopping()])
		fail += 1
	# Revive without resolve_player_spawn: respawn() searches from the origin
	# and generate_chunk would redraw the painted patch (#359).
	health.set_health_now(health.max_health)
	player.position = below
	swipe.call()
	# One tree in the drag plays the chop; it is not a stump until the swings finish.
	if not interaction.chopping() or not world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL dead_cut_alone: after the respawn the drag did not start a chop (tree %s, wood %s, chopping %s)"
				% [world.has_tree(tree), inventory.count_of(Inventory.WOOD), interaction.chopping()])
		fail += 1
	interaction.step_chop(1.0)
	if world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL dead_cut_alone: after the respawn the chop left tree %s, wood %s"
				% [world.has_tree(tree), inventory.count_of(Inventory.WOOD)])
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_dead_cut_alone")
	return fail


func _test_painted_tree_survives_respawn() -> int:
	## With MapGen seeds that grow a bush at (10, 8), a painted TREE there
	## must still be a tree after health.respawn() (#359). A wide grass pad
	## plus a pinned stand cell keeps resolve_player_spawn on painted land
	## so it never generate_chunk. Time cost: about 0.5 s alone with
	## --only=painted_tree_survives_respawn.
	print("-- test_painted_tree_survives_respawn")
	var fail := 0
	var p := MapGenParams.make_defaults()
	for key in ["altitude_seed", "moisture_seed", "temperature_seed", "items_seed", "biome_seed"]:
		p.set(key, 6)
	root.get_node("MapGen").params = p
	root.get_node("MapGen").save_to_disk()
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	root.get_node("MapGen").reset_to_defaults()
	world.set_process(false)
	world.clear()
	for x in range(-48, 49):
		for y in range(-48, 49):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	var tree := Vector2i(10, 8)
	world.set_cell(1, tree, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var stand := Vector2i(10, 10)
	world.spawn_point = stand
	world._castle_front = stand
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	var below: Vector2 = world.to_global(world.map_to_local(stand))
	player.position = below
	scene.get_node("World").add_child(player)
	await process_frame
	player.health.set_health_now(0)
	player.health.respawn()
	if not world.has_tree(tree) or world.get_cell_atlas_coords(1, tree) != TileCatalog.TREE:
		printerr("FAIL painted_tree_survives_respawn: after respawn cell %s atlas %s has_tree %s"
				% [tree, world.get_cell_atlas_coords(1, tree), world.has_tree(tree)])
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_painted_tree_survives_respawn")
	return fail
