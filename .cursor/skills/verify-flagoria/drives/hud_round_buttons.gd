extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## Match start with the minimap closed, then each building button and the
## minimap button. bin/launch.sh drives/hud_round_buttons.gd --display --seed 49

const PLANK := "CanvasLayer1/BuildPicker/PlankButton"
const TOWER := "CanvasLayer1/BuildPicker/TowerButton"
const WALL := "CanvasLayer1/BuildPicker/WallButton"
const MAP_BUTTON := "CanvasLayer1/MinimapButton"


func run() -> void:
	if not await start_game():
		return
	var panel: MinimapPanel = current_scene.get_node(MINIMAP)
	var interaction: Interaction = current_scene.get_node(INTERACTION)
	var ok := await wait_until(func() -> bool:
		var plank := current_scene.get_node_or_null(PLANK) as Control
		return plank != null and plank.size.x >= 16.0 and not panel.visible
	, 5.0)
	step("match-start")
	ok = ok and _row_ok(panel)
	await snapshot("match-start")
	print("hud round: start panel %s tool %s" % [panel.visible, interaction.build.tool])

	step("plank")
	await click(PLANK)
	var plank := current_scene.get_node(PLANK) as Button
	ok = ok and interaction.build.tool == BuildPlacement.Tool.PLANK and _selected(plank)
	await snapshot("plank")
	print("hud round: plank tool %s" % interaction.build.tool)

	step("tower")
	await click(TOWER)
	ok = ok and interaction.build.tool == BuildPlacement.Tool.TOWER
	await snapshot("tower")
	print("hud round: tower tool %s" % interaction.build.tool)

	step("wall")
	await click(WALL)
	ok = ok and interaction.build.tool == BuildPlacement.Tool.WALL
	await snapshot("wall")
	print("hud round: wall tool %s" % interaction.build.tool)

	step("minimap")
	await click(MAP_BUTTON)
	ok = ok and await wait_until(func() -> bool: return panel.visible, 2.0)
	await snapshot("minimap")
	print("hud round: minimap panel %s" % panel.visible)

	var before := interaction.mode
	await click(MODE_BUTTON)
	var switched: bool = interaction.mode != before
	await click(MODE_BUTTON)
	var back: bool = interaction.mode == before and interaction.build.tool == BuildPlacement.Tool.CUT
	print("hud round: mode switched %s back %s tool %s" % [switched, back, interaction.build.tool])
	done(ok and switched and back and current_scene.get_node_or_null("CanvasLayer1/MapReopen") == null)


func _row_ok(panel: MinimapPanel) -> bool:
	var run := current_scene.get_node("CanvasLayer1/RunButton") as Button
	var mode := current_scene.get_node(MODE_BUTTON) as Button
	var names := [PLANK, TOWER, WALL, MAP_BUTTON]
	if panel.visible or not _round(run) or not _round(mode) or run.text != "Run":
		printerr("hud round: start panel %s run %s '%s'" % [panel.visible, run.size, run.text])
		return false
	if run.get_global_rect().position.x >= mode.get_global_rect().position.x:
		printerr("hud round: Run is not left of the mode button")
		return false
	var panel_rect := Rect2(panel.position, panel.size * panel.scale)
	for path in names:
		var button := current_scene.get_node(path) as Button
		if not button.visible or not _round(button) or button.get_global_rect().intersects(panel_rect):
			printerr("hud round: %s visible %s size %s" % [button.name, button.visible, button.size])
			return false
	return true


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
