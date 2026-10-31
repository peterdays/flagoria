extends "res://tests/helpers/test_helpers.gd"
## Minimap panel and the explored map.


func _test_minimap_panel_in_scene() -> int:
	## In the real main scene the wood panel shows in the top right once the
	## local hero spawns, below the HUD buttons and clear of the attack
	## button, counts as HUD for touches, reveals once two samples agree, draws
	## the explored cells around the hero in the map colours, M hides it, and
	## a new world clears what was explored.
	print("-- test_minimap_panel_in_scene")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	await process_frame
	var panel: MinimapPanel = scene.get_node("CanvasLayer1/MinimapPanel")
	panel.set_physics_process(false)  # ticks run by hand below
	panel.tick()
	if panel.visible:
		printerr("FAIL minimap_panel visible before the hero spawns")
		fail += 1
	scene.add_player(scene.multiplayer.get_unique_id())
	await process_frame
	panel.tick()
	if panel.explored.explored_count() != 0:
		printerr("FAIL minimap_panel revealed on a single sample")
		fail += 1
	panel.tick()
	var rect: Rect2 = panel.get_global_rect()
	var mode_rect: Rect2 = scene.get_node("CanvasLayer1/ModeButton").get_global_rect()
	var attack: TouchScreenButton = scene.get_node("CanvasLayer1/TouchScreenButton")
	var attack_rect := Rect2(attack.position, attack.texture_normal.get_size() * attack.scale)
	var view_w: float = scene.get_viewport().get_visible_rect().size.x
	if not panel.visible or absf(rect.end.x - (view_w - MinimapPanel.MARGIN * panel.scale.x)) > 1.0 \
			or rect.size.round() != (Vector2(224, 144) * panel.scale).round() or rect.intersects(mode_rect) \
			or rect.intersects(attack_rect):
		printerr("FAIL minimap_panel visible %s at %s (mode button %s, attack button %s)"
				% [panel.visible, rect, mode_rect, attack_rect])
		fail += 1
	scene.get_node("CanvasLayer1").show()  # as Host and Join do
	var zoom = scene.get_node("World/%d/Camera2D/MapZoom" % scene.multiplayer.get_unique_id())
	if not zoom.starts_on_hud(rect.get_center()):
		printerr("FAIL minimap_panel touches on the panel are not HUD touches")
		fail += 1
	var hero: Vector2i = panel.hero_cell
	var tex: ImageTexture = panel.chunk_texture(ExploredMap.chunk_of(hero))
	if not panel.explored.is_explored(hero) or panel.explored.explored_count() != 317 or tex == null:
		printerr("FAIL minimap_panel explored %s cells around %s" % [panel.explored.explored_count(), hero])
		fail += 1
	else:
		var img := tex.get_image()
		var local := (hero - ExploredMap.chunk_of(hero) * ExploredMap.CHUNK) * MinimapPanel.CELL_PX + Vector2i.ONE
		var p: Array = world.predict_cell(hero)
		var want := MinimapPanel.cell_colour(p, false, hero, hero.x * 2 + 1, hero.y * 2 + 1)
		var got := img.get_pixelv(local)
		var far := Vector2i(hero.x + 12, hero.y)
		var far_px := (far - ExploredMap.chunk_of(far) * ExploredMap.CHUNK) * MinimapPanel.CELL_PX
		var far_tex: ImageTexture = panel.chunk_texture(ExploredMap.chunk_of(far))
		if got != want and got != MinimapPanel.INK:
			printerr("FAIL minimap_panel hero cell drawn %s, want %s" % [got, want])
			fail += 1
		if far_tex and far_tex.get_image().get_pixelv(far_px).a != 0.0:
			printerr("FAIL minimap_panel unexplored cell %s is not left to the mist" % far)
			fail += 1
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	panel._unhandled_key_input(key)
	panel.tick()
	if panel.visible:
		printerr("FAIL minimap_panel still visible after M")
		fail += 1
	panel._unhandled_key_input(key)
	panel.tick()
	if not panel.visible:
		printerr("FAIL minimap_panel hidden after a second M")
		fail += 1
	world.apply_map_params(_spawn_params(7, 0.003))
	if panel.explored.explored_count() != 0 or panel.chunk_texture(ExploredMap.chunk_of(hero)) != null:
		printerr("FAIL minimap_panel kept %s cells after a new world" % panel.explored.explored_count())
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_minimap_panel_in_scene")
	return fail


