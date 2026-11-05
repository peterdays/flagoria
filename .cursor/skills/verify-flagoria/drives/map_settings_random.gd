extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: (no --seed; Random specs invents its own)
## Map Settings → Random specs: before/after snapshots (#335).


const MAP_SETTINGS := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/MapSettingsButton"
const PANEL := "CanvasLayer2/MapAdminPanel"
const RANDOM_SPECS := "CanvasLayer2/MapAdminPanel/Margin/VBox/Buttons/RandomSpecs"


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
	await snapshot("map-settings-before")
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
	var ok := btn != null and btn.text == "Random specs" and moved
	print("map_settings_random: water %s -> %s seed %s -> %s ok=%s"
			% [water_before, water_after, seed_before, seed_after, ok])
	await snapshot("map-settings-after-random")
	done(ok)
