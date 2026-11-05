extends "res://tests/helpers/test_helpers.gd"
## The hit and fall frames of a chopped tree, bushy tree and pine (#333).


func _test_chop_tree_frames() -> int:
	## Each impact on a TREE, TREE_BUSHY or TREE_PINE_SMALL hides the tile
	## (HIDDEN_ALT, collision kept) and draws its own row of the type's
	## hit_sheet in its place, with fx_sheet frames 0-1 over it. The fall at
	## 560 ms keeps the puff and adds fx frames 2-3. The timing is the tree's:
	## impacts at 140 ms and 460 ms.
	print("-- test_chop_tree_frames")
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
	var plants := {Vector2i(9, 9): TileCatalog.TREE, Vector2i(10, 9): TileCatalog.TREE_BUSHY, Vector2i(11, 9): TileCatalog.TREE_PINE_SMALL}
	for cell: Vector2i in plants:
		world.set_cell(1, cell, TileCatalog.SOURCE_ID, plants[cell])
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)  # the test steps the chop clock itself
	interaction.set_mode(Interaction.Mode.INTERACT)
	var run_to := func(t: float) -> void:
		interaction.step_chop(t - maxf(interaction.chop_time, 0.0))
	var rows := {}  # type id -> {row: hit sheet row image}
	for cell: Vector2i in plants:
		var atlas: Vector2i = plants[cell]
		var type: InteractableType = world.choppable(cell)
		var tag := "%s at %s" % [atlas, cell]
		if type == null or type.hit_sheet == null or type.fx_sheet == null:
			printerr("FAIL chop_tree_frames: %s: type %s has no hit_sheet or fx_sheet" % [tag, type.id if type else null])
			fail += 1
			continue
		# One hit_sheet row per name in the type's tiles, in that order.
		var row := type.tiles.find(TileCatalog.TILES.keys().filter(
				func(n: String) -> bool: return TileCatalog.TILES[n]["atlas"] == atlas and type.tiles.has(n)).front())
		if not interaction.start_chop(cell):
			printerr("FAIL chop_tree_frames: %s: could not start the chop" % tag)
			fail += 1
			continue
		for hit_at in [0.15, 0.47]:
			run_to.call(hit_at)
			if world.get_cell_alternative_tile(1, cell) != Interaction.HIDDEN_ALT or not interaction._hit.visible \
					or interaction._hit.texture != type.hit_sheet or interaction._hit.frame_coords != Vector2i(0, row) \
					or not interaction._fx.visible or interaction._fx.texture != type.fx_sheet or interaction._fx.frame != 0:
				printerr("FAIL chop_tree_frames: %s at %s s: alt %s, hit %s %s, fx %s %s"
						% [tag, hit_at, world.get_cell_alternative_tile(1, cell), interaction._hit.visible,
						interaction._hit.frame_coords, interaction._fx.visible, interaction._fx.frame])
				fail += 1
			run_to.call(hit_at + 0.05)
			if interaction._hit.frame_coords != Vector2i(1, row) or interaction._fx.frame != 1:
				printerr("FAIL chop_tree_frames: %s: 50 ms after the impact hit %s, fx %s"
						% [tag, interaction._hit.frame_coords, interaction._fx.frame])
				fail += 1
			if hit_at < 0.4:
				run_to.call(0.3)
				if interaction._hit.visible or interaction._fx.visible or world.get_cell_alternative_tile(1, cell) != 0:
					printerr("FAIL chop_tree_frames: %s: the first hit did not end by 300 ms" % tag)
					fail += 1
		run_to.call(0.55)
		if world.choppable(cell) != type:
			printerr("FAIL chop_tree_frames: %s fell before 560 ms" % tag)
			fail += 1
		run_to.call(0.57)
		if world.choppable(cell) != null or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell) != TileCatalog.STUMP \
				or not interaction._puff.visible or interaction._hit.visible or not interaction._fx.visible or interaction._fx.frame != 2:
			printerr("FAIL chop_tree_frames: %s at 560 ms: decor %s, puff %s, hit %s, fx %s %s"
					% [tag, world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell), interaction._puff.visible,
					interaction._hit.visible, interaction._fx.visible, interaction._fx.frame])
			fail += 1
		run_to.call(0.75)
		if not interaction._fx.visible or interaction._fx.frame != 3:
			printerr("FAIL chop_tree_frames: %s at 750 ms fx %s %s, want frame 3" % [tag, interaction._fx.visible, interaction._fx.frame])
			fail += 1
		interaction.step_chop(1.0)
		interaction.step_chop(1.0)
		var img := type.hit_sheet.get_image()
		rows.get_or_add(type.id, {})[row] = img.get_region(Rect2i(0, row * 16, img.get_width(), 16))
	# TREE and TREE_BUSHY share tree.tres but each shakes its own art.
	var tree_rows: Dictionary = rows.get("tree", {})
	if tree_rows.size() != 2 or tree_rows[0].get_data() == tree_rows[1].get_data():
		printerr("FAIL chop_tree_frames: TREE and TREE_BUSHY do not have their own hit_sheet rows: %s" % [tree_rows.keys()])
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_tree_frames")
	return fail


