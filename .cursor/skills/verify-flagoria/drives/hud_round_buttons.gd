extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## Top-right Buildings, Map and Mode. Opens and closes the build list, picks
## Plank, opens the minimap, toggles interact, and taps Run.
## bin/launch.sh drives/hud_round_buttons.gd --display --seed 49

const BUILDINGS := "CanvasLayer1/BuildingsButton"
const PLANK := "CanvasLayer1/BuildPicker/PlankButton"
const MAP_BUTTON := "CanvasLayer1/MinimapButton"
const RUN_BUTTON := "CanvasLayer1/RunButton"


func run() -> void:
	if not await start_game():
		return
	var panel: MinimapPanel = current_scene.get_node(MINIMAP)
	var interaction: Interaction = current_scene.get_node(INTERACTION)
	var buildings := current_scene.get_node(BUILDINGS) as Button
	var ok := await wait_until(func() -> bool:
		return buildings.size.x >= RoundHudStyle.HIT and not panel.visible \
				and not _plank().visible
	, 5.0)
	step("match-start")
	ok = ok and _cluster_ok(panel) and _icon_is(buildings, "icon_buildings.png") \
			and _icon_is(current_scene.get_node(MAP_BUTTON), "icon_map.png") \
			and _icon_is(current_scene.get_node(MODE_BUTTON), "icon_mode_attack.png")
	await snapshot("match-start")
	print("hud round: start panel %s tool %s" % [panel.visible, interaction.build.tool])

	step("building-list")
	await click(BUILDINGS)
	ok = ok and await wait_until(func() -> bool: return _plank().visible, 2.0)
	ok = ok and _column_ok()
	await snapshot("building-list")
	await click(BUILDINGS)
	ok = ok and await wait_until(func() -> bool: return not _plank().visible, 2.0)
	print("hud round: list closed %s" % (not _plank().visible))

	step("building-selected")
	await click(BUILDINGS)
	await click(PLANK)
	var picked: bool = interaction.build.tool == BuildPlacement.Tool.PLANK and not _plank().visible
	await click(BUILDINGS)
	var plank := _plank()
	picked = picked and plank.visible and plank.button_pressed and _selected(plank)
	ok = ok and picked
	await snapshot("building-selected")
	print("hud round: plank tool %s ring %s" % [interaction.build.tool, picked])
	await click(BUILDINGS)

	step("minimap")
	await click(MAP_BUTTON)
	ok = ok and await wait_until(func() -> bool: return panel.visible, 2.0)
	await snapshot("minimap")
	print("hud round: minimap panel %s" % panel.visible)

	step("interact")
	var before := interaction.mode
	await click(MODE_BUTTON)
	var switched: bool = interaction.mode != before and interaction.mode == Interaction.Mode.INTERACT \
			and _icon_is(current_scene.get_node(MODE_BUTTON), "icon_mode_interact.png") \
			and interaction.build.tool == BuildPlacement.Tool.PLANK
	await snapshot("interact")
	await click(MODE_BUTTON)
	var back: bool = interaction.mode == before and interaction.build.tool == BuildPlacement.Tool.CUT \
			and _icon_is(current_scene.get_node(MODE_BUTTON), "icon_mode_attack.png")
	print("hud round: mode switched %s back %s" % [switched, back])

	step("run")
	var run := current_scene.get_node(RUN_BUTTON) as Button
	await click(RUN_BUTTON)
	var ran: bool = run.running() and run.latched
	print("hud round: run latched %s" % ran)
	done(ok and switched and back and ran and current_scene.get_node_or_null("CanvasLayer1/MapReopen") == null)


func _plank() -> Button:
	return current_scene.get_node(PLANK) as Button


func _cluster_ok(panel: MinimapPanel) -> bool:
	var mode := current_scene.get_node(MODE_BUTTON) as Button
	var map_button := current_scene.get_node(MAP_BUTTON) as Button
	var buildings := current_scene.get_node(BUILDINGS) as Button
	var run := current_scene.get_node(RUN_BUTTON) as Button
	var attack := current_scene.get_node("CanvasLayer1/TouchScreenButton") as TouchScreenButton
	if panel.visible or not _round(mode) or not _round(map_button) or not _round(buildings):
		printerr("hud round: start buttons mode %s" % mode.size)
		return false
	if run.text != "Run":
		printerr("hud round: Run label '%s'" % run.text)
		return false
	var attack_rect := Rect2(attack.position, attack.texture_normal.get_size() * attack.scale)
	var run_rect := run.get_global_rect()
	if run_rect.intersects(attack_rect) or run_rect.size.x >= attack_rect.size.x:
		printerr("hud round: Run %s attack %s" % [run_rect, attack_rect])
		return false
	var mode_c := mode.get_global_rect().get_center()
	var map_c := map_button.get_global_rect().get_center()
	var build_c := buildings.get_global_rect().get_center()
	if map_c.x >= mode_c.x or build_c.y <= map_c.y:
		printerr("hud round: arc mode %s map %s buildings %s" % [mode_c, map_c, build_c])
		return false
	return true


func _column_ok() -> bool:
	var buildings := current_scene.get_node(BUILDINGS) as Button
	var picker := current_scene.get_node("CanvasLayer1/BuildPicker") as Control
	var previous := buildings.get_global_rect().end.y - 0.5
	var left := buildings.get_global_rect().position.x
	var any := false
	for child in picker.get_children():
		var button := child as Button
		if button == null or not button.visible:
			continue
		any = true
		var rect := button.get_global_rect()
		if rect.position.y < previous or absf(rect.position.x - left) > 1.0:
			printerr("hud round: %s not stacked at %s" % [button.name, rect])
			return false
		previous = rect.end.y + 1.0
	return any


func _icon_is(button: Button, file_name: String) -> bool:
	return button.icon != null and str(button.icon.resource_path).ends_with(file_name)


func _round(button: Button) -> bool:
	var box := button.get_theme_stylebox("normal") as StyleBoxFlat
	if box == null or box.border_width_left != 1:
		return false
	var disc := button.size + Vector2(
			box.expand_margin_left + box.expand_margin_right,
			box.expand_margin_top + box.expand_margin_bottom)
	return absf(button.size.x - button.size.y) <= 1.0 and is_equal_approx(button.size.x, RoundHudStyle.HIT) \
			and is_equal_approx(disc.x, RoundHudStyle.SIZE) \
			and box.corner_radius_top_left >= int(RoundHudStyle.SIZE * 0.4)


func _selected(button: Button) -> bool:
	var box := button.get_theme_stylebox("pressed") as StyleBoxFlat
	return button.button_pressed and box != null and box.border_width_left >= 2 \
			and box.border_color.r > RoundHudStyle.INK.r + 0.4
