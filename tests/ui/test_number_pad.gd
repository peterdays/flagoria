extends "res://tests/helpers/test_helpers.gd"
## The Map Settings number pad: first key replaces, and keycap style.


func _test_number_pad_first_key_replaces() -> int:
	## Opening the pad selects the field's text, so the first key replaces the
	## old value instead of adding to it; later keys add as usual. A field left
	## holding only "-" or "." when the pad closes gets its old value back.
	print("-- test_number_pad_first_key_replaces")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var pad = panel.get_node("NumberPad")
	var fail := 0
	var seed_field: LineEdit = panel.find_child("ItemsSeed")
	for how in ["focus", "tap"]:
		seed_field.release_focus()
		pad.close()
		await process_frame
		seed_field.text = "4295"
		if how == "focus":
			seed_field.grab_focus()
		else:
			_tap_sequence(seed_field.get_global_rect().get_center(), ["mouse_down", "touch_down", "mouse_up", "touch_up"])
		await process_frame
		await process_frame
		if not pad.visible or seed_field.get_selected_text() != "4295":
			printerr("FAIL number_pad_first_key %s: pad open=%s selected=%s" % [how, pad.visible, seed_field.get_selected_text()])
			fail += 1
		for key in ["Digit7", "Digit1"]:
			pad.find_child(key, true, false).pressed.emit()
		if seed_field.text != "71":
			printerr("FAIL number_pad_first_key %s: typed 7 1 over 4295 gave %s want 71" % [how, seed_field.text])
			fail += 1
	pad.close()
	seed_field.release_focus()
	var spin: SpinBox = panel._spin_boxes["ground_chance_a"]
	var field := spin.get_line_edit()
	for lone in ["-", "."]:
		spin.value = 0.25
		await process_frame  # the SpinBox shows a new value a frame later
		field.grab_focus()
		await process_frame
		var old_text := field.text
		field.text = lone
		pad.find_child("OK", true, false).pressed.emit()
		if field.text != old_text or not is_equal_approx(spin.value, 0.25):
			printerr("FAIL number_pad_first_key lone %s gave text=%s value=%s want %s" % [lone, field.text, spin.value, old_text])
			fail += 1
		field.release_focus()
		await process_frame
	panel.queue_free()
	if fail == 0:
		print("PASS test_number_pad_first_key_replaces")
	return fail


func _test_number_pad_keycap_style() -> int:
	## The pad has its own keyboard look from the menu theme: keycaps for the
	## digits, a red Delete and a gold OK key, and a framed panel.
	print("-- test_number_pad_keycap_style")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var pad = panel.get_node("NumberPad")
	var fail := 0
	var theme: Theme = load("res://art/ui/main_menu_theme.tres")
	for type in ["KeyCap", "KeyCapDelete", "KeyCapOK"]:
		if not theme.get_type_variation_list(&"Button").has(StringName(type)):
			printerr("FAIL number_pad_keycap_style theme has no %s button style" % type)
			fail += 1
	panel.find_child("ItemsSeed").grab_focus()
	await process_frame
	var want := {"Digit5": &"KeyCap", "Delete": &"KeyCapDelete", "OK": &"KeyCapOK"}
	for key in want:
		var b: Button = pad.find_child(key, true, false)
		if b == null or b.theme_type_variation != want[key]:
			printerr("FAIL number_pad_keycap_style %s style %s want %s" % [key, b.theme_type_variation if b else "missing", want[key]])
			fail += 1
	if pad.get_node("Panel").theme_type_variation != &"KeyboardPanel":
		printerr("FAIL number_pad_keycap_style panel is not a KeyboardPanel")
		fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_number_pad_keycap_style")
	return fail
