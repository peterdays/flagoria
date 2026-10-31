extends "res://tests/helpers/test_helpers.gd"
## UI sounds.


func _test_ui_sfx_clips() -> int:
	## Every UI event maps to a clip that exists and loads, with a volume, a
	## cooldown and a counter, on a local (non-positional) SFX player; every
	## clip under art/audio/sfx/ui/ is used.
	print("-- test_ui_sfx_clips")
	var fail := 0
	var ui = root.get_node_or_null("UiSfx")
	if ui == null:
		printerr("FAIL ui_sfx_clips: no UiSfx autoload")
		return 1
	var want := ["click", "back", "menu_open", "menu_close", "saved"]
	if ui.SOUNDS.keys() != want:
		printerr("FAIL ui_sfx_clips: events %s, want %s" % [ui.SOUNDS.keys(), want])
		fail += 1
	var used := []
	for event in ui.SOUNDS:
		var clips: Array = ui.SOUNDS[event]
		if clips.is_empty():
			printerr("FAIL ui_sfx_clips: %s has no clips" % event)
			fail += 1
		for clip in clips:
			var wav := clip as AudioStreamWAV
			if wav == null or wav.get_length() <= 0.03 or not ResourceLoader.exists(wav.resource_path):
				printerr("FAIL ui_sfx_clips: %s clip %s missing or empty" % [event, clip])
				fail += 1
				continue
			used.append(wav.resource_path.get_file())
			if not wav.resource_path.get_file().begins_with(event + "_"):
				printerr("FAIL ui_sfx_clips: %s maps to %s" % [event, wav.resource_path])
				fail += 1
		if not ui.VOLUME_DB.has(event) or not ui.COOLDOWN.has(event) or not ui.plays.has(event):
			printerr("FAIL ui_sfx_clips: %s lacks a volume, cooldown or counter" % event)
			fail += 1
			continue
		var p = ui.players().get(event)
		if not p is AudioStreamPlayer or p.bus != &"SFX" or not is_equal_approx(p.volume_db, ui.VOLUME_DB[event]):
			printerr("FAIL ui_sfx_clips: %s player %s on %s" % [event, p, p.bus if p else ""])
			fail += 1
	for file in DirAccess.get_files_at("res://art/audio/sfx/ui"):
		if file.ends_with(".wav") and file not in used:
			printerr("FAIL ui_sfx_clips: %s is not used" % file)
			fail += 1
	if ui.process_mode != Node.PROCESS_MODE_ALWAYS:
		printerr("FAIL ui_sfx_clips: UiSfx stops when the game pauses")
		fail += 1
	if FileAccess.get_file_as_string("res://Scripts/ui_sfx.gd").contains("rpc"):
		printerr("FAIL ui_sfx_clips: UI sounds must stay local (no RPCs)")
		fail += 1
	if fail == 0:
		print("PASS test_ui_sfx_clips")
	return fail


