extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 11
## Junction screens: castle, guard post, joins, loop open and closed, caps cleared, 854x480.

const SETTLE_FRAMES := 8


func run() -> void:
	step("castle")
	if not await start_game() or not await settle():
		done(false)
		return
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var minimap: MinimapPanel = current_scene.get_node_or_null("CanvasLayer1/MinimapPanel")
	if minimap != null:
		minimap.shown = false
		minimap.visible = false
	print("wall_junctions: window %s" % DisplayServer.window_get_size())
	var castle_anchor: Variant = _placement_anchor(map, "castle")
	if castle_anchor == null or not _is_prefix(map, castle_anchor + Vector2i(-3, -4), "WALL_CORNER_OUT_"):
		printerr("wall_junctions: castle corner is not a solved outside corner")
		done(false)
		return
	await _look(map, castle_anchor)
	await snapshot("castle")

	step("guard-post")
	var post: Structure = StructurePlacer.load_named("guard_post")
	var post_at: Variant = _clear_anchor(map, post)
	if post_at == null or map.place_structure(post, post_at, 1) <= 0 \
			or not _is_prefix(map, post_at + Vector2i(-2, -3), "WALL_CORNER_OUT_"):
		printerr("wall_junctions: guard_post corner did not solve")
		done(false)
		return
	await _look(map, post_at)
	await snapshot("guard-post")

	step("joins")
	var tower: Structure = StructurePlacer.load_named("tower_wood")
	var pair: Variant = _tower_pair(map, tower)
	if pair == null:
		printerr("wall_junctions: no tower pair with room for the joins")
		done(false)
		return
	var a: Vector2i = pair[0]
	var gap: Vector2i = pair[1]
	if map.place_structure(tower, a, 1) <= 0 or map.place_structure(tower, a + Vector2i(4, 0), 1) <= 0:
		printerr("wall_junctions: tower place failed")
		done(false)
		return
	var gap_cells: Array[Vector2i] = [gap]
	var straight := a + Vector2i(0, -3)
	var bend := a + Vector2i(-2, -1)
	var tee := a + Vector2i(4, -3)
	var cross := a + Vector2i(4, 1)
	var shapes: Array[Vector2i] = [straight, straight + Vector2i(0, -1), bend, bend + Vector2i(0, 1),
		tee, tee + Vector2i(1, 0), tee + Vector2i(-1, 0), cross, cross + Vector2i(1, 0),
		cross + Vector2i(-1, 0), cross + Vector2i(0, 1)]
	if not map.place_wall_cells(gap_cells) or not map.place_wall_cells(shapes) \
			or map._walls.cap_names(gap) != ["CAP_COLLAR_E", "CAP_COLLAR_W"] \
			or map.predict_cell(a + Vector2i(0, -1))[1] != TileCatalog.PROP_FLAG_BLUE \
			or _name_at(map, 1, straight) != "PALISADE_V" \
			or _name_at(map, 1, bend) != "PALISADE_CORNER_OUT_NW" \
			or _name_at(map, 1, tee) != "PALISADE_T_N" \
			or _name_at(map, 1, cross) != "PALISADE_CROSS":
		printerr("wall_junctions: joins caps %s straight %s bend %s tee %s cross %s flag %s" % [
			map._walls.cap_names(gap), _name_at(map, 1, straight), _name_at(map, 1, bend),
			_name_at(map, 1, tee), _name_at(map, 1, cross), map.predict_cell(a + Vector2i(0, -1))[1]])
		done(false)
		return
	await _look(map, gap + Vector2i(0, 2))
	await snapshot("joins")

	step("loop-open")
	var origin: Variant = _find_rect(map, Vector2i(11, 6))
	if origin == null:
		printerr("wall_junctions: no land for the loop")
		done(false)
		return
	var o: Vector2i = origin
	var notch: Array[Vector2i] = []
	var rows := ["#######....", "#..#..#....", "#..#..#####", "#.........#", "#.........#", "####.######"]
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				notch.append(o + Vector2i(x, y))
	var far: Vector2i = o + Vector2i(6, 2)
	var closing: Vector2i = o + Vector2i(4, 5)
	if not map.place_wall_cells(notch):
		printerr("wall_junctions: open loop refused")
		done(false)
		return
	var open_piece: Vector2i = map._walls.piece(far)
	await _look(map, far)
	await snapshot("loop-open")

	step("loop-closed")
	var close_cells: Array[Vector2i] = [closing]
	if not map.place_wall_cells(close_cells) or map._walls.piece(far) == open_piece \
			or not _name_at(map, 1, far).begins_with("PALISADE_CORNER_IN_"):
		printerr("wall_junctions: far corner did not flip (%s)" % _name_at(map, 1, far))
		done(false)
		return
	await _look(map, far)
	await snapshot("loop-closed")

	step("caps-cleared")
	if not map._walls.erase_cells(gap_cells) or not map._walls.cap_names(gap).is_empty() \
			or map.get_cell_source_id(WallBuilder.CAP_LAYER, gap) != -1 \
			or map.get_cell_source_id(WallBuilder.CAP_LAYER_2, gap) != -1:
		printerr("wall_junctions: collars stayed after remove")
		done(false)
		return
	await _look(map, gap + Vector2i(0, 2))
	await snapshot("caps-cleared")
	if not map.place_wall_cells(gap_cells):
		printerr("wall_junctions: could not put the two-collar cell back")
		done(false)
		return

	step("constrained")
	# Same landscape phone window the explored-map drive uses (854x480).
	if not await _resize(854, 480):
		done(false)
		return
	await _look(map, gap + Vector2i(0, 2))
	await snapshot("constrained")
	done(true)


