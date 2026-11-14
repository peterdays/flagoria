extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 42
## Tower footprint rotation (#493). Preview at 0° and 90°, place once at 90°.

const SETTLE := 8


func run() -> void:
	step("start")
	if not await start_game():
		done(false)
		return
	var it: Interaction = current_scene.get_node(INTERACTION)
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var inventory: Inventory = current_scene.get_node(INVENTORY)
	inventory.add(Inventory.WOOD, 20)
	await toggle_mode()
	await click("CanvasLayer1/BuildingsButton")
	it.build.set_tool(BuildPlacement.Tool.TOWER)
	var anchor: Variant = _anchor_for_turn(it, map, inventory, 0)
	if anchor == null:
		printerr("footprint_rotation: no anchor")
		done(false)
		return
	var vp := _cell_vp(it, map, anchor)

	step("preview-0")
	it.build.footprint_rotation = 0
	it.build.update_preview(vp, vp)
	it._dragging = true
	it._start = vp
	it._end = vp
	it.queue_redraw()
	for i in SETTLE:
		await process_frame
	await snapshot("preview-0")

	step("preview-90")
	it.build.rotate_footprint()
	it.queue_redraw()
	for i in SETTLE:
		await process_frame
	await snapshot("preview-90")

	step("placed-90")
	var anchor_rot: Variant = _anchor_for_turn(it, map, inventory, 1)
	if anchor_rot == null:
		printerr("footprint_rotation: no anchor for rotation 1")
		done(false)
		return
	hero().global_position = map.to_global(map.map_to_local(anchor_rot + Vector2i(0, 3)))
	for i in 10:
		await process_frame
	var vp_rot := _cell_vp(it, map, anchor_rot)
	var wood := inventory.count_of(Inventory.WOOD)
	it.build.footprint_rotation = 1
	it.build.update_preview(vp_rot, vp_rot)
	if not it.build.cell_ok.all(func(ok: bool) -> bool: return ok):
		printerr("footprint_rotation: rotation 1 not placeable at %s (%s)"
				% [anchor, it.build.reasons])
		done(false)
		return
	if not it.build.commit() or inventory.count_of(Inventory.WOOD) != wood - 10:
		printerr("footprint_rotation: commit failed")
		done(false)
		return
	var rot := 0
	for p: Dictionary in map.placed_structures().values():
		if p["name"] == "tower_wood":
			rot = int(p.get("rotation", 0))
			break
	for i in SETTLE:
		await process_frame
	await snapshot("placed-rot%d" % rot)
	done(true)


func _anchor_for_turn(it: Interaction, map: TileMap, inventory: Inventory, turn: int) -> Variant:
	var placer := ConstructionPlacer.new(map)
	for cell in map.get_used_cells(0):
		if not it.in_reach(cell):
			continue
		if placer.can_place(BuildCosts.TOWER, [cell], inventory, turn).is_empty():
			return cell
	return null


func _cell_vp(it: Interaction, map: TileMap, cell: Vector2i) -> Vector2:
	var world := map.to_global(map.map_to_local(cell))
	return it.get_canvas_transform() * world