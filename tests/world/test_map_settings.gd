extends "res://tests/helpers/test_helpers.gd"
## The map settings panel (Scripts/MapAdminPanel.gd) and its number pad.


func _test_map_settings_water_reopen() -> int:
	## Map Settings must show the in-use water value on reopen, even when a
	## SpinBox LineEdit still holds a dirty string for the same numeric value.
	print("-- test_map_settings_water_reopen")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	var spin: SpinBox = panel._spin_boxes["water_max_alt"]
	var in_use := 0.45
	spin.value = in_use
	spin.get_line_edit().text = "0.2"
	var params = _pre_biome_defaults()
	params.water_max_alt = in_use
	panel.load_from_params(params)
	var shown := float(spin.get_line_edit().text)
	panel.queue_free()
	if abs(shown - in_use) > 0.001:
		printerr(
			"FAIL map_settings_water_reopen shown=%s want in-use=%s"
			% [shown, in_use]
		)
		return 1
	print("PASS test_map_settings_water_reopen shown=%s" % shown)
	return 0


func _test_map_settings_covers_params() -> int:
	## Every exported MapGenParams property must reach clients (to_dict) and
	## have a Map Settings control.
	print("-- test_map_settings_covers_params")
	var hand_wired := ["altitude_seed", "moisture_seed", "temperature_seed", "items_seed", "biome_seed", "noise_type"]
	var params = _pre_biome_defaults()
	var keys: Dictionary = params.to_dict()
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	var fail := 0
	var exported := 0
	for prop in params.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		exported += 1
		var key: String = prop["name"]
		if not keys.has(key):
			printerr("FAIL map_settings_covers_params %s missing from to_dict()" % key)
			fail += 1
		if not panel._spin_boxes.has(key) and not hand_wired.has(key):
			printerr("FAIL map_settings_covers_params %s has no panel control" % key)
			fail += 1

	params.chunk_refresh_frames = 7
	panel.load_from_params(params)
	panel._spin_boxes["chunk_refresh_frames"].value = 9
	panel.apply_to_params(params)
	if params.chunk_refresh_frames != 9:
		printerr(
			"FAIL map_settings_covers_params panel round-trip chunk_refresh_frames=%s want 9"
			% params.chunk_refresh_frames
		)
		fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_covers_params (%s properties)" % exported)
	return fail


func _test_map_settings_rows_from_hints() -> int:
	## Map Settings rows come from MapGenParams @export_range hints. Pins the
	## label, range and order of the rows that existed before that change;
	## rows for new parameters are allowed.
	print("-- test_map_settings_rows_from_hints")
	var expected := {
		"altitude_frequency": ["Altitude frequency", 0.001, 1.0, 0.001],
		"moisture_frequency": ["Moisture frequency", 0.001, 1.0, 0.001],
		"temperature_frequency": ["Temperature frequency", 0.001, 1.0, 0.001],
		"items_frequency": ["Items frequency", 0.01, 4.0, 0.01],
		"fractal_octaves": ["Fractal octaves", 1, 10, 1],
		"fractal_lacunarity": ["Fractal lacunarity", 0.1, 4.0, 0.1],
		"fractal_gain": ["Fractal gain", 0.0, 2.0, 0.05],
		"chunk_width": ["Chunk width", 8, 128, 1],
		"chunk_height": ["Chunk height", 8, 128, 1],
		"chunk_refresh_frames": ["Chunk refresh frames", 1, 120, 1],
		"water_max_alt": ["Water max altitude", -1.0, 1.0, 0.01],
		"sand_max_alt": ["Sand max altitude", -1.0, 1.0, 0.01],
		"swamp_special_alt": ["Swamp special altitude", -1.0, 1.0, 0.01],
		"ground_chance_a": ["Ground chance A", -1.0, 1.0, 0.05],
		"ground_chance_b": ["Ground chance B", -1.0, 1.0, 0.05],
		"ground_chance_c": ["Ground chance C", -1.0, 1.0, 0.05],
		"bush_min_alt": ["Bush min altitude", -1.0, 1.0, 0.01],
		"bush_max_alt": ["Bush max altitude", -1.0, 1.0, 0.01],
		"bush_min_chance": ["Bush min chance", -1.0, 1.0, 0.05],
		"tree_min_alt": ["Tree min altitude", -1.0, 1.0, 0.01],
		"tree_min_chance": ["Tree min chance", -1.0, 1.0, 0.05],
	}
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	var fail := 0
	var pinned_order: Array = panel._spin_boxes.keys().filter(func(k): return expected.has(k))
	if pinned_order != expected.keys():
		printerr(
			"FAIL map_settings_rows_from_hints row order=%s want %s"
			% [pinned_order, expected.keys()]
		)
		fail += 1
	for key in expected.keys():
		if not panel._spin_boxes.has(key):
			continue
		var want: Array = expected[key]
		var spin: SpinBox = panel._spin_boxes[key]
		var label: String = spin.get_parent().get_child(0).text
		var got := [label, spin.min_value, spin.max_value, spin.step]
		if label != want[0] or not is_equal_approx(spin.min_value, want[1]) \
				or not is_equal_approx(spin.max_value, want[2]) or not is_equal_approx(spin.step, want[3]):
			printerr("FAIL map_settings_rows_from_hints %s got %s want %s" % [key, got, want])
			fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_rows_from_hints (%s rows)" % expected.size())
	return fail


