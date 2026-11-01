extends SceneTree
## Base for feature drives. A drive lives in drives/<feature>.gd, starts with
## `extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"`,
## overrides run(), and is started with `bin/launch.sh drives/<feature>.gd`.
##
## Every helper goes through the path a player uses: pointer clicks and touch
## taps at positions read from the nodes at run time, and the input actions
## the game reads. A drive may read state to decide when to go on, but never
## sets game state (see SKILL.md, Drive).
##
## Lines on stdout, read by bin/launch.sh:
##   VERIFY_READY pid=<pid> scene=<scene>  a game is hosted and the hero exists
##   VERIFY_STEP <name>                     a drive step begins
##   VERIFY_DONE ok|fail                    the drive finished; exit 0 or 1
##   VERIFY_IDLE pid=<pid>                  the drive stays up for an agent
##
## snapshot(label) writes evidence to $VERIFY_EVIDENCE_DIR, which launch.sh
## sets to artifacts/out/runs/<run-id>/ (see SKILL.md, Evidence).

const MAIN := "res://flagoria_main.tscn"
const HOST_BUTTON := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/HostButton"
const MODE_BUTTON := "CanvasLayer1/ModeButton"
const MENU_BUTTON := "CanvasLayer1/InGameMenu/MenuButton"
const MENU_PANEL := "CanvasLayer1/InGameMenu/Pause"
const SAVE_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/Save"
const WORLD_MAP := "World/worldMap"
## Movement (Scripts/player.gd) and attack, as named in project.godot.
const ACTIONS := ["ui_left", "ui_right", "ui_up", "ui_down", "attack"]
## How long start_game() waits for each of the Host button and the hero.
const START_TIMEOUT_S := 30.0
## idle() quits on its own after this long, in case cleanup is never run.
const MAX_IDLE_S := 600.0
const INTERACTION := "World/Interaction"
const INVENTORY := "Inventory"
const MINIMAP := "CanvasLayer1/MinimapPanel"
const FOLIAGE_LAYER := 1
## snapshot() records the foliage layer in a square this many cells from the
## hero on each side: 9x9.
const SNAPSHOT_RADIUS := 4

var _finished := false
var _snapshots := 0


func _initialize() -> void:
	call_deferred("_drive")


func _drive() -> void:
	await run()
	if not _finished:
		printerr("drive: run() returned without done() or idle()")
		done(false)


## The drive. Override it; call done() or idle() at the end.
func run() -> void:
	pass


## Loads the main scene, clicks Host, and prints the ready line once the local
## hero exists under World. On failure it prints why, calls done(false) and
## returns false.
func start_game() -> bool:
	if change_scene_to_file(MAIN) != OK:
		return _fail("cannot load " + MAIN)
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(HOST_BUTTON), START_TIMEOUT_S):
		return _fail("no " + HOST_BUTTON)
	await click(HOST_BUTTON)
	if not await wait_until(func() -> bool: return hero() != null, START_TIMEOUT_S):
		return _fail("no local hero under World after clicking Host")
	print("VERIFY_READY pid=%d scene=%s" % [OS.get_process_id(), MAIN])
	return true


## The local player's hero, or null before it spawns.
func hero() -> Node2D:
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("World/%d" % get_multiplayer().get_unique_id()) as Node2D


## Holds an input action for some physics frames, then releases it.
func hold(action: String, frames: int) -> void:
	assert(action in ACTIONS, "drive: unknown action " + action)
	_action(action, true)
	for i in range(frames):
		await physics_frame
	_action(action, false)
	await physics_frame


func tap(action: String) -> void:
	await hold(action, 1)


## Clicks the mode button, as a player does to switch combat and interact mode.
func toggle_mode() -> void:
	await click(MODE_BUTTON)


## A touch tap on a map cell, at the screen position World/worldMap and the
## camera give it now. Like a finger, a tap on a cell under the HUD (the
## minimap, the buttons) reaches the HUD, not the map.
func tap_cell(cell: Vector2i) -> void:
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var at := to_window(map, map.map_to_local(cell))
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.pressed = pressed
		e.position = at
		Input.parse_input_event(e)
		await process_frame
		await process_frame


## Opens the in-game menu with its menu button and clicks Save. Returns false
## if the menu did not open.
func menu_save() -> bool:
	await click(MENU_BUTTON)
	var panel: Control = current_scene.get_node(MENU_PANEL)
	if not await wait_until(func() -> bool: return panel.is_visible_in_tree(), 5.0):
		return false
	await click(SAVE_BUTTON)
	return true


## A left click at the centre of a Control, given by its path from the scene.
func click(path: String) -> void:
	var control: Control = current_scene.get_node(path)
	var at := to_window(control, control.size / 2.0)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	var events: Array[InputEvent] = [move]
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		events.append(e)
	for e in events:
		Input.parse_input_event(e)
		await process_frame
		await process_frame