func _resize(width: int, height: int) -> bool:
	root.size = Vector2i(width, height)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(width, height))
	for i in 10:
		await process_frame
	var got := DisplayServer.window_get_size()
	var tex := Vector2.ZERO
	if root.get_texture() != null:
		tex = root.get_texture().get_size()
	print("wall_junctions: window %s texture %s (asked %dx%d)" % [got, tex, width, height])
	if got.x != width or got.y != height:
		printerr("wall_junctions: window stayed %s" % got)
		return false
	return true


func settle(timeout_s: float = 5.0) -> bool:
	var last := Vector2.INF
	var still := 0
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end:
		var h := hero()
		if h == null:
			await physics_frame
			continue
		var now := h.global_position
		still = still + 1 if now == last else 0
		if still >= SETTLE_FRAMES:
			return true
		last = now
		await physics_frame
	printerr("wall_junctions: hero did not settle")
	return false


func _look(map: TileMap, cell: Vector2i) -> void:
	var player := hero()
	if player != null:
		player.global_position = map.to_global(map.map_to_local(cell))
	for i in SETTLE_FRAMES:
		await process_frame


func _placement_anchor(map: TileMap, structure_name: String) -> Variant:
	for id in map.placed_structures():
		var entry: Dictionary = map.placed_structures()[id]
		if entry["name"] == structure_name:
			return entry["anchor"]
	return null


func _clear_anchor(map: TileMap, structure: Structure) -> Variant:
	for cell: Vector2i in map.get_used_cells(0):
		var cells: Array = StructurePlacer.footprint(structure, cell).keys()
		if cells.all(func(c): return map.get_cell_source_id(0, c) != -1 and map.predicted_clear(c)):
			return cell
	return null


func _tower_pair(map: TileMap, tower: Structure) -> Variant:
	for cell: Vector2i in map.get_used_cells(0):
		var gap: Vector2i = cell + Vector2i(2, -1)
		var both: Array = StructurePlacer.footprint(tower, cell).keys()
		both.append_array(StructurePlacer.footprint(tower, cell + Vector2i(4, 0)).keys())
		var extra: Array[Vector2i] = [cell + Vector2i(0, -3), cell + Vector2i(0, -4),
			cell + Vector2i(-2, -1), cell + Vector2i(-2, 0), cell + Vector2i(4, -3),
			cell + Vector2i(3, -3), cell + Vector2i(5, -3), cell + Vector2i(4, 1),
			cell + Vector2i(3, 1), cell + Vector2i(5, 1), cell + Vector2i(4, 2)]
		if both.all(func(c): return map.get_cell_source_id(0, c) != -1 and map.predicted_clear(c)) \
				and map.predicted_clear(gap) and _open_land(map, extra):
			return [cell, gap]
	return null


func _find_rect(map: TileMap, size: Vector2i) -> Variant:
	for origin: Vector2i in map.get_used_cells(0):
		var cells: Array[Vector2i] = []
		for y in size.y:
			for x in size.x:
				cells.append(origin + Vector2i(x, y))
		if _open_land(map, cells):
			return origin
	return null


func _open_land(map: TileMap, cells: Array) -> bool:
	for c in cells:
		if map.get_cell_source_id(0, c) == -1 or map._structures.has_cell(c) or map.has_wall(c) \
				or not map.ground_is_walkable(map.get_cell_atlas_coords(0, c)):
			return false
	return true


func _is_prefix(map: TileMap, cell: Vector2i, prefix: String) -> bool:
	var name := _name_at(map, 1, cell)
	return name.begins_with(prefix) and name != "WALL_POST"


func _name_at(map: TileMap, layer: int, cell: Vector2i) -> String:
	if map.get_cell_source_id(layer, cell) == -1:
		return ""
	var atlas: Vector2i = map.get_cell_atlas_coords(layer, cell)
	for n in TileCatalog.TILES:
		if TileCatalog.TILES[n]["atlas"] == atlas and (n.begins_with("WALL_") or n.begins_with("PALISADE_") \
				or n.begins_with("TOWER_STONE_") or n.begins_with("CAP_COLLAR_") or n.begins_with("PROP_FLAG_")):
			return n
	return ""
