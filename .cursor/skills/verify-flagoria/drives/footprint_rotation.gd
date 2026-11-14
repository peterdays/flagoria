extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 42
## Two tower placements at rotation 0 and 90°, green previews, rotate button.

const SETTLE := 10
const ROTATE_BTN := "CanvasLayer1/FootprintRotateButton"
const WOOD := 30
const STAND_OFFS := [
	Vector2i(0, 5), Vector2i(5, 0), Vector2i(0, -5), Vector2i(-5, 0),
	Vector2i(0, 6), Vector2i(6, 0), Vector2i(0, -6), Vector2i(-6, 0),
	Vector2i(4, 4), Vector2i(-4, 4), Vector2i(4, -4), Vector2i(-4, -4),
	Vector2i(0, 7), Vector2i(7, 0), Vector2i(0, -7), Vector2i(-7, 0),
	Vector2i(5, 5), Vector2i(-5, 5), Vector2i(5, -5), Vector2i(-5, -5),
]


func run() -> void:
	step("start")
	if not await start_game():
		done(false)
		return
	var it: Interaction = current_scene.get_node(INTERACTION)
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var inventory: Inventory = current_scene.get_node(INVENTORY)
	inventory.add(Inventory.WOOD, WOOD)
	await toggle_mode()
	await click("CanvasLayer1/BuildingsButton")
	it.build.set_tool(BuildPlacement.Tool.TOWER)
	var placer := ConstructionPlacer.new(map)
	var sites: Dictionary = _plan_sites(it, map, inventory, placer)
	if sites.is_empty():
		printerr("footprint_rotation: no twin sites on this seed")
		done(false)
		return
	var preview: Vector2i = sites["preview"]
	var place0: Vector2i = sites["place0"]
	var place1: Vector2i = sites["place1"]
	if not await _stand_for_anchor(it, map, placer, inventory, preview, [0, 1]):
		printerr("footprint_rotation: cannot stand beside preview %s" % preview)
		done(false)
		return
	var vp := _cell_vp(it, map, preview)

	step("preview-0")
	if not await _preview_valid(it, map, vp, preview, 0):
		printerr("footprint_rotation: preview 0 not green at %s" % preview)
		done(false)
		return
	await snapshot("preview-0")

	step("preview-90")
	if not await _preview_valid(it, map, vp, preview, 1):
		printerr("footprint_rotation: preview 90 not green at %s rot %d reasons %s"
				% [preview, it.build.footprint_rotation, it.build.reasons])
		done(false)
		return
	await snapshot("preview-90")

	step("placed-two")
	it.build.set_tool(BuildPlacement.Tool.TOWER)
	if not await _place_tower(it, map, placer, inventory, place0, 0, [0]):
		printerr("footprint_rotation: first tower failed at %s" % place0)
		done(false)
		return
	if not await _place_tower(it, map, placer, inventory, place1, 1, [1]):
		printerr("footprint_rotation: second tower failed at %s" % place1)
		done(false)
		return
	for i in SETTLE:
		await process_frame
	await snapshot("placed-two")
	done(true)


func _plan_sites(it: Interaction, map: TileMap, inventory: Inventory, placer: ConstructionPlacer) -> Dictionary:
	var preview: Variant = null
	for cell in map.get_used_cells(0):
		if not it.in_reach(cell):
			continue
		if placer.can_place(BuildCosts.TOWER, [cell], inventory, 0).is_empty() \
				and placer.can_place(BuildCosts.TOWER, [cell], inventory, 1).is_empty():
			preview = cell
			break
	if preview == null:
		return {}
	var list0: Array[Vector2i] = []
	var list1: Array[Vector2i] = []
	for cell in map.get_used_cells(0):
		if placer.can_place_geometry(BuildCosts.TOWER, [cell], 0).is_empty():
			list0.append(cell)
		if placer.can_place_geometry(BuildCosts.TOWER, [cell], 1).is_empty():
			list1.append(cell)
	for a in list0:
		var foot_a: Array = placer.tower_footprint(a, 0)
		for b in list1:
			if a == b:
				continue
			if maxi(absi(a.x - b.x), absi(a.y - b.y)) < 4:
				continue
			var foot_b: Array = placer.tower_footprint(b, 1)
			if _overlap(foot_a, foot_b):
				continue
			return {"preview": preview, "place0": a, "place1": b}
	return {}