## Window pixels for a point local to a canvas item: through its canvas
## transform (camera included) and the window's stretch transform. Input
## events are given in window pixels, which the root viewport maps back.
func to_window(item: CanvasItem, local: Vector2) -> Vector2:
	return root.get_final_transform() * (item.get_global_transform_with_canvas() * local)


## Waits frame by frame until predicate returns true or timeout_s passes.
func wait_until(predicate: Callable, timeout_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not predicate.call():
		if Time.get_ticks_msec() > end:
			return false
		await process_frame
	return true


## Writes <NN>-<label>.json with the game state a player can see: hero cell
## and facing, mode, inventory counts, explored cell count and the foliage
## tile names in a 9x9 square around the hero. Under --display it also writes
## <NN>-<label>.png of the window; headless runs have no image, and the JSON
## says so. Returns the JSON path, or "" outside launch.sh.
func snapshot(label: String) -> String:
	var dir := OS.get_environment("VERIFY_EVIDENCE_DIR")
	if dir == "":
		printerr("drive: snapshot %s skipped: VERIFY_EVIDENCE_DIR is unset (start drives with bin/launch.sh)" % label)
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	_snapshots += 1
	var base := dir.path_join("%02d-%s" % [_snapshots, label.validate_filename()])
	var state := snapshot_state()
	state["label"] = label
	if DisplayServer.get_name() == "headless":
		state["png"] = "skipped: headless run, no image (launch with --display for one)"
	else:
		await RenderingServer.frame_post_draw
		var png := base + ".png"
		var err := root.get_texture().get_image().save_png(png)
		state["png"] = png.get_file() if err == OK else "failed: error %d" % err
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  ", false) + "\n")
	f.close()
	print("drive: snapshot %s" % base.get_file())
	return base + ".json"


## The state snapshot() records, read from the nodes; never sets anything.
func snapshot_state() -> Dictionary:
	var state := {}
	var h := hero()
	var map: TileMap = current_scene.get_node_or_null(WORLD_MAP) if current_scene else null
	if h == null or map == null:
		state["hero"] = null
		return state
	var cell := map.local_to_map(map.to_local(h.global_position))
	state["hero"] = {"cell": [cell.x, cell.y], "facing": h.get("lastAnimDirection")}
	var it := current_scene.get_node_or_null(INTERACTION)
	if it != null:
		var modes: Dictionary = it.get_script().get_script_constant_map()["Mode"]
		state["mode"] = str(modes.find_key(it.mode)).to_lower()
	var inventory := current_scene.get_node_or_null(INVENTORY)
	if inventory != null:
		var counts := {}
		for value in inventory.get_script().get_script_constant_map().values():
			if value is StringName:
				counts[str(value)] = inventory.count_of(value)
		state["inventory"] = counts
	var minimap := current_scene.get_node_or_null(MINIMAP)
	if minimap != null:
		state["explored_cells"] = minimap.explored.explored_count()
	state["foliage"] = _foliage_names(map, cell)
	return state


## Rows of tile names from TileCatalog (null for an empty cell), top to
## bottom, around `center` on the foliage layer.
func _foliage_names(map: TileMap, center: Vector2i) -> Array:
	var names := {}
	var catalog: Dictionary = (load("res://Scripts/tile_catalog.gd") as Script).get_script_constant_map()
	for key in catalog:
		if catalog[key] is Vector2i and not names.has(catalog[key]):
			names[catalog[key]] = key  # first declared name wins for shared coords
	var rows := []
	for dy in range(-SNAPSHOT_RADIUS, SNAPSHOT_RADIUS + 1):
		var row := []
		for dx in range(-SNAPSHOT_RADIUS, SNAPSHOT_RADIUS + 1):
			var cell := center + Vector2i(dx, dy)
			var source := map.get_cell_source_id(FOLIAGE_LAYER, cell)
			var atlas := map.get_cell_atlas_coords(FOLIAGE_LAYER, cell)
			if source == -1:
				row.append(null)
			elif source == TileCatalog.SOURCE_ID and names.has(atlas):
				row.append(names[atlas])
			else:
				row.append("source %d atlas %d,%d" % [source, atlas.x, atlas.y])
		rows.append(row)
	return rows


func step(name: String) -> void:
	print("VERIFY_STEP " + name)


## Ends the drive: prints VERIFY_DONE ok|fail and quits with 0 or 1.
func done(ok: bool) -> void:
	if _finished:
		return
	_finished = true
	print("VERIFY_DONE " + ("ok" if ok else "fail"))
	quit(0 if ok else 1)


## Leaves the game running for an agent: prints VERIFY_IDLE, which makes
## bin/launch.sh return 0, then waits for bin/cleanup.sh to stop it.
func idle() -> void:
	if _finished:
		return
	_finished = true
	print("VERIFY_IDLE pid=%d" % OS.get_process_id())
	await create_timer(MAX_IDLE_S).timeout
	quit(0)


func _action(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)


func _fail(why: String) -> bool:
	printerr("drive: " + why)
	done(false)
	return false
