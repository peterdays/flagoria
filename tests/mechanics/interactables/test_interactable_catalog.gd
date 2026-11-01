extends "res://tests/helpers/test_helpers.gd"
## InteractableCatalog: which type a cell is, and the per-type regrow delay.


func _test_catalog_resolves_cells() -> int:
	## The catalog resolves TREE, PINE (TREE_PINE_SMALL) and BUSH cells to
	## their own types (#266) and grass to none. The pine has the tree's
	## values today (hits, wood, stump, regrow delay, sounds, effects), so
	## splitting them changes nothing; has_tree is true for both. Each type
	## has its own save_key.
	print("-- test_catalog_resolves_cells")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	world.clear()
	var want := {
		TileCatalog.TREE: "tree", TileCatalog.PINE: "pine", TileCatalog.BUSH: "bush", TileCatalog.GRASS_A: "",
	}
	var x := 0
	for atlas: Vector2i in want:
		var cell := Vector2i(x, 0)
		world.set_cell(0, cell, TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
		if atlas != TileCatalog.GRASS_A:
			world.set_cell(1, cell, TileCatalog.SOURCE_ID, atlas)
		var type: InteractableType = world.choppable(cell)
		var got := type.id if type != null else ""
		if got != want[atlas] or InteractableCatalog.type_at(atlas) != type:
			printerr("FAIL catalog_resolves_cells: %s at %s is %s, want %s" % [atlas, cell, got, want[atlas]])
			fail += 1
		if world.has_tree(cell) != (got == "tree" or got == "pine"):
			printerr("FAIL catalog_resolves_cells: has_tree(%s) is %s for %s" % [cell, world.has_tree(cell), got])
			fail += 1
		x += 1
	var tree := InteractableCatalog.by_id("tree")
	var pine := InteractableCatalog.by_id("pine")
	for prop in ["hits", "yields", "leaves", "regrow_delay", "hit_sounds", "fell_sounds", "hit_no_repeat",
			"fell_own_player", "hit_layer_sounds", "last_hit_sounds", "pickup_sounds", "hit_sheet", "fx_sheet",
			"fell_puff"]:
		if tree.get(prop) != pine.get(prop):
			printerr("FAIL catalog_resolves_cells: pine %s %s differs from the tree's %s" % [prop, pine.get(prop), tree.get(prop)])
			fail += 1
	var keys := {}
	for type: InteractableType in InteractableCatalog.TYPES:
		if type.save_key == "" or keys.has(type.save_key) or type.regrow_delay != 300.0:
			printerr("FAIL catalog_resolves_cells: %s save_key %s regrow_delay %s" % [type.id, type.save_key, type.regrow_delay])
			fail += 1
		keys[type.save_key] = true
	scene.queue_free()
	return fail


func _test_regrow_delay_per_type() -> int:
	## With no map-wide regrow_delay set, a stump regrows after its type's
	## regrow_delay (300 s for every type today), and a type with 0 never
	## regrows.
	print("-- test_regrow_delay_per_type")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	world.clear()
	var cells := {Vector2i(0, 0): TileCatalog.PINE, Vector2i(2, 0): TileCatalog.BUSH}
	for cell: Vector2i in cells:
		world.set_cell(0, cell, TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
		world.set_cell(1, cell, TileCatalog.SOURCE_ID, cells[cell])
		world.cut_choppable(cell)
	if world.regrow_delay >= 0.0:
		printerr("FAIL regrow_delay_per_type: map regrow_delay %s overrides the types by default" % world.regrow_delay)
		fail += 1
	world.play_time = 299.9
	if world.regrow_due() != 0:
		printerr("FAIL regrow_delay_per_type: a stump regrew before 300 s")
		fail += 1
	var bush := InteractableCatalog.by_id("bush")
	bush.regrow_delay = 0.0
	world.play_time = 300.0
	var grown: int = world.regrow_due()
	world.play_time = 10000.0
	var later: int = world.regrow_due()
	bush.regrow_delay = 300.0
	if grown != 1 or later != 0 or not world._tree_cuts.has_cut(Vector2i(2, 0)):
		printerr("FAIL regrow_delay_per_type: regrew %d at 300 s and %d later, bush still cut %s; want 1, 0, true"
				% [grown, later, world._tree_cuts.has_cut(Vector2i(2, 0))])
		fail += 1
	scene.queue_free()
	return fail
