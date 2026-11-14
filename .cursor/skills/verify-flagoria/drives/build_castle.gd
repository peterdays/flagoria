extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 11
## Place a second castle for 50 wood at rotation 90°, save and reload.


const ROTATE_BTN := "CanvasLayer1/FootprintRotateButton"
const MAIN_MENU_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/MainMenu"
const STAND_OFFS := [
	Vector2i(0, 5), Vector2i(5, 0), Vector2i(-5, 0), Vector2i(0, -5),
	Vector2i(0, 4), Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, -4),
	Vector2i(3, 3), Vector2i(-3, 3), Vector2i(3, -3), Vector2i(-3, -3),
]


func run() -> void:
	step("start")
	if not await start_game():
		return
	var it: Interaction = current_scene.get_node(INTERACTION)
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var inventory: Inventory = current_scene.get_node(INVENTORY)
	inventory.add(Inventory.WOOD, 50)
	await toggle_mode()
	await click("CanvasLayer1/BuildingsButton")
	it.build.set_tool(BuildPlacement.Tool.CASTLE)
	var placer := ConstructionPlacer.new(map)
	var anchor: Variant = _find_anchor(map, placer)
	if anchor == null:
		printerr("build_castle: no anchor on this seed")
		done(false)
		return
	if not await _stand_near(it, map, placer, inventory, anchor):
		printerr("build_castle: could not reach anchor %s" % anchor)
		done(false)
		return
	var vp := _cell_vp(it, map, anchor)
	for i in 1:
		await click(ROTATE_BTN)
		it.build.update_preview(vp, vp)
		for _j in 8:
			await process_frame
	if it.build.cost != 50 or it.build.reasons.size() > 0:
		printerr("build_castle: preview refused %s cost %s" % [it.build.reasons, it.build.cost])
		done(false)
		return
	step("place")
	it.build.commit()
	for i in 20:
		await physics_frame
	if map.placed_structures().size() < 2:
		printerr("build_castle: placements %s" % map.placed_structures())
		done(false)
		return
	await snapshot("second_castle_placed")

	step("save")
	var saved := []
	root.get_node("MapGen").map_saved.connect(func(path: String) -> void: saved.append(path))
	if not await menu_save() or not await wait_until(func() -> bool: return not saved.is_empty(), 5.0):
		printerr("build_castle: save failed")
		done(false)
		return
	await click(MAIN_MENU_BUTTON)
	await wait_until(func() -> bool: return current_scene != null and current_scene.has_node(HOST_BUTTON), 10.0)
	var err: String = root.get_node("MapGen").load_map_inputs(saved[0])
	if err != "" or not await start_game():
		printerr("build_castle: load %s" % err)
		done(false)
		return
	for i in 20:
		await physics_frame
	map = current_scene.get_node(WORLD_MAP)
	var ok: bool = map.placed_structures().size() >= 2
	await snapshot("second_castle_loaded")
	done(ok)


func _find_anchor(map: TileMap, placer: ConstructionPlacer) -> Variant:
	var base: Vector2i = map.spawn_point + Vector2i(28, 4)
	for turns in [0, 1, 2]:
		for r in range(8, 56):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var cell := base + Vector2i(dx, dy)
					if placer.can_place_geometry(BuildCosts.CASTLE, [cell], turns).is_empty():
						return cell
	return null


func _stand_near(it: Interaction, map: TileMap, placer: ConstructionPlacer,
		inventory: Inventory, anchor: Vector2i) -> bool:
	var one: Array[Vector2i] = [anchor]
	for off: Vector2i in STAND_OFFS:
		hero().global_position = map.to_global(map.map_to_local(anchor + off))
		for i in 8:
			await process_frame
		if it.in_reach(anchor) \
				and placer.can_place(BuildCosts.CASTLE, one, inventory, it.build.footprint_rotation).is_empty():
			return true
	return false


func _cell_vp(it: Interaction, map: TileMap, cell: Vector2i) -> Vector2:
	return it.get_canvas_transform() * map.to_global(map.map_to_local(cell))