func _overlap(a: Array, b: Array) -> bool:
	var seen := {}
	for c: Vector2i in b:
		seen[c] = true
	for c: Vector2i in a:
		if seen.has(c):
			return true
	return false


func _footprint_cells(placer: ConstructionPlacer, anchor: Vector2i, quarter_turns: int) -> Dictionary:
	var out := {}
	for c: Vector2i in placer.tower_footprint(anchor, quarter_turns):
		out[c] = true
	return out


func _stand_for_anchor(it: Interaction, map: TileMap, placer: ConstructionPlacer,
		inventory: Inventory, anchor: Vector2i, rotations: Array[int]) -> bool:
	var blocked := {}
	for rot in rotations:
		for c in _footprint_cells(placer, anchor, rot):
			blocked[c] = true
	for off: Vector2i in STAND_OFFS:
		var stand: Vector2i = anchor + off
		if blocked.has(stand):
			continue
		hero().global_position = map.to_global(map.map_to_local(stand))
		for i in SETTLE:
			await process_frame
		if not it.in_reach(anchor):
			continue
		var one: Array[Vector2i] = [anchor]
		var ok := true
		for rot in rotations:
			if not placer.can_place(BuildCosts.TOWER, one, inventory, rot).is_empty():
				ok = false
				break
		if ok:
			return true
	return false


func _preview_valid(it: Interaction, map: TileMap, vp: Vector2, anchor: Vector2i,
		want_rot: int) -> bool:
	await _preview_at(it, map, vp)
	var guard := 0
	while it.build.footprint_rotation != want_rot:
		guard += 1
		if guard > 4:
			printerr("footprint_rotation: rotate stuck at %d want %d"
					% [it.build.footprint_rotation, want_rot])
			return false
		await click(ROTATE_BTN)
		it.build.update_preview(vp, vp)
		it.queue_redraw()
		for i in SETTLE:
			await process_frame
	if it.build._snap_from != anchor:
		printerr("footprint_rotation: preview snapped to %s, want %s"
				% [it.build._snap_from, anchor])
		return false
	return it.build.footprint_rotation == want_rot \
			and it.build.cell_ok.all(func(ok: bool) -> bool: return ok)


func _place_tower(it: Interaction, map: TileMap, placer: ConstructionPlacer,
		inventory: Inventory, anchor: Vector2i, want_rot: int, rotations: Array[int]) -> bool:
	if not await _stand_for_anchor(it, map, placer, inventory, anchor, rotations):
		printerr("footprint_rotation: no stand at %s rot %d" % [anchor, want_rot])
		return false
	var vp := _cell_vp(it, map, anchor)
	if not await _preview_valid(it, map, vp, anchor, want_rot):
		printerr("footprint_rotation: preview failed at %s rot %d reasons %s"
				% [anchor, want_rot, it.build.reasons])
		return false
	if not it.build.commit():
		printerr("footprint_rotation: commit failed at %s rot %d reasons %s"
				% [anchor, want_rot, it.build.reasons])
		return false
	return true


func _preview_at(it: Interaction, map: TileMap, vp: Vector2) -> void:
	it._dragging = true
	it._start = vp
	it._end = vp
	it.build.update_preview(vp, vp)
	it.queue_redraw()
	for i in SETTLE:
		await process_frame


func _cell_vp(it: Interaction, map: TileMap, cell: Vector2i) -> Vector2:
	var world := map.to_global(map.map_to_local(cell))
	return it.get_canvas_transform() * world