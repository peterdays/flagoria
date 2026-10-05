extends SceneTree
## Opens Map Settings and writes a PNG into the skill artifacts folder.
## Invoked by drive-map-settings-screenshot.sh (not by tools/verify.sh).

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err = change_scene_to_file("res://flagoria_main.tscn")
	if err != OK:
		push_error("capture_map_settings: failed to load main scene")
		quit(1)
		return
	for i in range(20):
		await process_frame

	var flagoria = current_scene
	if flagoria == null:
		push_error("capture_map_settings: no current scene")
		quit(1)
		return

	var menu = flagoria.get_node_or_null("CanvasLayer2/MainMenu")
	if menu == null or not menu.has_method("_on_map_settings_pressed"):
		push_error("capture_map_settings: Map Settings entry missing")
		quit(1)
		return

	menu._on_map_settings_pressed()
	for i in range(20):
		await process_frame

	var img = flagoria.get_viewport().get_texture().get_image()
	if img == null:
		push_error("capture_map_settings: no viewport image")
		quit(1)
		return

	# Repo-relative artifacts path (ProjectSettings.globalize_path for res://)
	var out_res := "res://.cursor/skills/verify-flagoria/artifacts/map_settings.png"
	var abs_out := ProjectSettings.globalize_path(out_res)
	var save_err = img.save_png(abs_out)
	print("capture_map_settings: save_err=", save_err, " path=", out_res)
	if save_err != OK:
		quit(1)
		return
	print("MAP_SETTINGS_SCREENSHOT_OK")
	quit(0)