func _test_hit_row_miss_warns() -> int:
	## hit_row push_warnings and sets last_hit_row_missed when the atlas is
	## not in tiles, then still returns row 0 (#357). Time cost: ~0.05 s in
	## verify (~1.4 s alone with --only=, Godot boot dominates).
	print("-- test_hit_row_miss_warns")
	var type := InteractableType.new()
	type.id = "tree_fixture"
	var tile_names: Array[String] = ["TREE"]
	type.tiles = tile_names
	var known: Vector2i = TileCatalog.TILES["TREE"]["atlas"]
	var unknown: Vector2i = TileCatalog.TILES["TREE_BUSHY"]["atlas"]
	var known_row: int = type.hit_row(known)
	if known_row != 0 or type.last_hit_row_missed:
		printerr("FAIL hit_row_miss_warns: known atlas %s row/miss %s/%s"
				% [known, known_row, type.last_hit_row_missed])
		return 1
	var row: int = type.hit_row(unknown)
	if row != 0 or not type.last_hit_row_missed:
		printerr("FAIL hit_row_miss_warns: miss atlas %s row=%s missed=%s, want 0 and true"
				% [unknown, row, type.last_hit_row_missed])
		return 1
	print("PASS test_hit_row_miss_warns")
	return 0


func _test_hit_sheets_match_golden() -> int:
	## tree_hit.png and pine_hit.png match tests/golden/hit_sheets.txt (sha256
	## and size). TREE and TREE_BUSHY share tree_hit; pine uses pine_hit.
	## Changing or resizing a sheet fails this test (#357). Time cost: ~0.1 s
	## in verify (~1.5 s alone with --only=).
	print("-- test_hit_sheets_match_golden")
	var fail := 0
	var golden_path := "res://tests/golden/hit_sheets.txt"
	var text := FileAccess.get_file_as_string(golden_path)
	if text.is_empty():
		printerr("FAIL hit_sheets_match_golden: missing %s" % golden_path)
		return 1
	var want := {}  # path -> {sha, w, h}
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.is_empty() or s.begins_with("#"):
			continue
		var parts := s.split(" ")
		if parts.size() != 4:
			printerr("FAIL hit_sheets_match_golden: bad golden line %s" % s)
			fail += 1
			continue
		want[parts[0]] = {"sha": parts[1], "w": int(parts[2]), "h": int(parts[3])}
	# Tree (covers TREE + TREE_BUSHY rows) and pine hit sheets from the catalog.
	var by_id := {
		"tree": "art/flagoria/fx/tree_hit.png",
		"pine": "art/flagoria/fx/pine_hit.png",
	}
	for id in by_id:
		var type: InteractableType = InteractableCatalog.by_id(id)
		if type == null or type.hit_sheet == null:
			printerr("FAIL hit_sheets_match_golden: type %s has no hit_sheet" % id)
			fail += 1
			continue
		var path: String = type.hit_sheet.resource_path.trim_prefix("res://")
		if path != by_id[id]:
			printerr("FAIL hit_sheets_match_golden: %s hit_sheet is %s, want %s" % [id, path, by_id[id]])
			fail += 1
		if not want.has(path):
			printerr("FAIL hit_sheets_match_golden: no golden row for %s" % path)
			fail += 1
			continue
		var abs_path := "res://%s" % path
		var got_sha := FileAccess.get_sha256(abs_path)
		var tex: Texture2D = type.hit_sheet
		var g: Dictionary = want[path]
		if got_sha != g["sha"] or tex.get_width() != g["w"] or tex.get_height() != g["h"]:
			printerr("FAIL hit_sheets_match_golden: %s sha/size %s %dx%d, want %s %dx%d"
					% [path, got_sha, tex.get_width(), tex.get_height(), g["sha"], g["w"], g["h"]])
			fail += 1
		# Frame layout: 16 px rows, one per tiles entry; width a multiple of 16.
		var rows: int = type.tiles.size()
		if tex.get_height() != 16 * rows or tex.get_width() % 16 != 0:
			printerr("FAIL hit_sheets_match_golden: %s is %dx%d, want width%%16==0 and height %d"
					% [path, tex.get_width(), tex.get_height(), 16 * rows])
			fail += 1
	# TREE_BUSHY is row 1 of the tree sheet (same file as TREE).
	var tree: InteractableType = InteractableCatalog.by_id("tree")
	if tree != null and tree.tiles.size() >= 2:
		var bushy_atlas: Vector2i = TileCatalog.TILES[tree.tiles[1]]["atlas"]
		if tree.hit_row(bushy_atlas) != 1 or tree.last_hit_row_missed:
			printerr("FAIL hit_sheets_match_golden: TREE_BUSHY row is %s missed=%s, want 1"
					% [tree.hit_row(bushy_atlas), tree.last_hit_row_missed])
			fail += 1
	if fail == 0:
		print("PASS test_hit_sheets_match_golden (%s sheets)" % want.size())
	return fail

