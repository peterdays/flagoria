extends "res://tests/helpers/test_helpers.gd"
## The main menu letter keyboard for the join address.


func _test_main_menu_letter_keyboard() -> int:
	## The join address field uses the in-game letter keyboard, in the same
	## keycap style as the number pad, instead of the OS keyboard: its keys
	## type letters, digits, "." and ":", the first key replaces the old text,
	## OK closes it, and a physical keyboard still types there.
	print("-- test_main_menu_letter_keyboard")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	var field: LineEdit = menu.address_entry
	var kb = menu.get_node_or_null("LetterKeyboard")
	var fail := 0
	if kb == null or field.virtual_keyboard_enabled:
		printerr("FAIL letter_keyboard address field has no in-game keyboard (os keyboard=%s)" % field.virtual_keyboard_enabled)
		scene.queue_free()
		return 1
	field.text = "old.host"
	field.grab_focus()
	await process_frame
	if not kb.visible or kb.target != field:
		printerr("FAIL letter_keyboard focusing the address field did not open the keyboard")
		fail += 1
	for key in ["Digit1", "Point", "Digit2", "Colon", "Digit9", "Digit0", "Delete", "Digit1"]:
		var b: Button = kb.find_child(key, true, false)
		if b == null:
			printerr("FAIL letter_keyboard no %s key" % key)
			fail += 1
			continue
		b.pressed.emit()
	if field.text != "1.2:91":
		printerr("FAIL letter_keyboard keys gave %s want 1.2:91" % field.text)
		fail += 1
	field.text = ""
	for key in ["l", "o", "c", "a", "l", "h", "o", "s", "t"]:
		kb.find_child(key, true, false).pressed.emit()
	if field.text != "localhost":
		printerr("FAIL letter_keyboard letter keys gave %s want localhost" % field.text)
		fail += 1
	for key in ["l", "Digit5", "Delete", "OK"]:
		var want_style: StringName = {"Delete": &"KeyCapDelete", "OK": &"KeyCapOK"}.get(key, &"KeyCap")
		if kb.find_child(key, true, false).theme_type_variation != want_style:
			printerr("FAIL letter_keyboard %s key is not styled %s" % [key, want_style])
			fail += 1
	kb.find_child("OK", true, false).pressed.emit()
	if kb.visible:
		printerr("FAIL letter_keyboard OK did not close the keyboard")
		fail += 1
	field.caret_column = field.text.length()
	for ch in ":7":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		root.push_input(ev)
	await process_frame
	if field.text != "localhost:7":
		printerr("FAIL letter_keyboard physical keys gave %s want localhost:7" % field.text)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_main_menu_letter_keyboard")
	return fail


func _test_letter_keyboard_minus_key() -> int:
	## The letter keyboard has a "-" key, so a host name with a hyphen can be
	## typed by touch.
	print("-- test_letter_keyboard_minus_key")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	var field: LineEdit = menu.address_entry
	var kb = menu.get_node("LetterKeyboard")
	var fail := 0
	field.text = ""
	field.grab_focus()
	await process_frame
	for ch in "my-host.local":
		var key: String = {"-": "Minus", ".": "Point"}.get(ch, ch)
		var b: Button = kb.find_child(key, true, false)
		if b == null:
			printerr("FAIL letter_keyboard_minus_key no %s key" % key)
			fail += 1
			continue
		b.pressed.emit()
	if field.text != "my-host.local":
		printerr("FAIL letter_keyboard_minus_key keys gave %s want my-host.local" % field.text)
		fail += 1
	kb.close()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_letter_keyboard_minus_key")
	return fail


func _test_letter_keyboard_first_minus_replaces() -> int:
	## With the address selected, the first "-" replaces the text with "-"
	## (letter Minus types; it does not negate) (#356). Time cost: ~0.15 s in
	## verify (~1.5 s alone with --only=, Godot boot dominates).
	print("-- test_letter_keyboard_first_minus_replaces")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	var field: LineEdit = menu.address_entry
	var kb = menu.get_node("LetterKeyboard")
	var fail := 0
	field.text = "old.host"
	field.grab_focus()
	await process_frame
	await process_frame
	if field.get_selected_text() != "old.host":
		printerr("FAIL letter_keyboard_first_minus_replaces: address not selected on open (%s)"
				% field.get_selected_text())
		fail += 1
	kb.find_child("Minus", true, false).pressed.emit()
	if field.text != "-":
		printerr("FAIL letter_keyboard_first_minus_replaces: first Minus gave %s want -" % field.text)
		fail += 1
	kb.close()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_letter_keyboard_first_minus_replaces")
	return fail


func _test_letter_keyboard_third_row_fits() -> int:
	## Third letter row is 11 keys (a–l, Colon, Minus) and the keyboard panel
	## still fits the 480x270 viewport (#356). Time cost: ~0.15 s in verify
	## (~1.5 s alone with --only=).
	print("-- test_letter_keyboard_third_row_fits")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	var field: LineEdit = menu.address_entry
	var kb: NumberPad = menu.get_node("LetterKeyboard")
	var fail := 0
	field.grab_focus()
	await process_frame
	await process_frame
	var rows: Array = NumberPad.LETTER_ROWS
	if rows.size() != 4:
		printerr("FAIL letter_keyboard_third_row_fits: %s rows, want 4" % rows.size())
		fail += 1
	else:
		var counts := [rows[0].size(), rows[1].size(), rows[2].size(), rows[3].size()]
		if counts != [10, 10, 11, 10]:
			printerr("FAIL letter_keyboard_third_row_fits: row sizes %s want [10, 10, 11, 10]" % [counts])
			fail += 1
		if rows[2][-1] != "Minus" or rows[2][-2] != "Colon":
			printerr("FAIL letter_keyboard_third_row_fits: third row ends %s, want Colon then Minus" % [rows[2].slice(-2)])
			fail += 1
	var panel: Control = kb.get_node("Panel")
	var pad_w: float = panel.get_combined_minimum_size().x
	var screen_w: float = kb.get_viewport_rect().size.x
	if pad_w > screen_w + 0.5:
		printerr("FAIL letter_keyboard_third_row_fits: panel width %s > viewport %s" % [pad_w, screen_w])
		fail += 1
	else:
		print("letter_keyboard_third_row_fits: panel_w=%s viewport_w=%s" % [pad_w, screen_w])
	# Every third-row key is present and has a positive size (tappable).
	for key in rows[2]:
		var node_name: String = ("Digit" + key) if key.is_valid_int() else key
		var b: Button = kb.find_child(node_name, true, false)
		if b == null or b.size.x < 1.0 or b.size.y < 1.0:
			printerr("FAIL letter_keyboard_third_row_fits: key %s missing or untappable size %s"
					% [key, b.size if b else Vector2.ZERO])
			fail += 1
	kb.close()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_letter_keyboard_third_row_fits")
	return fail

