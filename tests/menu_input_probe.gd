extends SceneTree
## Loads the main scene and feeds the main menu a burst of unhandled input
## events, then quits. Run as a subprocess by test_main_menu_input_no_log_spam
## in run_tests.gd, which checks this process's output for InputMap errors.

const EVENTS := 50


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("menu_input_probe: cannot load main scene")
		quit(1)
		return
	for i in range(5):
		await process_frame
	for i in range(EVENTS):
		var key := InputEventKey.new()
		key.physical_keycode = KEY_A
		key.keycode = KEY_A
		key.pressed = i % 2 == 0
		Input.parse_input_event(key)
		await process_frame
	print("MENU_INPUT_PROBE_OK")
	quit(0)
