extends "res://tests/helpers/test_helpers.gd"
## Round HUD row: minimap closed, five round buttons, Run matches them (#450).


func _test_hud_round_buttons() -> int:
	## A hosted scene starts with the wood panel closed and no reopen chip.
	## Plank, tower, wall, minimap and the mode button are round, in that
	## order after Run, under the wood counter. Each build button selects
	## that tool. The minimap button opens and closes the panel. The mode
	## button still switches attack and chop, and leaving interact returns
	## to Cut. Time cost: about 0.5 s in tools/verify.sh.
	print("-- test_hud_round_buttons")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	await process_frame
	scene.add_player(scene.multiplayer.get_unique_id())
	await process_frame
	await process_frame
	var panel: MinimapPanel = scene.get_node("CanvasLayer1/MinimapPanel")
	panel.set_physics_process(false)
	panel.tick()
	panel.tick()
	var run: Button = scene.get_node("CanvasLayer1/RunButton")
	var picker: HBoxContainer = scene.get_node("CanvasLayer1/BuildPicker")
	var plank: Button = picker.get_node("PlankButton")
	var tower: Button = picker.get_node("TowerButton")
	var wall: Button = picker.get_node("WallButton")
	var map_button: Button = scene.get_node("CanvasLayer1/MinimapButton")
	var mode: Button = scene.get_node("CanvasLayer1/ModeButton")
	var interaction: Interaction = scene.get_node("World/Interaction")
	if panel.visible or scene.get_node_or_null("CanvasLayer1/MapReopen") != null:
		printerr("FAIL hud_round_buttons: panel %s or the old chip is showing" % panel.visible)
		fail += 1
	var row: Array[Button] = [run, plank, tower, wall, map_button, mode]
	var previous := -1.0
	for button in row:
		if not button.visible or not _is_round(button):
			printerr("FAIL hud_round_buttons: %s visible %s size %s" % [button.name, button.visible, button.size])
			fail += 1
		var at: float = button.get_global_rect().position.x
		if at <= previous:
			printerr("FAIL hud_round_buttons: %s at %s is not to the right of %s" % [button.name, at, previous])
			fail += 1
		previous = at
	var wood: Control = scene.get_node("CanvasLayer1/ResourceHud")
	var menu_rect: Rect2 = scene.get_node("CanvasLayer1/InGameMenu").menu_button.get_global_rect()
	var panel_rect := Rect2(panel.position, panel.size * panel.scale)
	var wood_bottom := wood.position.y + wood.size.y * minf(wood.scale.y, 2.0)
	if plank.get_global_rect().position.y + 0.5 < wood_bottom:
		printerr("FAIL hud_round_buttons: row %s is not under the wood bottom %s"
				% [plank.get_global_rect(), wood_bottom])
		fail += 1
	for button in row:
		var rect := button.get_global_rect()
		if rect.intersects(menu_rect) or rect.intersects(panel_rect):
			printerr("FAIL hud_round_buttons: %s %s hits menu %s or panel %s"
					% [button.name, rect, menu_rect, panel_rect])
			fail += 1
	if run.text != "Run" or absf(run.get_global_rect().position.y - mode.get_global_rect().position.y) > 0.5:
		printerr("FAIL hud_round_buttons: Run '%s' is not in line with the mode button" % run.text)
		fail += 1
	if interaction.build.tool != BuildPlacement.Tool.CUT:
		printerr("FAIL hud_round_buttons: tool starts at %s" % interaction.build.tool)
		fail += 1
	plank.pressed.emit()
	if interaction.build.tool != BuildPlacement.Tool.PLANK or not plank.button_pressed:
		printerr("FAIL hud_round_buttons: plank did not select")
		fail += 1
	tower.pressed.emit()
	if interaction.build.tool != BuildPlacement.Tool.TOWER or plank.button_pressed:
		printerr("FAIL hud_round_buttons: tower did not select")
		fail += 1
	wall.pressed.emit()
	if interaction.build.tool != BuildPlacement.Tool.WALL:
		printerr("FAIL hud_round_buttons: wall did not select")
		fail += 1
	map_button.pressed.emit()
	if not panel.visible:
		printerr("FAIL hud_round_buttons: minimap button left the panel closed")
		fail += 1
	for button in row:
		if button.get_global_rect().intersects(Rect2(panel.position, panel.size * panel.scale)):
			printerr("FAIL hud_round_buttons: open panel covers %s" % button.name)
			fail += 1
	map_button.pressed.emit()
	if panel.visible:
		printerr("FAIL hud_round_buttons: second press left the panel open")
		fail += 1
	var before := interaction.mode
	mode.pressed.emit()
	if interaction.mode == before or interaction.mode != Interaction.Mode.INTERACT:
		printerr("FAIL hud_round_buttons: mode did not switch to interact (%s)" % interaction.mode)
		fail += 1
	if interaction.build.tool != BuildPlacement.Tool.WALL:
		printerr("FAIL hud_round_buttons: entering interact cleared the wall tool")
		fail += 1
	mode.pressed.emit()
	if interaction.mode != Interaction.Mode.COMBAT or interaction.build.tool != BuildPlacement.Tool.CUT:
		printerr("FAIL hud_round_buttons: leaving interact mode %s tool %s"
				% [interaction.mode, interaction.build.tool])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_hud_round_buttons")
	return fail


func _is_round(button: Button) -> bool:
	var box := button.get_theme_stylebox("normal") as StyleBoxFlat
	if box == null:
		return false
	var side := button.size.x
	return absf(button.size.x - button.size.y) <= 1.0 and side >= 16.0 and side <= 28.0 \
			and box.corner_radius_top_left >= int(side * 0.4)
