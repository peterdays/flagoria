extends SceneTree
## Capture the Cut/Plank picker and a plank drag preview under xvfb (#225).


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err = change_scene_to_file("res://flagoria_main.tscn")
	if err != OK:
		push_error("capture_build_placement: failed to load main scene")
		quit(1)
		return
	for i in range(20):
		await process_frame

	var flagoria = current_scene
	if flagoria == null:
		push_error("capture_build_placement: no current scene")
		quit(1)
		return

	var menu = flagoria.get_node_or_null("CanvasLayer2/MainMenu")
	if menu:
		menu.hide()
		menu.set_process_unhandled_input(false)
	flagoria.get_node("CanvasLayer1").show()

	var world = flagoria.get_node("World/worldMap")
	var land := func(c: Vector2i) -> bool:
		return not world.has_bridge(c) and world.ground_is_walkable(world.predict_cell(c)[0])
	var shore := Vector2i.ZERO
	var water_run: Array[Vector2i] = []
	for s in [11, 42, 7, 1, 99, 3, 5]:
		var params := MapGenParams.make_defaults()
		params.altitude_seed = s
		params.moisture_seed = s
		params.temperature_seed = s
		params.items_seed = s
		params.biome_frequency = 0.0
		world.apply_map_params(params)
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if not land.call(cell):
				continue
			var run: Array[Vector2i] = []
			for i in range(1, 4):
				var w: Vector2i = cell + Vector2i(i, 0)
				if world.predict_cell(w)[0] != TileCatalog.WATER or world.has_bridge(w):
					break
				run.append(w)
			if run.size() >= 2:
				shore = cell
				water_run = run
				break
		if not water_run.is_empty():
			break
	if water_run.is_empty():
		push_error("capture_build_placement: no shore run")
		quit(1)
		return

	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(flagoria.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(shore))
	flagoria.get_node("World").add_child(player)
	var interaction: Interaction = flagoria.get_node("World/Interaction")
	interaction.bind(player)
	var inventory: Inventory = flagoria.get_node("Inventory")
	inventory.add(Inventory.WOOD, water_run.size() + 4)

	# Camera on the shore so the picker and preview are in frame.
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.make_current()

	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	var start: Vector2 = interaction.get_canvas_transform() * world.to_global(world.map_to_local(water_run[0]))
	var end: Vector2 = interaction.get_canvas_transform() * world.to_global(
			world.map_to_local(water_run[water_run.size() - 1]))
	interaction.build.update_preview(start, end)
	# Fake an active drag so _draw runs the preview every frame.
	interaction._dragging = true
	interaction._start = start
	interaction._end = end
	interaction.queue_redraw()

	for i in range(20):
		await process_frame

	var out_res := "res://docs/screenshots/build_placement_preview.png"
	var abs_out := ProjectSettings.globalize_path(out_res)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var img = flagoria.get_viewport().get_texture().get_image()
	if img == null:
		push_error("capture_build_placement: no viewport image")
		quit(1)
		return
	var save_err = img.save_png(abs_out)
	print("capture_build_placement: save_err=", save_err, " path=", out_res,
			" cells=", interaction.build.cells, " cost=", interaction.build.cost)
	if save_err != OK:
		quit(1)
		return
	print("BUILD_PLACEMENT_SCREENSHOT_OK")
	quit(0)