func _test_map_settings_number_pad() -> int:
	## Seed fields use the in-game number pad instead of the OS keyboard:
	## the pad's keys edit the field, OK or a tap outside closes it, and typed
	## non-digits are dropped.
	print("-- test_map_settings_number_pad")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var fail := 0
	var fields := ["AltitudeSeed", "MoistureSeed", "TemperatureSeed", "ItemsSeed", "BiomeSeed"]
	for field_name in fields:
		var f: LineEdit = panel.find_child(field_name)
		if f.virtual_keyboard_enabled:
			printerr("FAIL number_pad %s still opens the OS keyboard" % field_name)
			fail += 1
	var pad = panel.get_node_or_null("NumberPad")
	if pad == null:
		printerr("FAIL number_pad Map Settings has no NumberPad")
		panel.queue_free()
		return fail + 1
	var field: LineEdit = panel.find_child("ItemsSeed")
	field.text = "0"
	field.grab_focus()
	await process_frame
	if not pad.visible or pad.target != field:
		printerr("FAIL number_pad focusing ItemsSeed did not open the pad for it")
		fail += 1
	for key in ["Digit4", "Digit2", "Digit7", "Delete", "Digit9"]:
		pad.find_child(key, true, false).pressed.emit()
	if field.text != "429":
		printerr("FAIL number_pad keys gave %s want 429" % field.text)
		fail += 1
	field.caret_column = field.text.length()
	for ch in "a-5.":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		root.push_input(ev)
	await process_frame  # LineEdit emits text_changed deferred
	if field.text != "4295":
		printerr("FAIL number_pad typed a-5. gave %s want 4295" % field.text)
		fail += 1
	pad.find_child("OK", true, false).pressed.emit()
	if pad.visible:
		printerr("FAIL number_pad OK did not close the pad")
		fail += 1
	pad.open(field)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = Vector2(root.get_visible_rect().size) - Vector2(2, 2)
		root.push_input(click, true)
	if pad.visible:
		printerr("FAIL number_pad a tap outside did not close the pad")
		fail += 1
	var params = MapGenParams.make_defaults()
	panel.apply_to_params(params)
	if params.items_seed != 4295:
		printerr("FAIL number_pad items_seed=%s want 4295" % params.items_seed)
		fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_number_pad (%s fields)" % fields.size())
	return fail


