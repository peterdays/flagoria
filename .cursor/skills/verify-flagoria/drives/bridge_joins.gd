extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 11
## Two shore-to-shore plank runs, then the second run removed and placed again
## (features/bridge-joins.md). Seed 11. The hero is moved only so the gap sits
## in frame; the planks go through build_bridge and erase_cells.

const SETTLE_FRAMES := 8


func run() -> void:
	step("separate")
	if not await start_game() or not await settle():
		done(false)
		return
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var minimap: MinimapPanel = current_scene.get_node_or_null("CanvasLayer1/MinimapPanel")
	if minimap != null:
		minimap.shown = false
		minimap.visible = false
	var gap := _shore_gap(map, Vector2i.RIGHT, [])
	if gap.is_empty():
		printerr("bridge_joins: no shore-to-shore water gap of 4 to 8 cells")
		done(false)
		return
	var first: Array[Vector2i] = [gap[0], gap[1], gap[2]]
	var rest: Array[Vector2i] = []
	for i in range(3, gap.size()):
		rest.append(gap[i])
	if not map.build_bridge(first[0], first[2]) or not _is_deck(map, first, true, false):
		printerr("bridge_joins: separate pieces %s" % _keys(map, first))
		done(false)
		return
	print("bridge_joins: gap %s separate %s" % [gap[0], _keys(map, first)])
	await _look(map, gap[gap.size() / 2], _beside_row())
	await snapshot("separate")

	step("joined")
	if not map.build_bridge(rest[0], rest[rest.size() - 1]) or not _is_deck(map, gap, true, true):
		printerr("bridge_joins: joined pieces %s" % _keys(map, gap))
		done(false)
		return
	print("bridge_joins: joined %s" % _keys(map, gap))
	await _look(map, gap[gap.size() / 2], _beside_row())
	await snapshot("joined")

	step("removed")
	if not map._bridges.erase_cells(rest) or not _is_deck(map, first, true, false):
		printerr("bridge_joins: removed pieces %s" % _keys(map, first))
		done(false)
		return
	for c in rest:
		if map.has_bridge(c) or map.get_cell_atlas_coords(0, c) != TileCatalog.WATER:
			printerr("bridge_joins: removed %s stayed %s bridge %s" % [c, map.get_cell_atlas_coords(0, c), map.has_bridge(c)])
			done(false)
			return
	print("bridge_joins: removed %s" % _keys(map, first))
	await _look(map, gap[gap.size() / 2], _beside_row())
	await snapshot("removed")

	step("rejoined")
	if not map.build_bridge(rest[0], rest[rest.size() - 1]) or not _is_deck(map, gap, true, true):
		printerr("bridge_joins: rejoined pieces %s" % _keys(map, gap))
		done(false)
		return
	print("bridge_joins: rejoined %s" % _keys(map, gap))
	await _look(map, gap[gap.size() / 2], _beside_row())
	await snapshot("rejoined")

	step("vertical-separate")
	var column := _column_gap(map, Vector2i.DOWN, gap)
	if column.is_empty():
		printerr("bridge_joins: no north-south shore gap of 4 to 8 cells")
		done(false)
		return
	var vfirst: Array[Vector2i] = [column[0], column[1], column[2]]
	var vrest: Array[Vector2i] = []
	for i in range(3, column.size()):
		vrest.append(column[i])
	if not map.build_bridge(vfirst[0], vfirst[2]) or not _is_deck(map, vfirst, false, false):
		printerr("bridge_joins: vertical separate pieces %s" % _keys(map, vfirst))
		done(false)
		return
	print("bridge_joins: vertical gap %s separate %s" % [column[0], _keys(map, vfirst)])
	await _look(map, column[column.size() / 2], _beside_column())
	await snapshot("vertical-separate")

	step("vertical-joined")
	var v_land_after := _land(map, column[column.size() - 1] + Vector2i.DOWN)
	if not map.build_bridge(vrest[0], vrest[vrest.size() - 1]) or not _is_deck(map, column, false, v_land_after):
		printerr("bridge_joins: vertical joined pieces %s" % _keys(map, column))
		done(false)
		return
	print("bridge_joins: vertical joined %s" % _keys(map, column))
	await _look(map, column[column.size() / 2], _beside_column())
	await snapshot("vertical-joined")

	step("vertical-removed")
	if not map._bridges.erase_cells(vrest) or not _is_deck(map, vfirst, false, false):
		printerr("bridge_joins: vertical removed pieces %s erase failed or deck changed" % _keys(map, vfirst))
		done(false)
		return
	for c in vrest:
		if map.has_bridge(c) or map.get_cell_atlas_coords(0, c) != TileCatalog.WATER:
			printerr("bridge_joins: vertical removed %s stayed %s bridge %s" % [c, map.get_cell_atlas_coords(0, c), map.has_bridge(c)])
			done(false)
			return
	print("bridge_joins: vertical removed %s" % _keys(map, vfirst))
	await _look(map, column[column.size() / 2], _beside_column())
	await snapshot("vertical-removed")

	step("vertical-rejoined")
	if not map.build_bridge(vrest[0], vrest[vrest.size() - 1]) or not _is_deck(map, column, false, v_land_after):
		printerr("bridge_joins: vertical rejoined pieces %s" % _keys(map, column))
		done(false)
		return
	print("bridge_joins: vertical rejoined %s" % _keys(map, column))
	await _look(map, column[column.size() / 2], _beside_column())
	await snapshot("vertical-rejoined")
	done(true)


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
	printerr("bridge_joins: hero did not settle")
	return false


