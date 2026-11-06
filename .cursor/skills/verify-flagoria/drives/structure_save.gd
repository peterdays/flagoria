extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 11
## Structures in world saves (#42, features/map-save.md save-structures).
## Host, put a wooden tower held by the mobs (purple flag) and a palisade
## ring next to the start castle, save with the in-game menu's Save button,
## leave with its Main menu button, load the save, host again. Proof: the
## same castle, tower (purple flag) and walls in the "loaded" shot, one
## castle only. The tower and walls are placed through the map API (as the
## cities drive does), and the load goes through MapGen.load_map_inputs:
## no menu lists saves yet.

const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"


func run() -> void:
	step("build")
	if not await start_game():
		return
	for i in 20:
		await physics_frame
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var at: Vector2i = map.local_to_map(map.to_local(hero().global_position))
	var tower: Structure = StructurePlacer.load_named("tower_wood")
	var anchor: Variant = StartCastle.find_anchor(map, tower, at + Vector2i(4, 2))
	if anchor == null or map.place_structure(tower, anchor, StructurePlacer.OWNER_MOBS) <= 0:
		printerr("structure_save: no tower spot near %s" % at)
		done(false)
		return
	var ring: Array[Vector2i] = []
	var lo: Vector2i = anchor + Vector2i(-3, -4)
	for x in range(lo.x, lo.x + 7):
		for y in [lo.y, lo.y + 6]:
			ring.append(Vector2i(x, y))
	for y in range(lo.y + 1, lo.y + 6):
		for x in [lo.x, lo.x + 6]:
			ring.append(Vector2i(x, y))
	ring = ring.filter(func(c: Vector2i) -> bool: return map.predicted_clear(c) and not map._structures.has_cell(c))
	map.place_wall_cells(ring)
	for i in 8:
		await process_frame
	await snapshot("before_save")
	var want: Array = map.structures_for_sync()
	print("structure_save: placed %s walls=%d" % [want, ring.size()])

	step("save")
	var saved := []
	root.get_node("MapGen").map_saved.connect(func(path: String) -> void: saved.append(path))
	if not await menu_save() or not await wait_until(func() -> bool: return not saved.is_empty(), 5.0):
		printerr("structure_save: Save did not write a file")
		done(false)
		return
	await snapshot("saved")
	await click(MAIN_MENU_BUTTON)
	await wait_until(func() -> bool: return current_scene != null and current_scene.has_node(HOST_BUTTON), 10.0)

	step("load")
	var err: String = root.get_node("MapGen").load_map_inputs(saved[0])
	if err != "" or not await start_game():
		printerr("structure_save: load %s" % err)
		done(false)
		return
	for i in 20:
		await physics_frame
	map = current_scene.get_node(WORLD_MAP)
	var got: Array = map.structures_for_sync()
	var walls_back := ring.all(func(c: Vector2i) -> bool: return map.has_wall(c))
	await snapshot("loaded")
	print("structure_save: loaded %s walls_back=%s" % [got, walls_back])
	done(str(got) == str(want) and walls_back)
