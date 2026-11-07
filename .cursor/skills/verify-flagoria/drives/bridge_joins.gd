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
	var gap := _shore_gap(map)
	if gap.is_empty():
		printerr("bridge_joins: no shore-to-shore water gap of 4 to 8 cells")
		done(false)
		return
	var first: Array[Vector2i] = [gap[0], gap[1], gap[2]]
	var rest: Array[Vector2i] = []
	for i in range(3, gap.size()):
		rest.append(gap[i])
	if not map.build_bridge(first[0], first[2]) or not _is_deck(map, first, false):
		printerr("bridge_joins: separate pieces %s" % _keys(map, first))
		done(false)
		return
	print("bridge_joins: gap %s separate %s" % [gap[0], _keys(map, first)])
	await _look(map, gap[gap.size() / 2])
	await snapshot("separate")

	step("joined")
	if not map.build_bridge(rest[0], rest[rest.size() - 1]) or not _is_deck(map, gap, true):
		printerr("bridge_joins: joined pieces %s" % _keys(map, gap))
		done(false)
		return
	print("bridge_joins: joined %s" % _keys(map, gap))
	await _look(map, gap[gap.size() / 2])
	await snapshot("joined")

	step("removed")
	if not map._bridges.erase_cells(rest) or not _is_deck(map, first, false):
		printerr("bridge_joins: removed pieces %s" % _keys(map, first))
		done(false)
		return
	for c in rest:
		if map.has_bridge(c) or map.get_cell_atlas_coords(0, c) != TileCatalog.WATER:
			printerr("bridge_joins: removed %s stayed %s bridge %s" % [c, map.get_cell_atlas_coords(0, c), map.has_bridge(c)])
			done(false)
			return
	print("bridge_joins: removed %s" % _keys(map, first))
	await _look(map, gap[gap.size() / 2])
	await snapshot("removed")

	step("rejoined")
	if not map.build_bridge(rest[0], rest[rest.size() - 1]) or not _is_deck(map, gap, true):
		printerr("bridge_joins: rejoined pieces %s" % _keys(map, gap))
		done(false)
		return
	print("bridge_joins: rejoined %s" % _keys(map, gap))
	await _look(map, gap[gap.size() / 2])
	await snapshot("rejoined")
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


func _look(map: TileMap, cell: Vector2i) -> void:
	## Stand on land beside the gap so the deck is in frame and not under the hero.
	var spot := cell
	for delta in [Vector2i(0, -2), Vector2i(0, -3), Vector2i(0, 2), Vector2i(0, 3), Vector2i(-3, -2), Vector2i(3, -2)]:
		var c: Vector2i = cell + delta
		if map.get_cell_source_id(0, c) != -1 and map.is_walkable_land(c) and not map.has_bridge(c):
			spot = c
			break
	var player := hero()
	if player != null:
		player.global_position = map.to_global(map.map_to_local(spot))
	for _i in SETTLE_FRAMES:
		await process_frame


func _shore_gap(map: TileMap) -> Array[Vector2i]:
	var found := _search_gap(map)
	if not found.is_empty():
		return found
	for y in range(-2, 3):
		for x in range(-2, 3):
			map.generate_chunk(Vector2(x * map.chunk_width, y * map.chunk_height))
	return _search_gap(map)


func _search_gap(map: TileMap) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for cell in map.get_used_cells(0):
		if not _land(map, cell):
			continue
		var run: Array[Vector2i] = []
		for i in range(1, 9):
			var w: Vector2i = cell + Vector2i(i, 0)
			if map.get_cell_source_id(0, w) == -1 or map.predict_cell(w)[0] != TileCatalog.WATER \
					or map.has_bridge(w):
				break
			run.append(w)
		if run.size() < 4 or not _land(map, cell + Vector2i(run.size() + 1, 0)):
			continue
		if map.get_cell_source_id(0, cell + Vector2i(run.size() + 1, 0)) == -1:
			continue
		if best.is_empty() or run.size() < best.size():
			best = run
			if best.size() == 4:
				break
	return best


func _land(map: TileMap, cell: Vector2i) -> bool:
	return map.get_cell_source_id(0, cell) != -1 and not map.has_bridge(cell) \
			and map.ground_is_walkable(map.predict_cell(cell)[0])


func _is_deck(map: TileMap, cells: Array[Vector2i], land_after: bool) -> bool:
	var keys := _keys(map, cells)
	var want := _want(cells.size(), land_after)
	return keys == want


func _want(n: int, land_after: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for i in n:
		var key := "H"
		if i == 0:
			key = "H_START"
		elif i == n - 1 and land_after:
			key = "H_END"
		elif i == n - 1:
			key = "H_TIP_E"
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
