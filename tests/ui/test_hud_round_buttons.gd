extends "res://tests/helpers/test_helpers.gd"
## Top-right HUD arc: Buildings, Map and Mode, with Run beside attack (#480).


func _test_hud_round_buttons() -> int:
	## A hosted scene starts with the wood panel closed and the build list
	## collapsed. Buildings, Map and Mode are a top-right arc of round buttons.
	## Buildings opens a column; a pick selects that tool and collapses it.
	## Map toggles the panel. Mode swaps attack and interact icons. Run sits
	## beside the attack button and is smaller. The same arc holds at
	## 1280x720 and 2400x1080. Time cost: about 0.8 s in tools/verify.sh.
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
	var buildings: Button = scene.get_node("CanvasLayer1/BuildingsButton")
	var picker: Control = scene.get_node("CanvasLayer1/BuildPicker")
	var plank: Button = picker.get_node("PlankButton")
	var tower: Button = picker.get_node("TowerButton")
	var wall: Button = picker.get_node("WallButton")
	var map_button: Button = scene.get_node("CanvasLayer1/MinimapButton")
	var mode: Button = scene.get_node("CanvasLayer1/ModeButton")
	var interaction: Interaction = scene.get_node("World/Interaction")
	if panel.visible or scene.get_node_or_null("CanvasLayer1/MapReopen") != null:
		printerr("FAIL hud_round_buttons: panel %s or the old chip is showing" % panel.visible)
		fail += 1
	if interaction.build.tool != BuildPlacement.Tool.CUT or plank.visible or tower.visible or wall.visible:
		printerr("FAIL hud_round_buttons: list starts open, tool %s" % interaction.build.tool)
		fail += 1
	fail += _check_cluster(scene, "start")
	buildings.set_pressed(true)
	await process_frame
	if not plank.visible or not tower.visible or not wall.visible:
		printerr("FAIL hud_round_buttons: Buildings did not open the column")
		fail += 1
	else:
		fail += _check_column(buildings, [plank, tower, wall])
	buildings.set_pressed(false)
	await process_frame
	if plank.visible or tower.visible or wall.visible:
		printerr("FAIL hud_round_buttons: second Buildings tap left the column open")
		fail += 1
	buildings.set_pressed(true)
	await process_frame
	plank.pressed.emit()
	await process_frame
	if interaction.build.tool != BuildPlacement.Tool.PLANK or plank.visible \
			or not plank.button_pressed or not _is_selected(plank) \
			or tower.button_pressed or wall.button_pressed:
		printerr("FAIL hud_round_buttons: plank select tool %s open %s" % [interaction.build.tool, plank.visible])
		fail += 1
	buildings.set_pressed(true)
	await process_frame
	if not plank.visible or not _is_selected(plank) or not _is_neutral(tower):
		printerr("FAIL hud_round_buttons: reopened list lost the plank ring")
		fail += 1
	buildings.set_pressed(false)
	await process_frame
	map_button.pressed.emit()
	if not panel.visible or not map_button.button_pressed or not _is_selected(map_button):
		printerr("FAIL hud_round_buttons: minimap button left the panel closed")
		fail += 1
	if mode.get_global_rect().intersects(Rect2(panel.position, panel.size * panel.scale)):
		printerr("FAIL hud_round_buttons: open panel covers Mode")
		fail += 1
	map_button.pressed.emit()
	if panel.visible:
		printerr("FAIL hud_round_buttons: second press left the panel open")
		fail += 1
	var before := interaction.mode
	mode.pressed.emit()
	if interaction.mode == before or interaction.mode != Interaction.Mode.INTERACT \
			or not str(mode.icon.resource_path).ends_with("icon_mode_interact.png"):
		printerr("FAIL hud_round_buttons: mode did not switch to interact (%s)" % interaction.mode)
		fail += 1
	if interaction.build.tool != BuildPlacement.Tool.PLANK:
		printerr("FAIL hud_round_buttons: entering interact cleared the plank tool")
		fail += 1
	mode.pressed.emit()
	if interaction.mode != Interaction.Mode.COMBAT or interaction.build.tool != BuildPlacement.Tool.CUT \
			or not str(mode.icon.resource_path).ends_with("icon_mode_attack.png"):
		printerr("FAIL hud_round_buttons: leaving interact mode %s tool %s"
				% [interaction.mode, interaction.build.tool])
		fail += 1
	var win: Window = scene.get_window()
	var saved_size: Vector2i = win.size
	var saved_aspect: Window.ContentScaleAspect = win.content_scale_aspect
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for wanted in [Vector2i(1280, 720), Vector2i(2400, 1080)]:
		win.size = wanted
		await process_frame
		await process_frame
		var visible: Vector2 = scene.get_viewport().get_visible_rect().size
		print("hud round: window %s visible %s" % [wanted, visible])
		fail += _check_cluster(scene, "%s" % wanted)
	win.size = saved_size
	win.content_scale_aspect = saved_aspect
	await process_frame
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_hud_round_buttons")
	return fail


