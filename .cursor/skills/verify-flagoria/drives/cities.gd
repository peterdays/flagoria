extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 11
## Closed wall loop → city (#277, features/cities.md). Seed 11. Proof from
## snapshots: castle city tint at start, a wooden tower + free-form ring that
## closes, the same ring after a gap dissolves the city, and the minimap
## painting remaining city walls. Minimap closed for play shots.

const SETTLE_FRAMES := 10


func run() -> void:
	step("start")
	if not await start_game() or not await settle():
		done(false)
		return
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var cities: Cities = current_scene.get_node("World/Cities")
	var inventory: Inventory = current_scene.get_node(INVENTORY)
	inventory.add(Inventory.WOOD, 80)
	var minimap: MinimapPanel = current_scene.get_node_or_null("CanvasLayer1/MinimapPanel")
	if minimap != null:
		minimap.shown = false
		minimap.visible = false
	# Castle courtyard is a city once Cities has ticked.
	cities.rebuild()
	await snapshot("start")
	if cities.cities.is_empty():
		printerr("cities: start castle did not form a city")
		done(false)
		return
	print("cities: start cities=%s" % [cities.cities.keys()])

	step("closed")
	var origin = _find_clear(map, Vector2i(5, 5))
	if origin == null:
		for off in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
				Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			map.generate_chunk(off)
		origin = _find_clear(map, Vector2i(5, 5))
	if origin == null:
		printerr("cities: no 5x5 clear near spawn")
		done(false)
		return
	var o: Vector2i = origin
	var tower: Structure = StructurePlacer.load_named("tower_wood")
	var id: int = map.place_structure(tower, o + Vector2i(2, 3), 1)
	if id <= 0:
		printerr("cities: tower_wood place failed at %s" % [o])
		done(false)
		return
	var ring: Array[Vector2i] = _perimeter(o, o + Vector2i(4, 4))
	if not map.place_wall_cells(ring):
		printerr("cities: ring place failed")
		done(false)
		return
	cities.rebuild()
	if not cities.cities.has(id):
		printerr("cities: closed ring did not make a city for %s; have %s" % [id, cities.cities.keys()])
		done(false)
		return
	# Pan camera toward the new city if possible.
	var player = current_scene.get_node_or_null("World/player")
	if player == null:
		player = current_scene.get_node_or_null("World/1")
	if player != null:
		player.global_position = map.to_global(map.map_to_local(o + Vector2i(2, 2)))
	for i in 8:
		await process_frame
	await snapshot("closed")
	print("cities: closed city %s walls=%d" % [id, cities.cities[id]["walls"].size()])

	step("open")
	var gap: Array[Vector2i] = [o + Vector2i(2, 0)]
	if not map._walls.erase_cells(gap):
		printerr("cities: erase gap failed")
		done(false)
		return
	cities.rebuild()
	if cities.cities.has(id):
		printerr("cities: city remained after gap")
		done(false)
		return
	for i in 8:
		await process_frame
	await snapshot("open")
	print("cities: dissolved; remaining=%s" % [cities.cities.keys()])

	step("minimap")
	if minimap != null:
		minimap.shown = true
		minimap.visible = true
		minimap.tick()
		for i in 8:
			await process_frame
	await snapshot("minimap")
	done(true)


func _find_clear(map: TileMap, size: Vector2i) -> Variant:
	## Prefer a clear rect near the player; fall back to any clear rect.
	var player: Node2D = current_scene.get_node_or_null("World/1")
	var origin := Vector2i.ZERO
	if player != null:
		origin = map.local_to_map(map.to_local(player.global_position))
	var best: Variant = null
	var best_d := 1 << 30
	for cell: Vector2i in map.get_used_cells(0):
		var ok := true
		for y in size.y:
			for x in size.x:
				var c := cell + Vector2i(x, y)
				if map.get_cell_source_id(0, c) == -1 or not map.predicted_clear(c) \
						or map.has_wall(c) or map._structures.has_cell(c):
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		var d: int = absi(cell.x - origin.x) + absi(cell.y - origin.y)
		if d < best_d:
			best_d = d
			best = cell
	return best


func _perimeter(lo: Vector2i, hi: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(lo.x, hi.x + 1):
		out.append(Vector2i(x, lo.y))
		out.append(Vector2i(x, hi.y))
	for y in range(lo.y + 1, hi.y):
		out.append(Vector2i(lo.x, y))
		out.append(Vector2i(hi.x, y))
	return out


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
	printerr("cities: hero did not settle")
	return false

