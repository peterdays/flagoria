extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: (no --seed; Random specs invents its own)
## Map Settings → five-button layout at 1280x720 and 854x480, then Random specs (#217, #335).


const MAP_SETTINGS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/MapSettingsButton"
const PANEL := "CanvasLayer2/MapAdminPanel"
const RANDOM_SPECS := "CanvasLayer2/MapAdminPanel/Margin/VBox/Buttons/RandomSpecs"
const BACK := "CanvasLayer2/MapAdminPanel/Margin/VBox/ButtonsDefaults/Back"
## The five action buttons, in row order.
const ACTION_BUTTONS := [
	"CanvasLayer2/MapAdminPanel/Margin/VBox/Buttons/RandomSeed",
	"CanvasLayer2/MapAdminPanel/Margin/VBox/Buttons/RandomSpecs",
	"CanvasLayer2/MapAdminPanel/Margin/VBox/ButtonsDefaults/Reset",
	"CanvasLayer2/MapAdminPanel/Margin/VBox/ButtonsDefaults/Back",
	"CanvasLayer2/MapAdminPanel/Margin/VBox/Buttons2/Start",
]


func run() -> void:
	step("menu")
	if change_scene_to_file(MAIN) != OK:
		_fail("cannot load " + MAIN)
		return
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(MAP_SETTINGS), START_TIMEOUT_S):
		_fail("no Map Settings button")
		return
	print("VERIFY_READY pid=%d scene=%s" % [OS.get_process_id(), MAIN])
	step("open-map-settings")
	await click(MAP_SETTINGS)
	if not await wait_until(func() -> bool:
			var p = current_scene.get_node_or_null(PANEL)
			return p != null and p.visible, 5.0):
		_fail("Map Settings panel did not open")
		return
	var panel: Node = current_scene.get_node(PANEL)
	var water_spin: SpinBox = panel._spin_boxes["water_max_alt"]
	var water_before: float = water_spin.value
	var seed_before: int = root.get_node("MapGen").params.altitude_seed
	var layout_ok := _buttons_fit("1280x720")
	await snapshot("map-settings-before")
	step("landscape")
	var landscape := await _resize(854, 480)
	# Stretch aspect is keep, so this shorter landscape window still lays the
	# panel out in the 480x270 space. The shot is that window, not a new size.
	var landscape_ok := landscape.x < 1100 and landscape.y < 600 and landscape.x > landscape.y
	if DisplayServer.get_name() == "headless":
		landscape_ok = true
	layout_ok = _buttons_fit("landscape") and layout_ok and landscape_ok
	await snapshot("map-settings-landscape")
	var restored := await _resize(1280, 720)
	if DisplayServer.get_name() != "headless" and restored.x < 1100:
		layout_ok = false
	layout_ok = _buttons_fit("restored") and layout_ok
	step("random-specs")
	await click(RANDOM_SPECS)
	await process_frame
	await process_frame
	var water_after: float = water_spin.value
	var seed_after: int = root.get_node("MapGen").params.altitude_seed
	var btn: Button = current_scene.get_node(RANDOM_SPECS)
	var moved := water_after != water_before or seed_after != seed_before
	if not moved:
		var p = root.get_node("MapGen").params
		moved = p.island_radius != 0 or p.archipelago_spacing != 0
	var ok := btn != null and btn.text == "Random specs" and moved and layout_ok
	print("map_settings_random: water %s -> %s seed %s -> %s window=%s layout=%s ok=%s"
			% [water_before, water_after, seed_before, seed_after, landscape, layout_ok, ok])
	await snapshot("map-settings-after-random")
	step("back")
	await click(BACK)
	var menu_back := await wait_until(func() -> bool:
		var menu := current_scene.get_node_or_null("CanvasLayer2/MainMenu")
		var p := current_scene.get_node_or_null(PANEL)
		return menu != null and menu.visible and p != null and not p.visible, 5.0)
	print("map_settings_random: back_to_menu=%s" % menu_back)
	done(ok and menu_back)


func _resize(width: int, height: int) -> Vector2i:
	root.size = Vector2i(width, height)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(width, height))
	for _i in 12:
		await process_frame
	var got := DisplayServer.window_get_size()
	print("map_settings_random: window %s (asked %dx%d) visible %s" % [got, width, height, root.get_visible_rect().size])
	return got


func _buttons_fit(tag: String) -> bool:
	var vp: Rect2 = root.get_visible_rect()
	var rects: Array[Rect2] = []
	var ok := true
	for path in ACTION_BUTTONS:
		var b: Control = current_scene.get_node_or_null(path)
		if b == null:
			print("map_settings_random: %s missing %s" % [tag, path])
			ok = false
			continue
		var rect := b.get_global_rect()
		rects.append(rect)
		var inside := vp.encloses(rect)
		print("map_settings_random: %s %s rect=%s size=%s inside=%s" % [tag, b.name, rect, b.size, inside])
		if not inside or b.size.x < 40.0 or b.size.y < 24.0:
			ok = false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				print("map_settings_random: %s overlap %s %s" % [tag, rects[i], rects[j]])
				ok = false
	return ok
