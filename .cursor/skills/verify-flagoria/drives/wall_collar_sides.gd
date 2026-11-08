extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 11
## Three and four stone sides each draw a collar. Remove and replace the palisade.
## Landscape: 1280x720, then 854x480.

const SETTLE_FRAMES := 8


func run() -> void:
	step("three")
	if not await start_game() or not await settle():
		done(false)
		return
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var minimap: MinimapPanel = current_scene.get_node_or_null("CanvasLayer1/MinimapPanel")
	if minimap != null:
		minimap.shown = false
		minimap.visible = false
	print("wall_collar_sides: window %s" % DisplayServer.window_get_size())
	var tower: Structure = StructurePlacer.load_named("tower_wood")
	var found: Variant = _collar_plus(map, tower)
	if found == null:
		map.apply_map_params(_open_params())
		map.generate_chunk(Vector2(0, 0))
		found = _collar_plus(map, tower)
	if found == null:
		printerr("wall_collar_sides: no clear plus")
		done(false)
		return
	var p: Vector2i = found[0]
	var anchors: Array = found[1]
	for i in 3:
		if map.place_structure(tower, anchors[i], 1) <= 0:
			printerr("wall_collar_sides: tower %s refused" % i)
			done(false)
			return
	var cells: Array[Vector2i] = [p]
	if not map.place_wall_cells(cells):
		printerr("wall_collar_sides: palisade refused")
		done(false)
		return
	var three: Array = ["CAP_COLLAR_N", "CAP_COLLAR_E", "CAP_COLLAR_W"]
	if map._walls.cap_names(p) != three or not _layers(map, p, three):
		printerr("wall_collar_sides: three caps %s" % map._walls.cap_names(p))
		done(false)
		return
	await _look(map, p + Vector2i(5, 4))
	await snapshot("three")

	step("four")
	if map.place_structure(tower, anchors[3], 1) <= 0:
		printerr("wall_collar_sides: south tower refused")
		done(false)
		return
	var four: Array = ["CAP_COLLAR_N", "CAP_COLLAR_E", "CAP_COLLAR_S", "CAP_COLLAR_W"]
	if map._walls.cap_names(p) != four or not _layers(map, p, four):
		printerr("wall_collar_sides: four caps %s" % map._walls.cap_names(p))
		done(false)
		return
	await _look(map, p + Vector2i(5, 4))
	await snapshot("four")

	step("removed")
	if not map._walls.erase_cells(cells) or not map._walls.cap_names(p).is_empty() or not _layers(map, p, []):
		printerr("wall_collar_sides: collars stayed after remove")
		done(false)
		return
	await _look(map, p + Vector2i(5, 4))
	await snapshot("removed")

	step("readded")
	if not map.place_wall_cells(cells) or map._walls.cap_names(p) != four or not _layers(map, p, four):
		printerr("wall_collar_sides: readd %s" % map._walls.cap_names(p))
		done(false)
		return
	await _look(map, p + Vector2i(5, 4))
	await snapshot("readded")

	step("constrained")
	if not await _resize(854, 480):
		done(false)
		return
	await _look(map, p + Vector2i(5, 4))
	await snapshot("constrained")
	done(true)


func _open_params() -> MapGenParams:
	var params := MapGenParams.new()
	params.altitude_seed = 11
	params.moisture_seed = 12
	params.temperature_seed = 13
	params.items_seed = 14
	params.biome_seed = 15
	params.biome_frequency = 0.0
	params.tree_min_chance = 0.85
	params.bush_min_chance = 0.85
	params.pine_min_chance = 0.85
	return params


func _layers(map: TileMap, cell: Vector2i, caps: Array) -> bool:
	for i in WallBuilder.CAP_LAYERS.size():
		var want: String = caps[i] if i < caps.size() else ""
		if _name_at(map, WallBuilder.CAP_LAYERS[i], cell) != want:
			return false
	return true


func _collar_plus(map: TileMap, tower: Structure) -> Variant:
	for cell: Vector2i in map.get_used_cells(0):
		if not map.predicted_clear(cell):
			continue
		var anchors: Array[Vector2i] = [
			cell + Vector2i(-1, -1), cell + Vector2i(2, 0), cell + Vector2i(-2, 2), cell + Vector2i(1, 3),
		]
		var seen := {}
		var ok := true
		for a in anchors:
			for c in StructurePlacer.footprint(tower, a).keys():
				if seen.has(c) or c == cell or map.get_cell_source_id(0, c) == -1 or not map.predicted_clear(c):
					ok = false
					break
				seen[c] = true
			if not ok:
				break
		if ok:
			return [cell, anchors]
	return null


func _name_at(map: TileMap, layer: int, cell: Vector2i) -> String:
	if map.get_cell_source_id(layer, cell) == -1:
		return ""
	var atlas: Vector2i = map.get_cell_atlas_coords(layer, cell)
	for n in TileCatalog.TILES:
		if TileCatalog.TILES[n]["atlas"] == atlas and n.begins_with("CAP_COLLAR_"):
			return n
	return ""


func _look(map: TileMap, cell: Vector2i) -> void:
	var player := hero()
	if player != null:
		player.global_position = map.to_global(map.map_to_local(cell))
	for i in SETTLE_FRAMES:
		await process_frame


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
	printerr("wall_collar_sides: hero did not settle")
	return false


func _resize(width: int, height: int) -> bool:
	root.size = Vector2i(width, height)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(width, height))
	for i in 10:
		await process_frame
	var got := DisplayServer.window_get_size()
	print("wall_collar_sides: window %s (asked %dx%d)" % [got, width, height])
	if got.x != width or got.y != height:
		printerr("wall_collar_sides: window stayed %s" % got)
		return false
	return true