func _test_map_settings_number_pad_touch_tap() -> int:
	## Tapping a seed field on a phone opens the pad and it stays open. Android
	## sends each tap as an emulated mouse button first and then the screen
	## touch (emulate_mouse_from_touch), so the touch lands on the pad that the
	## mouse press just opened. Desktop with emulate_touch_from_mouse sends the
	## touch first. Both orders, and a plain mouse click, must keep the pad
	## open with the field as its target, and a later tap outside must close it.
	print("-- test_map_settings_number_pad_touch_tap")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var pad = panel.get_node("NumberPad")
	var fail := 0
	for field_name in ["AltitudeSeed", "MoistureSeed", "TemperatureSeed", "ItemsSeed", "BiomeSeed"]:
		var f: LineEdit = panel.find_child(field_name)
		var row: HBoxContainer = f.get_parent()
		if f.alignment != HORIZONTAL_ALIGNMENT_CENTER or f.size_flags_horizontal & Control.SIZE_EXPAND \
				or row.alignment != BoxContainer.ALIGNMENT_CENTER:
			printerr("FAIL number_pad_touch_tap %s is not a centered fixed-width field" % field_name)
			fail += 1
	var orders := {
		"android": ["mouse_down", "touch_down", "mouse_up", "touch_up"],
		"desktop": ["touch_down", "mouse_down", "touch_up", "mouse_up"],
		"mouse": ["mouse_down", "mouse_up"],
		"engine": ["input_touch_down", "input_touch_up"],
	}
	for order_name in orders:
		for field_name in ["AltitudeSeed", "BiomeSeed"]:
			var field: LineEdit = panel.find_child(field_name)
			field.release_focus()
			pad.close()
			await process_frame
			field.text = "0"
			_tap_sequence(field.get_global_rect().get_center(), orders[order_name])
			await process_frame
			if not pad.visible or pad.target != field or not field.has_focus():
				printerr(
					"FAIL number_pad_touch_tap %s tap on %s: pad open=%s target=%s focus=%s"
					% [order_name, field_name, pad.visible, pad.target.name if pad.target else "none", field.has_focus()]
				)
				fail += 1
				continue
			for key in ["Digit7", "Digit3"]:
				pad.find_child(key, true, false).pressed.emit()
			if field.text != "73":
				printerr("FAIL number_pad_touch_tap %s %s typed %s want 73" % [order_name, field_name, field.text])
				fail += 1
			_tap_sequence(Vector2(root.get_visible_rect().size) - Vector2(2, 2), orders[order_name])
			await process_frame
			if pad.visible:
				printerr("FAIL number_pad_touch_tap %s tap outside did not close the pad" % order_name)
				fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_number_pad_touch_tap (%s orders)" % orders.size())
	return fail


