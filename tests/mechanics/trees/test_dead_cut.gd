extends "res://tests/helpers/test_helpers.gd"
## A dead hero cuts nothing in interact mode (#349). The client case, with
## the host's own check, is test_dead_cut_client (tests/net/test_cut_sync.gd).


func _test_dead_cut_alone() -> int:
	## Alone, with the hero dead: a drag over a tree in reach and a tap on it
	## leave the tree and add no wood. After the respawn the same drag cuts it.
	print("-- test_dead_cut_alone")
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
	var tree := Vector2i(10, 8)
	world.set_cell(1, tree, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	var below: Vector2 = world.to_global(world.map_to_local(Vector2i(10, 10)))
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
	var swipe := func() -> void:  # a drag across the tree
		touch.call(at.call(Vector2(9.2, 8.3)), true)
		var e := InputEventScreenDrag.new()
		e.position = at.call(Vector2(11.8, 8.7))
		vp.push_input(e, true)
		touch.call(at.call(Vector2(11.8, 8.7)), false)
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
	health.respawn()
	player.position = below
	swipe.call()
	if world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL dead_cut_alone: after the respawn the drag left tree %s, wood %s"
				% [world.has_tree(tree), inventory.count_of(Inventory.WOOD)])
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_dead_cut_alone")
	return fail