func _beside_row() -> Array:
	return [Vector2i(0, -2), Vector2i(0, -3), Vector2i(0, 2), Vector2i(0, 3), Vector2i(-3, -2), Vector2i(3, -2)]


func _beside_column() -> Array:
	return [Vector2i(2, 0), Vector2i(3, 0), Vector2i(-2, 0), Vector2i(-3, 0), Vector2i(2, -2), Vector2i(-2, 2)]


func _look(map: TileMap, cell: Vector2i, deltas: Array) -> void:
	## Stand on land beside the gap so the deck is in frame and not under the hero.
	var spot := cell
	for delta in deltas:
		var c: Vector2i = cell + delta
		if map.get_cell_source_id(0, c) != -1 and map.is_walkable_land(c) and not map.has_bridge(c):
			spot = c
			break
	var player := hero()
	if player != null:
		player.global_position = map.to_global(map.map_to_local(spot))
	for _i in SETTLE_FRAMES:
		await process_frame


func _shore_gap(map: TileMap, step: Vector2i, avoid: Array) -> Array[Vector2i]:
	var found := _search_gap(map, step, avoid)
	if not found.is_empty():
		return found
	for y in range(-2, 3):
		for x in range(-2, 3):
			map.generate_chunk(Vector2(x * map.chunk_width, y * map.chunk_height))
	return _search_gap(map, step, avoid)


func _search_gap(map: TileMap, step: Vector2i, avoid: Array) -> Array[Vector2i]:
	var blocked := {}
	for c in avoid:
		blocked[c] = true
	var best: Array[Vector2i] = []
	for cell in map.get_used_cells(0):
		if not _land(map, cell):
			continue
		var run: Array[Vector2i] = []
		var hits_avoid := false
		for i in range(1, 9):
			var w: Vector2i = cell + step * i
			if blocked.has(w):
				hits_avoid = true
				break
			if map.get_cell_source_id(0, w) == -1 or map.predict_cell(w)[0] != TileCatalog.WATER \
					or map.has_bridge(w):
				break
			run.append(w)
		if hits_avoid or run.size() < 4 or not _land(map, cell + step * (run.size() + 1)):
			continue
		if map.get_cell_source_id(0, cell + step * (run.size() + 1)) == -1:
			continue
		if best.is_empty() or run.size() < best.size():
			best = run
			if best.size() == 4:
				break
	return best


func _column_gap(map: TileMap, step: Vector2i, avoid: Array) -> Array[Vector2i]:
	## North-south (or along step) water leaving land. Land on the far side is
	## preferred; a run that ends on open water is still a column, and its end
	## piece is a tip.
	var found := _search_column(map, step, avoid)
	if not found.is_empty():
		return found
	for y in range(-2, 3):
		for x in range(-2, 3):
			map.generate_chunk(Vector2(x * map.chunk_width, y * map.chunk_height))
	return _search_column(map, step, avoid)


func _search_column(map: TileMap, step: Vector2i, avoid: Array) -> Array[Vector2i]:
	var blocked := {}
	for c in avoid:
		blocked[c] = true
	var best: Array[Vector2i] = []
	var best_landed := false
	for cell in map.get_used_cells(0):
		if not _land(map, cell) or blocked.has(cell):
			continue
		var run: Array[Vector2i] = []
		var stopped := false
		for i in range(1, 9):
			var w: Vector2i = cell + step * i
			if blocked.has(w) or map.get_cell_source_id(0, w) == -1 \
					or map.predict_cell(w)[0] != TileCatalog.WATER or map.has_bridge(w):
				stopped = true
				break
			run.append(w)
		if run.size() < 4:
			continue
		var far: Vector2i = run[run.size() - 1] + step
		if map.get_cell_source_id(0, far) == -1 or blocked.has(far) or (stopped and blocked.has(far)):
			continue
		var landed := _land(map, far)
		if best.is_empty() or (landed and not best_landed) or (landed == best_landed and run.size() < best.size()):
			best = run
			best_landed = landed
			if best_landed and best.size() == 4:
				break
	return best


func _land(map: TileMap, cell: Vector2i) -> bool:
	return map.get_cell_source_id(0, cell) != -1 and not map.has_bridge(cell) \
			and map.ground_is_walkable(map.predict_cell(cell)[0])


func _is_deck(map: TileMap, cells: Array[Vector2i], horizontal: bool, land_after: bool) -> bool:
	var keys := _keys(map, cells)
	var want := _want(cells.size(), horizontal, land_after)
	return keys == want


func _want(n: int, horizontal: bool, land_after: bool) -> PackedStringArray:
	## Open-water end is TIP_ (unfinished planks). Shore rope is START/END only.
	var axis := "H" if horizontal else "V"
	var tip := "H_TIP_E" if horizontal else "V_TIP_S"
	var out := PackedStringArray()
	for i in n:
		var key := axis
		if i == 0:
			key = axis + "_START"
		elif i == n - 1 and land_after:
			key = axis + "_END"
		elif i == n - 1:
			key = tip
		out.append(key)
	return out


func _keys(map: TileMap, cells: Array[Vector2i]) -> PackedStringArray:
	var out := PackedStringArray()
	for c in cells:
		out.append(_key(map, c))
	return out


func _key(map: TileMap, cell: Vector2i) -> String:
	if not map.has_bridge(cell):
		return ""
	var atlas: Vector2i = map.get_cell_atlas_coords(0, cell)
	for tile_name: String in TileCatalog.TILES:
		if tile_name.begins_with("BRIDGE_PLANK_") and tile_name.ends_with("_WATER") \
				and TileCatalog.TILES[tile_name]["atlas"] == atlas:
			return tile_name.trim_prefix("BRIDGE_PLANK_").trim_suffix("_WATER")
	return ""