func _test_ui_sfx_presses() -> int:
	## Each press plays exactly once: click on every button in the main menu
	## and map settings panel, back on Back. The sound starts before the
	## button's own handler and outlives the button. A "ui_menu" Control
	## plays menu_open/menu_close when it shows or hides; a map save that
	## succeeds plays saved, a failed one nothing. (Cooldowns are cleared
	## between steps; they only guard against a double fire.)
	print("-- test_ui_sfx_presses")
	var fail := 0
	var ui = root.get_node("UiSfx")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame  # the map settings panel is added deferred
	var layer: Node = scene.get_node("CanvasLayer2")
	var buttons := layer.find_children("*", "BaseButton", true, false)
	var names := []
	for b in buttons:
		names.append(str(b.name))
		var first: Callable = b.pressed.get_connections()[0]["callable"] if b.pressed.get_connections().size() > 0 else Callable()
		if first.get_object() != ui:
			printerr("FAIL ui_sfx_presses: %s press sound is not connected first" % b.name)
			fail += 1
		var want := "back" if b.name == "Back" else "click"
		if ui.sound_for(b) != want:
			printerr("FAIL ui_sfx_presses: %s plays %s, want %s" % [b.name, ui.sound_for(b), want])
			fail += 1
	for n in ["MapSettingsButton", "HostButton", "JoinButton", "RandomSeed", "Reset", "Back", "Start", "NoiseType"]:
		if n not in names:
			printerr("FAIL ui_sfx_presses: no %s button found" % n)
			fail += 1
	# Real presses that stay local (Host and Join start networking).
	var menu = layer.get_node("MainMenu")
	var panel = menu.admin_panel
	var presses := [
		[menu.get_node("MarginContainer/VBoxContainer/MapSettingsButton"), "click"],
		[panel.get_node("Margin/VBox/Buttons/RandomSeed"), "click"],
		[panel.get_node("Margin/VBox/Buttons/Reset"), "click"],
		[panel.get_node("Margin/VBox/Buttons2/Back"), "back"],
	]
	for press in presses:
		ui._last_ms.clear()  # cooldowns are wall-clock; each step is a new press
		var before: Dictionary = ui.plays.duplicate()
		press[0].pressed.emit()
		await process_frame
		var got := _ui_plays_since(ui, before)
		if got != {press[1]: 1}:
			printerr("FAIL ui_sfx_presses: %s press played %s, want {%s: 1}" % [press[0].name, got, press[1]])
			fail += 1
	if not menu.visible or panel.visible:
		printerr("FAIL ui_sfx_presses: Back did not return to the main menu")
		fail += 1
	scene.queue_free()
	await process_frame

	# A handler that blocks, then frees the button's scene (like a scene
	# change): the click has already started and keeps playing.
	var fake := Node.new()
	var button := Button.new()
	fake.add_child(button)
	var seen := {}
	button.pressed.connect(func() -> void:
		seen["click"] = ui.plays["click"]
		seen["playing"] = ui.players()["click"].playing
		OS.delay_msec(100)
		fake.queue_free())
	root.add_child(fake)
	ui._last_ms.clear()  # cooldowns are wall-clock; each step is a new press
	var start: int = ui.plays["click"]
	button.pressed.emit()
	await process_frame
	await process_frame
	if seen.get("click", start) != start + 1 or ui.plays["click"] != start + 1:
		printerr("FAIL ui_sfx_presses: click %s before the handler, %s after; want %s" % [seen.get("click"), ui.plays["click"], start + 1])
		fail += 1
	if not seen.get("playing", false) or is_instance_valid(fake) or not ui.players()["click"].is_inside_tree():
		printerr("FAIL ui_sfx_presses: click not playing before the handler, or gone with the button's scene")
		fail += 1

	# A button that leaves and re-enters the tree still plays once per press.
	var holder := Node.new()
	root.add_child(holder)
	var again := Button.new()
	holder.add_child(again)
	holder.remove_child(again)
	holder.add_child(again)
	for i in 2:
		ui._last_ms.clear()  # cooldowns are wall-clock; each step is a new press
		var before: Dictionary = ui.plays.duplicate()
		again.pressed.emit()
		if _ui_plays_since(ui, before) != {"click": 1}:
			printerr("FAIL ui_sfx_presses: re-added button press %d played %s" % [i, _ui_plays_since(ui, before)])
			fail += 1

	# Menu open and close follow visibility in the tree, once per change.
	var parent := Control.new()
	holder.add_child(parent)
	var menu_panel := Control.new()
	menu_panel.add_to_group(&"ui_menu")
	var steps := [
		["add visible", func() -> void: parent.add_child(menu_panel), {}],
		["hide", func() -> void: menu_panel.hide(), {"menu_close": 1}],
		["hide again", func() -> void: menu_panel.hide(), {}],
		["show", func() -> void: menu_panel.show(), {"menu_open": 1}],
		["parent hidden", func() -> void: parent.hide(), {"menu_close": 1}],
		["parent shown", func() -> void: parent.show(), {"menu_open": 1}],
		["parent hidden again", func() -> void: parent.hide(), {"menu_close": 1}],
		["hidden under hidden parent", func() -> void: menu_panel.hide(), {}],
		["shown under hidden parent", func() -> void: menu_panel.show(), {}],
		["parent shown again", func() -> void: parent.show(), {"menu_open": 1}],
	]
	for step in steps:
		ui._last_ms.clear()
		var before: Dictionary = ui.plays.duplicate()
		step[1].call()
		if _ui_plays_since(ui, before) != step[2]:
			printerr("FAIL ui_sfx_presses: menu %s played %s, want %s" % [step[0], _ui_plays_since(ui, before), step[2]])
			fail += 1
	holder.queue_free()

	# Saved: once for a map save that succeeds, nothing for one that fails.
	var map_gen = root.get_node("MapGen")
	var kept: MapGenParams = map_gen.params
	map_gen.params = kept.duplicate_params()
	map_gen.params.ensure_seeds()
	var before_save: Dictionary = ui.plays.duplicate()
	var err: String = map_gen.save_map_inputs("test_ui_saved")
	DirAccess.remove_absolute(MapSave.path_for("test_ui_saved"))
	if err != "" or _ui_plays_since(ui, before_save) != {"saved": 1}:
		printerr("FAIL ui_sfx_presses: save (%s) played %s, want {saved: 1}" % [err, _ui_plays_since(ui, before_save)])
		fail += 1
	ui._last_ms.clear()
	map_gen.params.altitude_seed = 0
	before_save = ui.plays.duplicate()
	err = map_gen.save_map_inputs("test_ui_saved")
	if err == "" or _ui_plays_since(ui, before_save) != {}:
		printerr("FAIL ui_sfx_presses: failed save (%s) played %s" % [err, _ui_plays_since(ui, before_save)])
		fail += 1
	map_gen.params = kept
	await process_frame
	if fail == 0:
		print("PASS test_ui_sfx_presses (%d buttons)" % buttons.size())
	return fail