func _check_cluster(scene: Node, label: String) -> int:
	var fail := 0
	var view: Vector2 = scene.get_viewport().get_visible_rect().size
	var buildings: Button = scene.get_node("CanvasLayer1/BuildingsButton")
	var map_button: Button = scene.get_node("CanvasLayer1/MinimapButton")
	var mode: Button = scene.get_node("CanvasLayer1/ModeButton")
	var run: Button = scene.get_node("CanvasLayer1/RunButton")
	var wood: Control = scene.get_node("CanvasLayer1/ResourceHud")
	var menu_rect: Rect2 = scene.get_node("CanvasLayer1/InGameMenu/MenuButton").get_global_rect()
	var wood_rect := Rect2(wood.global_position, Vector2(
			wood.size.x * minf(wood.scale.x, 2.0), wood.size.y * minf(wood.scale.y, 2.0)))
	var mains: Array[Button] = [buildings, map_button, mode]
	var icons := ["icon_buildings.png", "icon_map.png", "icon_mode_attack.png"]
	if interaction_mode_is_interact(scene):
		icons[2] = "icon_mode_interact.png"
	var seen: Array[Rect2] = []
	for i in mains.size():
		var button: Button = mains[i]
		var rect := button.get_global_rect()
		if not button.visible or not _is_round(button) or not _icon_ok(button, icons[i]):
			printerr("FAIL hud_round_buttons %s: %s visible %s size %s icon %s"
					% [label, button.name, button.visible, button.size, button.icon])
			fail += 1
		if rect.intersects(menu_rect) or rect.intersects(wood_rect):
			printerr("FAIL hud_round_buttons %s: %s %s hits menu %s or wood %s"
					% [label, button.name, rect, menu_rect, wood_rect])
			fail += 1
		for other in seen:
			if rect.intersects(other):
				printerr("FAIL hud_round_buttons %s: %s overlaps %s" % [label, rect, other])
				fail += 1
		seen.append(rect)
	var mode_c := mode.get_global_rect().get_center()
	var map_c := map_button.get_global_rect().get_center()
	var build_c := buildings.get_global_rect().get_center()
	var v1 := map_c - mode_c
	var v2 := build_c - map_c
	var bend := absf(v1.x * v2.y - v1.y * v2.x)
	if mode_c.x < view.x - 80.0 or mode_c.y > 40.0 or map_c.x >= mode_c.x \
			or build_c.y <= map_c.y or build_c.x > map_c.x or bend < 40.0:
		printerr("FAIL hud_round_buttons %s: arc mode %s map %s buildings %s bend %s view %s"
				% [label, mode_c, map_c, build_c, bend, view])
		fail += 1
	var attack: TouchScreenButton = scene.get_node("CanvasLayer1/TouchScreenButton")
	var attack_rect := Rect2(attack.position, attack.texture_normal.get_size() * attack.scale)
	var run_rect := run.get_global_rect()
	if run.text != "Run" and run.text != "RUN":
		printerr("FAIL hud_round_buttons %s: Run label '%s'" % [label, run.text])
		fail += 1
	if run_rect.intersects(attack_rect) or _gap(run_rect, attack_rect) > 3.0 \
			or run_rect.size.x >= attack_rect.size.x:
		printerr("FAIL hud_round_buttons %s: Run %s is not a smaller neighbour of %s"
				% [label, run_rect, attack_rect])
		fail += 1
	return fail


func interaction_mode_is_interact(scene: Node) -> bool:
	var interaction: Interaction = scene.get_node("World/Interaction")
	return interaction.mode == Interaction.Mode.INTERACT


func _check_column(buildings: Button, buttons: Array[Button]) -> int:
	var fail := 0
	var previous := buildings.get_global_rect().end.y - 0.5
	var left := buildings.get_global_rect().position.x
	for button in buttons:
		var rect := button.get_global_rect()
		if not _is_round(button) or rect.position.y < previous \
				or absf(rect.position.x - left) > 1.0:
			printerr("FAIL hud_round_buttons: %s column %s under %s"
					% [button.name, rect, buildings.get_global_rect()])
			fail += 1
		for other in buttons:
			if other != button and rect.intersects(other.get_global_rect()):
				printerr("FAIL hud_round_buttons: column %s overlaps %s" % [button.name, other.name])
				fail += 1
		previous = rect.end.y + 1.0
	return fail


func _icon_ok(button: Button, file_name: String) -> bool:
	var tex := button.icon
	return tex != null and tex.get_width() == 32 and tex.get_height() == 32 \
			and str(tex.resource_path).ends_with(file_name) \
			and button.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST


func _gap(a: Rect2, b: Rect2) -> float:
	var dx := 0.0
	if a.end.x < b.position.x:
		dx = b.position.x - a.end.x
	elif b.end.x < a.position.x:
		dx = a.position.x - b.end.x
	var dy := 0.0
	if a.end.y < b.position.y:
		dy = b.position.y - a.end.y
	elif b.end.y < a.position.y:
		dy = a.position.y - b.end.y
	return maxf(dx, dy)


func _is_round(button: Button) -> bool:
	var box := button.get_theme_stylebox("normal") as StyleBoxFlat
	if box == null or not _is_neutral(button):
		return false
	var disc := _disc_size(button, box)
	return absf(button.size.x - button.size.y) <= 1.0 and is_equal_approx(button.size.x, RoundHudStyle.HIT) \
			and is_equal_approx(disc.x, RoundHudStyle.SIZE) and is_equal_approx(disc.y, RoundHudStyle.SIZE) \
			and box.corner_radius_top_left >= int(RoundHudStyle.SIZE * 0.4)


func _disc_size(button: Button, box: StyleBoxFlat) -> Vector2:
	return button.size + Vector2(
			box.expand_margin_left + box.expand_margin_right,
			box.expand_margin_top + box.expand_margin_bottom)


func _is_neutral(button: Button) -> bool:
	var box := button.get_theme_stylebox("normal") as StyleBoxFlat
	return box != null and box.border_width_left == 1 and box.border_color.is_equal_approx(RoundHudStyle.INK)


func _is_selected(button: Button) -> bool:
	var box := button.get_theme_stylebox("pressed") as StyleBoxFlat
	if box == null or box.border_width_left < 2:
		return false
	return box.border_color.r > RoundHudStyle.INK.r + 0.4 \
			and box.bg_color.get_luminance() > RoundHudStyle.FACE.get_luminance() + 0.15
