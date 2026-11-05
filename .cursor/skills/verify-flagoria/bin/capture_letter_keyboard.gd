extends SceneTree
## Open the main-menu letter keyboard and save a PNG at the project viewport
## size (480x270). Invoked by drive-letter-keyboard-screenshot.sh.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err := change_scene_to_file("res://flagoria_main.tscn")
	if err != OK:
		push_error("capture_letter_keyboard: failed to load main scene")
		quit(1)
		return
	for i in range(20):
		await process_frame
	var flagoria = current_scene
	if flagoria == null:
		push_error("capture_letter_keyboard: no current scene")
		quit(1)
		return
	var menu: Node = flagoria.get_node("CanvasLayer2/MainMenu")
	var field: LineEdit = menu.address_entry
	field.text = "my-host.local"
	field.grab_focus()
	for i in range(10):
		await process_frame
	var kb: Control = menu.get_node("LetterKeyboard")
	if not kb.visible:
		push_error("capture_letter_keyboard: letter keyboard not visible")
		quit(1)
		return
	var img: Image = flagoria.get_viewport().get_texture().get_image()
	if img == null:
		push_error("capture_letter_keyboard: no viewport image")
		quit(1)
		return
	var out_path := "res://docs/screenshots/letter_keyboard_480x270.png"
	var abs_out := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var save_err := img.save_png(abs_out)
	if save_err != OK:
		push_error("capture_letter_keyboard: save_png failed %s" % save_err)
		quit(1)
		return
	print("wrote %s (%dx%d) panel_min=%s"
			% [abs_out, img.get_width(), img.get_height(),
			kb.get_node("Panel").get_combined_minimum_size()])
	quit(0)
