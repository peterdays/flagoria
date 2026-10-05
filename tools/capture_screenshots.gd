extends SceneTree
## Capture admin panel + two differently parameterized maps for the PR.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err = change_scene_to_file("res://flagoria_main.tscn")
	if err != OK:
		push_error("Failed to load main scene: %s" % err)
		quit(1)
		return
	for i in range(10):
		await process_frame

	var flagoria = current_scene
	if flagoria == null:
		push_error("No current scene")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")

	var menu = flagoria.get_node_or_null("CanvasLayer2/MainMenu")
	if menu and menu.has_method("_on_map_settings_pressed"):
		menu._on_map_settings_pressed()
	for i in range(15):
		await process_frame
	_shot(flagoria.get_viewport(), "res://docs/screenshots/admin_panel.png")

	var admin = flagoria.get_node_or_null("CanvasLayer2/MapAdminPanel")
	if admin:
		admin.hide()
	if menu:
		menu.hide()

	var world = flagoria.get_node("World/worldMap")
	var params_a = MapGenParams.make_defaults()
	params_a.altitude_seed = 42
	params_a.moisture_seed = 42
	params_a.temperature_seed = 42
	params_a.items_seed = 42
	params_a.water_max_alt = 0.1
	params_a.altitude_frequency = 0.03
	world.apply_map_params(params_a)
	world.generate_chunk(Vector2(0, 0))
	for i in range(5):
		await process_frame
	_shot(flagoria.get_viewport(), "res://docs/screenshots/map_low_water.png")

	var params_b = MapGenParams.make_defaults()
	params_b.altitude_seed = 99
	params_b.moisture_seed = 99
	params_b.temperature_seed = 99
	params_b.items_seed = 99
	params_b.water_max_alt = 0.45
	params_b.sand_max_alt = 0.5
	params_b.altitude_frequency = 0.015
	params_b.tree_min_chance = -0.5
	world.apply_map_params(params_b)
	world.generate_chunk(Vector2(0, 0))
	for i in range(5):
		await process_frame
	_shot(flagoria.get_viewport(), "res://docs/screenshots/map_high_water.png")

	print("SCREENSHOTS_DONE")
	quit(0)


func _shot(viewport: Viewport, path: String) -> void:
	var img = viewport.get_texture().get_image()
	if img == null:
		push_error("No image from viewport for %s" % path)
		return
	var err = img.save_png(path)
	print("saved %s err=%s size=%sx%s" % [path, err, img.get_width(), img.get_height()])