func _test_map_settings_number_pad_spin_boxes() -> int:
	## Every other number field in Map Settings (the SpinBox rows) uses the
	## in-game pad too: no OS keyboard, focus or a tap opens the pad, "-" and
	## "." keys show only where the field takes them, and closing the pad
	## commits the text through the SpinBox's own min, max and step.
	print("-- test_map_settings_number_pad_spin_boxes")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var pad = panel.get_node("NumberPad")
	var fail := 0
	var spins: Dictionary = panel._spin_boxes
	if spins.size() < 10:
		printerr("FAIL number_pad_spin_boxes only %s SpinBox rows" % spins.size())
		fail += 1
	for key in spins:
		var spin: SpinBox = spins[key]
		var field := spin.get_line_edit()
		if spin.rounded and not field.text.is_valid_int():
			printerr("FAIL number_pad_spin_boxes int row %s shows %s" % [key, field.text])
			fail += 1
		if field.virtual_keyboard_enabled:
			printerr("FAIL number_pad_spin_boxes %s still opens the OS keyboard" % key)
			fail += 1
		field.grab_focus()
		await process_frame
		if not pad.visible or pad.target != field:
			printerr("FAIL number_pad_spin_boxes focusing %s did not open the pad for it" % key)
			fail += 1
		var want_minus := spin.min_value < 0.0
		var want_point := not spin.rounded and spin.step < 1.0
		if pad.find_child("Minus", true, false).visible != want_minus \
				or pad.find_child("Point", true, false).visible != want_point:
			printerr("FAIL number_pad_spin_boxes %s minus/point keys shown %s/%s want %s/%s" % [
				key, pad.find_child("Minus", true, false).visible,
				pad.find_child("Point", true, false).visible, want_minus, want_point])
			fail += 1
		pad.close()
		field.release_focus()
	var cases := [
		# [key, pad keys, committed value]
		["archipelago_island_count", ["Digit3", "Digit0", "Digit0"], 256.0],  # clamped to max
		["archipelago_spacing", ["Digit9", "Digit6"], 96.0],
		["ground_chance_a", ["Minus", "Point", "Digit5"], -0.5],
		["water_max_alt", ["Digit1", "Point", "Digit7"], 1.0],  # clamped to max
		["fractal_gain", ["Digit0", "Point", "Digit7", "Digit3"], 0.75],  # snapped to step
	]
	for c in cases:
		var spin: SpinBox = spins[c[0]]
		var field := spin.get_line_edit()
		field.grab_focus()
		await process_frame
		field.text = ""
		for k in c[1]:
			pad.find_child(k, true, false).pressed.emit()
		pad.find_child("OK", true, false).pressed.emit()
		if pad.visible or not is_equal_approx(spin.value, c[2]):
			printerr("FAIL number_pad_spin_boxes %s keys %s gave %s (pad open=%s) want %s" % [
				c[0], c[1], spin.value, pad.visible, c[2]])
			fail += 1
		field.release_focus()
	# A physical keyboard still types, keeping one leading "-" and one ".".
	var bush: LineEdit = spins["bush_min_alt"].get_line_edit()
	bush.grab_focus()
	await process_frame
	bush.text = ""
	for ch in "a-0.2-.5":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		root.push_input(ev)
	await process_frame  # LineEdit emits text_changed deferred
	if bush.text != "-0.25":
		printerr("FAIL number_pad_spin_boxes typed a-0.2-.5 gave %s want -0.25" % bush.text)
		fail += 1
	pad.close()
	bush.release_focus()
	# An int field takes digits only.
	var count: LineEdit = spins["archipelago_island_count"].get_line_edit()
	count.grab_focus()
	await process_frame
	count.text = ""
	for ch in "-1.2":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		root.push_input(ev)
	await process_frame
	if count.text != "12":
		printerr("FAIL number_pad_spin_boxes int field typed -1.2 gave %s want 12" % count.text)
		fail += 1
	pad.close()
	count.release_focus()
	# A touch tap on a SpinBox field opens the pad and keeps it open.
	var tap_spin: SpinBox = spins["archipelago_spacing"]
	panel.scroll.ensure_control_visible(tap_spin)
	await process_frame
	await process_frame
	_tap_sequence(tap_spin.get_line_edit().get_global_rect().get_center(), ["mouse_down", "touch_down", "mouse_up", "touch_up"])
	await process_frame
	if not pad.visible or pad.target != tap_spin.get_line_edit():
		printerr("FAIL number_pad_spin_boxes android tap on archipelago_spacing did not keep the pad open")
		fail += 1
	pad.close()
	var params = MapGenParams.make_defaults()
	panel.apply_to_params(params)
	if params.archipelago_island_count != 12 or not is_equal_approx(params.ground_chance_a, -0.5) \
			or params.archipelago_spacing != 96:
		printerr("FAIL number_pad_spin_boxes params count=%s ground_chance_a=%s spacing=%s" % [
			params.archipelago_island_count, params.ground_chance_a, params.archipelago_spacing])
		fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_number_pad_spin_boxes (%s fields)" % spins.size())
	return fail


func _test_map_settings_uses_menu_theme() -> int:
	## Map Settings uses the menu theme at its root, so its text uses the game
	## font and its bottom buttons look like the main menu's.
	print("-- test_map_settings_uses_menu_theme")
	var theme: Theme = load("res://art/ui/main_menu_theme.tres")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var fail := 0
	if panel.theme != theme:
		printerr("FAIL map_settings_uses_menu_theme panel root theme is %s" % panel.theme)
		fail += 1
	for button_name in ["RandomSeed", "Reset", "Back", "Start"]:
		var b: Button = panel.find_child(button_name)
		if b.get_theme_stylebox("normal") != theme.get_stylebox("normal", "Button") \
				or b.get_theme_font("font") != theme.default_font \
				or b.get_theme_font_size("font_size") != theme.get_font_size("font_size", "Button"):
			printerr("FAIL map_settings_uses_menu_theme %s does not use the menu button style" % button_name)
			fail += 1
	for node_name in ["Title", "AltitudeSeed", "NoiseType"]:
		var c: Control = panel.find_child(node_name)
		if c.get_theme_font("font") != theme.default_font:
			printerr("FAIL map_settings_uses_menu_theme %s does not use the game font" % node_name)
			fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_uses_menu_theme")
	return fail