func _test_minimap_incremental_render() -> int:
	## Painting only the newly revealed cells (and the ring around them) gives
	## the same chunk images, pixel for pixel, as drawing each chunk from
	## scratch, across chunk edges and coast lines, and reuses each chunk's
	## texture.
	print("-- test_minimap_incremental_render")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	await process_frame
	var panel: MinimapPanel = scene.get_node("CanvasLayer1/MinimapPanel")
	panel.set_physics_process(false)
	var cell := Vector2i(-40, -40)
	var first_tex: ImageTexture = null
	for leg in [Vector2i(3, 0), Vector2i(0, 3), Vector2i(-2, 1), Vector2i(1, -3)]:
		for i in 25:
			panel.reveal_around(cell)
			if first_tex == null:
				first_tex = panel.chunk_texture(ExploredMap.chunk_of(cell))
			cell += leg
	if panel.chunk_texture(ExploredMap.chunk_of(Vector2i(-40, -40))) != first_tex:
		printerr("FAIL minimap_incremental_render: a chunk texture was replaced, not updated")
		fail += 1
	var ink := 0
	var water := 0
	for chunk in panel.explored.chunks():
		var got := panel.chunk_image(chunk)  # the headless renderer keeps no texture pixels
		var want := panel.render_chunk(chunk)
		if got.get_data() != want.get_data():
			printerr("FAIL minimap_incremental_render: chunk %s differs from a full render" % chunk)
			fail += 1
		for y in want.get_height():
			for x in want.get_width():
				var c := want.get_pixel(x, y)
				ink += int(c == MinimapPanel.INK)
				water += int(c == MinimapPanel.SKY or c == MinimapPanel.SKY_DEEP)
	if ink == 0 or water == 0 or panel.explored.chunks().size() < 6:
		printerr("FAIL minimap_incremental_render: walk too plain (%d ink, %d water px, %d chunks)"
				% [ink, water, panel.explored.chunks().size()])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_minimap_incremental_render")
	return fail


func _test_explored_map() -> int:
	## Revealing marks every cell within 10 cells (Euclidean) of the hero, in
	## 32 x 32 chunks of 128-byte bitsets, across negative coordinates; a
	## second reveal at the same spot changes nothing and clear() forgets all.
	print("-- test_explored_map")
	var fail := 0
	var map := ExploredMap.new()
	var changed := map.reveal(Vector2i.ZERO)
	var want_chunks := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]
	if changed.size() != 4 or want_chunks.any(func(c): return not c in changed):
		printerr("FAIL explored_map changed chunks %s" % [changed])
		fail += 1
	if map.explored_count() != 317:  # lattice points with x^2 + y^2 <= 100
		printerr("FAIL explored_map %s cells explored, want 317" % map.explored_count())
		fail += 1
	for c in [[Vector2i(10, 0), true], [Vector2i(-10, 0), true], [Vector2i(8, -6), true],
			[Vector2i(-8, 7), false], [Vector2i(11, 0), false], [Vector2i(0, -11), false]]:
		if map.is_explored(c[0]) != c[1]:
			printerr("FAIL explored_map is_explored(%s) != %s" % c)
			fail += 1
	if ExploredMap.chunk_of(Vector2i(-1, -33)) != Vector2i(-1, -2) or ExploredMap.chunk_of(Vector2i(31, 32)) != Vector2i(0, 1):
		printerr("FAIL explored_map chunk_of")
		fail += 1
	if map.chunk_bits(Vector2i.ZERO).size() != ExploredMap.CHUNK_BYTES or not map.chunk_bits(Vector2i(5, 5)).is_empty():
		printerr("FAIL explored_map chunk_bits sizes")
		fail += 1
	var again := map.reveal(Vector2i.ZERO)
	var step := map.reveal(Vector2i(1, 0))  # only the new east edge, all at x >= 0
	if not again.is_empty() or step.size() != 2 or not Vector2i(0, -1) in step or not Vector2i(0, 0) in step:
		printerr("FAIL explored_map repeat reveal changed chunks")
		fail += 1
	map.clear()
	if map.explored_count() != 0 or map.is_explored(Vector2i.ZERO):
		printerr("FAIL explored_map clear")
		fail += 1
	if fail == 0:
		print("PASS test_explored_map")
	return fail
