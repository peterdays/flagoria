extends SceneTree
## Capture the Cut/Plank/Tower picker and a tower footprint preview under xvfb (#273).


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err = change_scene_to_file("res://flagoria_main.tscn")
	if err != OK:
		push_error("capture_build_tower: failed to load main scene")
		quit(1)
		return
	for i in range(20):
		await process_frame

	var flagoria = current_scene
	if flagoria == null:
		push_error("capture_build_tower: no current scene")
		quit(1)
		return

	var menu = flagoria.get_node_or_null("CanvasLayer2/MainMenu")
	if menu:
		menu.hide()
		menu.set_process_unhandled_input(false)
	flagoria.get_node("CanvasLayer1").show()

	var world = flagoria.get_node("World/worldMap")
	var structure: Structure = StructurePlacer.load_named("tower_wood")
	var anchor := Vector2i.ZERO
	var found := false
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
			var foot: Array = StructurePlacer.footprint(structure, cell).keys()
			if foot.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
				anchor = cell
				found = true
				break
		if found:
			break
	if not found:
		push_error("capture_build_tower: no clear 3x3 land")
		quit(1)
		return

	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(flagoria.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(anchor + Vector2i(0, 3)))
	flagoria.get_node("World").add_child(player)
	var interaction: Interaction = flagoria.get_node("World/Interaction")
	interaction.bind(player)
	var inventory: Inventory = flagoria.get_node("Inventory")
	inventory.add(Inventory.WOOD, 10)

	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.make_current()

	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.TOWER)
	var vp: Vector2 = interaction.get_canvas_transform() * world.to_global(world.map_to_local(anchor))
	interaction.build.update_preview(vp, vp)
	interaction._dragging = true
	interaction._start = vp
	interaction._end = vp
	interaction.queue_redraw()

	for i in range(20):
		await process_frame

	var out_res := "res://docs/screenshots/build_tower_preview.png"
	var abs_out := ProjectSettings.globalize_path(out_res)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var img = flagoria.get_viewport().get_texture().get_image()
	if img == null:
		push_error("capture_build_tower: no viewport image")
		quit(1)
		return
	var save_err = img.save_png(abs_out)
	print("capture_build_tower: save_err=", save_err, " path=", out_res,
			" cells=", interaction.build.cells, " cost=", interaction.build.cost,
			" ok=", interaction.build.cell_ok)
	if save_err != OK:
		quit(1)
		return
	print("BUILD_TOWER_SCREENSHOT_OK")
	quit(0)