func _test_map_settings_rows_centered() -> int:
	## Below the seeds, the noise type and numeric rows are centered rows of a
	## fixed width like the seed rows, in the game font, and the bottom buttons
	## are a centered block instead of spanning the screen.
	print("-- test_map_settings_rows_centered")
	var theme: Theme = load("res://art/ui/main_menu_theme.tres")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	for i in 3:
		await process_frame
	var fail := 0
	var view_w: float = root.get_visible_rect().size.x
	var form: Control = panel.find_child("Form")
	var rows: Array = [panel.find_child("NoiseTypeRow")]
	for spin in panel._spin_boxes.values():
		rows.append(spin.get_parent())
	rows.append(panel.find_child("Buttons"))
	rows.append(panel.find_child("Buttons2"))
	for row in rows:
		# Extent of the row's children, which is what the player sees.
		var left := INF
		var right := -INF
		for c in row.get_children():
			left = minf(left, c.get_global_rect().position.x)
			right = maxf(right, c.get_global_rect().end.x)
			if c.get_theme_font("font") != theme.default_font:
				printerr("FAIL map_settings_rows_centered %s/%s does not use the game font" % [row.name, c.name])
				fail += 1
		var parent_rect: Rect2 = form.get_global_rect() if row.get_parent() == form else row.get_global_rect()
		var off_center := absf((left + right) / 2.0 - parent_rect.get_center().x)
		if right - left > 0.7 * view_w or off_center > 1.0:
			printerr("FAIL map_settings_rows_centered %s spans %.0f of %.0f px, %.0f px off center" % [
					row.name, right - left, view_w, off_center])
			fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_map_settings_rows_centered (%s rows)" % rows.size())
	return fail


func _test_new_param_needs_no_ui_code() -> int:
	## A field added to MapGenParams reaches to_dict() and gets a Map Settings
	## row with no other edits. A runtime subclass stands in for that edit.
	print("-- test_new_param_needs_no_ui_code")
	var script := GDScript.new()
	script.source_code = (
		"extends MapGenParams\n"
		+ "@export_range(0, 9) var dummy_count: int = 3\n"
		+ "@export_range(-2.0, 2.0, 0.25) var dummy_ratio: float = 0.5\n"
	)
	if script.reload() != OK:
		printerr("FAIL new_param_needs_no_ui_code: dummy subclass does not compile")
		return 1
	var params = script.new()
	var expected := {
		"dummy_count": ["Dummy count", 0, 9, 1, 3],
		"dummy_ratio": ["Dummy ratio", -2.0, 2.0, 0.25, 0.5],
	}
	var fail := 0
	var data: Dictionary = params.to_dict()
	for key in expected.keys():
		if not data.has(key) or data[key] != expected[key][4]:
			printerr("FAIL new_param_needs_no_ui_code to_dict() %s=%s want %s" % [key, data.get(key), expected[key][4]])
			fail += 1

	var map_gen = root.get_node("MapGen")
	var saved_params = map_gen.params
	map_gen.params = params
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	map_gen.params = saved_params
	for key in expected.keys():
		var want: Array = expected[key]
		if not panel._spin_boxes.has(key):
			printerr("FAIL new_param_needs_no_ui_code %s has no Map Settings row" % key)
			fail += 1
			continue
		var spin: SpinBox = panel._spin_boxes[key]
		var got := [spin.get_parent().get_child(0).text, spin.min_value, spin.max_value, spin.step, spin.value]
		if got[0] != want[0] or not is_equal_approx(got[1], want[1]) or not is_equal_approx(got[2], want[2]) \
				or not is_equal_approx(got[3], want[3]) or not is_equal_approx(got[4], want[4]):
			printerr("FAIL new_param_needs_no_ui_code %s row %s want %s" % [key, got, want])
			fail += 1

	if fail == 0:
		panel._spin_boxes["dummy_count"].value = 7
		panel._spin_boxes["dummy_ratio"].value = -1.25
		panel.apply_to_params(params)
		var copy = script.new()
		copy.from_dict(params.to_dict())
		if copy.dummy_count != 7 or not is_equal_approx(copy.dummy_ratio, -1.25):
			printerr(
				"FAIL new_param_needs_no_ui_code round-trip dummy_count=%s dummy_ratio=%s"
				% [copy.dummy_count, copy.dummy_ratio]
			)
			fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_new_param_needs_no_ui_code")
	return fail
