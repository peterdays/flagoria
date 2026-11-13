extends "res://tests/helpers/test_helpers.gd"
## Junctions on the map: corners, both collars, tower flag, a far flip, cap cleanup, save load.

const NOTCH := [
	"#######....", "#..#..#....", "#..#..#####", "#.........#", "#.........#", "####.######",
]

func _test_wall_junctions() -> int:
	## Time cost: about 1 s in tools/verify.sh (~2.4 s alone with --only).
	print("-- test_wall_junctions")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var params := _spawn_params(11, 0.0)
	world.apply_map_params(params)
	world.generate_chunk(Vector2(0, 0))
	if world.get_layers_count() < 7 or world.get_layer_z_index(WallBuilder.CAP_LAYER) <= 1 \
			or world.get_layer_z_index(WallBuilder.CAP_LAYER_2) <= world.get_layer_z_index(WallBuilder.CAP_LAYER) \
			or world.get_layer_z_index(WallBuilder.CAP_LAYER_4) <= world.get_layer_z_index(WallBuilder.CAP_LAYER_3):
		printerr("FAIL wall_junctions: cap layers missing or under the walls")
		fail += 1
	fail += _gate_outline()
	fail += _caps_have_no_collision(world)
	if not world.place_start_castle(1):
		printerr("FAIL wall_junctions: no starting castle on seed 11")
		scene.queue_free()
		return 1
	var castle: Dictionary = world.placed_structures()
	var castle_anchor: Vector2i = castle[castle.keys()[0]]["anchor"]
	fail += _expect_prefix(world, castle_anchor + Vector2i(-3, -4), "WALL_CORNER_OUT_", "castle corner")
	var post := StructurePlacer.load_named("guard_post")
	var post_at: Variant = _clear_anchor(world, post)
	if post_at == null or world.place_structure(post, post_at, 1) <= 0:
		printerr("FAIL wall_junctions: no guard_post on seed 11")
		scene.queue_free()
		return 1
	fail += _expect_prefix(world, post_at + Vector2i(-2, -3), "WALL_CORNER_OUT_", "guard_post corner")
	var tower := StructurePlacer.load_named("tower_wood")
	var pair: Variant = _tower_pair(world, tower)
	if pair == null:
		printerr("FAIL wall_junctions: no pair of towers with a gap")
		scene.queue_free()
		return 1
	var a: Vector2i = pair[0]
	var gap: Vector2i = pair[1]
	if world.place_structure(tower, a, 1) <= 0 or world.place_structure(tower, a + Vector2i(4, 0), 1) <= 0:
		printerr("FAIL wall_junctions: tower place failed at %s" % a)
		scene.queue_free()
		return 1
	var flag: Vector2i = a + Vector2i(0, -1)
	if world.predict_cell(flag)[1] != TileCatalog.PROP_FLAG_BLUE:
		printerr("FAIL wall_junctions: tower centre %s is not the team flag" % flag)
		fail += 1
	var gap_cells: Array[Vector2i] = [gap]
	if not world.place_wall_cells(gap_cells):
		printerr("FAIL wall_junctions: gap palisade refused")
		fail += 1
	else:
		var caps: Array = world._walls.cap_names(gap)
		if world._walls.piece(gap) != TileCatalog.PALISADE_H or caps != ["CAP_COLLAR_E", "CAP_COLLAR_W"]:
			printerr("FAIL wall_junctions: gap piece %s caps %s" % [world._walls.piece(gap), caps])
			fail += 1
		fail += _cap_layers(world, gap, caps, "two collars")
		if not _tile_name(world, 1, a + Vector2i(1, -1)).begins_with("TOWER_STONE_E_E") \
				or not _tile_name(world, 1, a + Vector2i(3, -1)).begins_with("TOWER_STONE_W_W"):
			printerr("FAIL wall_junctions: tower arms %s %s" % [
				_tile_name(world, 1, a + Vector2i(1, -1)), _tile_name(world, 1, a + Vector2i(3, -1))])
			fail += 1
	var straight := a + Vector2i(0, -3)
	var bend := a + Vector2i(-2, -1)
	var tee := a + Vector2i(4, -3)
	var cross := a + Vector2i(4, 1)
	var shapes: Array[Vector2i] = [straight, straight + Vector2i(0, -1), bend, bend + Vector2i(0, 1),
		tee, tee + Vector2i(1, 0), tee + Vector2i(-1, 0), cross, cross + Vector2i(1, 0),
		cross + Vector2i(-1, 0), cross + Vector2i(0, 1)]
	if not _land(world, shapes) or not world.place_wall_cells(shapes):
		printerr("FAIL wall_junctions: join shapes do not fit at %s" % shapes)
		fail += 1
	else:
		var want := {
			straight: ["PALISADE_V", ["CAP_COLLAR_S"]],
			bend: ["PALISADE_CORNER_OUT_NW", ["CAP_COLLAR_E"]],
			tee: ["PALISADE_T_N", ["CAP_COLLAR_S"]],
			cross: ["PALISADE_CROSS", ["CAP_COLLAR_N"]],
		}
		for cell in want:
			var got := _name_of(world._walls.piece(cell))
			if got != want[cell][0] or world._walls.cap_names(cell) != want[cell][1]:
				printerr("FAIL wall_junctions: %s is %s caps %s, want %s" % [cell, got, world._walls.cap_names(cell), want[cell]])
				fail += 1
	var origin: Variant = _find_rect(world, Vector2i(11, 6))
	if origin == null:
		printerr("FAIL wall_junctions: no 11x6 land for the notch")
		fail += 1
	else:
		var o: Vector2i = origin
		var cells: Array[Vector2i] = []
		for y in NOTCH.size():
			for x in NOTCH[y].length():
				if NOTCH[y][x] == "#":
					cells.append(o + Vector2i(x, y))
		var corner: Vector2i = o + Vector2i(6, 2)
		var closing: Vector2i = o + Vector2i(4, 5)
		if absi(corner.x - closing.x) + absi(corner.y - closing.y) <= 1 or not world.place_wall_cells(cells):
			printerr("FAIL wall_junctions: notch place failed")
			fail += 1
		else:
			var open_piece: Vector2i = world._walls.piece(corner)
			var close_cells: Array[Vector2i] = [closing]
			if not world.place_wall_cells(close_cells):
				printerr("FAIL wall_junctions: closing cell refused")
				fail += 1
			elif world._walls.piece(corner) == open_piece or not _name_of(world._walls.piece(corner)).begins_with("PALISADE_CORNER_IN_"):
				printerr("FAIL wall_junctions: far corner stayed %s" % _name_of(world._walls.piece(corner)))
				fail += 1
			elif not world._walls.erase_cells(close_cells) or world._walls.piece(corner) != open_piece:
				printerr("FAIL wall_junctions: far corner did not flip back")
				fail += 1
			else:
				world.place_wall_cells(close_cells)
	if not world._walls.erase_cells(gap_cells) or not world._walls.cap_names(gap).is_empty() \
			or world.get_cell_source_id(WallBuilder.CAP_LAYER, gap) != -1 \
			or world.get_cell_source_id(WallBuilder.CAP_LAYER_2, gap) != -1:
		printerr("FAIL wall_junctions: caps stayed after remove")
		fail += 1
	elif _tile_name(world, 1, a + Vector2i(1, -1)) != "TOWER_STONE_E_X":
		printerr("FAIL wall_junctions: tower arm stayed after the palisade left")
		fail += 1
	world.place_wall_cells(gap_cells)
	var before := _sample(world, [gap, flag, castle_anchor + Vector2i(-3, -4), post_at + Vector2i(-2, -3)])
	var changes := StructureSaves.to_changes(world)
	world.apply_map_params(params)
	if StructureSaves.restore(changes, world) <= 0:
		printerr("FAIL wall_junctions: restore wrote nothing")
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	var after := _sample(world, before.keys())
	if str(after) != str(before):
		printerr("FAIL wall_junctions: save load %s want %s" % [after, before])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_wall_junctions")
	return fail


func _test_wall_collar_sides() -> int:
	## Three stone sides draw three collars and four draw four, in N,E,S,W
	## order. Removing the palisade clears every cap layer; placing it again
	## brings them back. One- and two-side cells are unchanged. Time cost:
	## about 0.5 s in tools/verify.sh.
	print("-- test_wall_collar_sides")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var tower := StructurePlacer.load_named("tower_wood")
	var found: Variant = null
	for seed_value in [11, 42, 99, 7, 1, 3]:
		var params := _spawn_params(seed_value, 0.0)
		params.tree_min_chance = 0.85
		params.bush_min_chance = 0.85
		params.pine_min_chance = 0.85
		world.apply_map_params(params)
		world.generate_chunk(Vector2(0, 0))
		found = _collar_plus(world, tower)
		if found != null:
			break
	if found == null:
		printerr("FAIL wall_collar_sides: no clear plus of four towers")
		scene.queue_free()
		return 1
	var p: Vector2i = found[0]
	var anchors: Array = found[1]
	for i in 3:
		if world.place_structure(tower, anchors[i], 1) <= 0:
			printerr("FAIL wall_collar_sides: tower %s refused at %s" % [i, anchors[i]])
			scene.queue_free()
			return 1
	var cells: Array[Vector2i] = [p]
	if not world.place_wall_cells(cells):
		printerr("FAIL wall_collar_sides: palisade refused at %s" % p)
		scene.queue_free()
		return 1
	var three: Array = ["CAP_COLLAR_N", "CAP_COLLAR_E", "CAP_COLLAR_W"]
	if world._walls.cap_names(p) != three or _name_of(world._walls.piece(p)) != "PALISADE_T_S":
		printerr("FAIL wall_collar_sides: three sides %s piece %s" % [world._walls.cap_names(p), _name_of(world._walls.piece(p))])
		fail += 1
	fail += _cap_layers(world, p, three, "three collars")
	if world.place_structure(tower, anchors[3], 1) <= 0:
		printerr("FAIL wall_collar_sides: south tower refused")
		fail += 1
	else:
		var four: Array = ["CAP_COLLAR_N", "CAP_COLLAR_E", "CAP_COLLAR_S", "CAP_COLLAR_W"]
		if world._walls.cap_names(p) != four or _name_of(world._walls.piece(p)) != "PALISADE_CROSS":
			printerr("FAIL wall_collar_sides: four sides %s piece %s" % [world._walls.cap_names(p), _name_of(world._walls.piece(p))])
			fail += 1
		fail += _cap_layers(world, p, four, "four collars")
		if not world._walls.erase_cells(cells):
			printerr("FAIL wall_collar_sides: remove failed")
			fail += 1
		else:
			fail += _cap_layers(world, p, [], "cleared")
			if not world.place_wall_cells(cells) or world._walls.cap_names(p) != four:
				printerr("FAIL wall_collar_sides: readd %s" % world._walls.cap_names(p))
				fail += 1
			fail += _cap_layers(world, p, four, "readded")
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_wall_collar_sides")
	return fail

func _gate_outline() -> int:
	var tex := load("res://art/flagoria/flagoria_tiles_v4.png") as Texture2D
	var img := tex.get_image() if tex != null else null
	if img == null:
		printerr("FAIL wall_junctions: atlas did not load")
		return 1
	for cell in [Vector2i(20, 2), Vector2i(21, 2)]:
		for x in range(6, 10):
			var p := img.get_pixel(cell.x * 16 + x, cell.y * 16 + 14)
			if p.r8 != 0x2a or p.g8 != 0x22 or p.b8 != 0x38:
				printerr("FAIL wall_junctions: gate %s pixel %s is %s" % [cell, x, p])
				return 1
	return 0

func _caps_have_no_collision(world) -> int:
	var src: TileSetAtlasSource = world.tile_set.get_source(TileCatalog.SOURCE_ID)
	for n in ["CAP_COLLAR_N", "CAP_COLLAR_E", "CAP_COLLAR_S", "CAP_COLLAR_W"]:
		if src.get_tile_data(TileCatalog.TILES[n]["atlas"], 0).get_collision_polygons_count(0) != 0:
			printerr("FAIL wall_junctions: %s has collision" % n)
			return 1
	var body := src.get_tile_data(TileCatalog.TILES["TOWER_STONE_N_X"]["atlas"], 0)
	if body.get_collision_polygons_count(0) == 0:
		printerr("FAIL wall_junctions: tower ring has no collision")
		return 1
	return 0

func _clear_anchor(world, structure: Structure) -> Variant:
	for cell: Vector2i in world.get_used_cells(0):
		var cells: Array = StructurePlacer.footprint(structure, cell).keys()
		if cells.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
			return cell
	return null

func _tower_pair(world, tower: Structure) -> Variant:
	for cell: Vector2i in world.get_used_cells(0):
		var gap: Vector2i = cell + Vector2i(2, -1)
		var both: Array = StructurePlacer.footprint(tower, cell).keys()
		both.append_array(StructurePlacer.footprint(tower, cell + Vector2i(4, 0)).keys())
		var extra: Array[Vector2i] = [cell + Vector2i(0, -3), cell + Vector2i(0, -4),
			cell + Vector2i(-2, -1), cell + Vector2i(-2, 0), cell + Vector2i(4, -3),
			cell + Vector2i(3, -3), cell + Vector2i(5, -3), cell + Vector2i(4, 1),
			cell + Vector2i(3, 1), cell + Vector2i(5, 1), cell + Vector2i(4, 2)]
		if both.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)) \
				and world.predicted_clear(gap) and _land(world, extra):
			return [cell, gap]
	return null

func _find_rect(world, size: Vector2i) -> Variant:
	for origin: Vector2i in world.get_used_cells(0):
		if _land(world, _rect_cells(origin, size)):
			return origin
	return null

func _rect_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells

func _land(world, cells: Array) -> bool:
	for c in cells:
		if world.get_cell_source_id(0, c) == -1 or world._structures.has_cell(c) or world.has_wall(c) \
				or not world.ground_is_walkable(world.get_cell_atlas_coords(0, c)):
			return false
	return true

func _expect_prefix(world, cell: Vector2i, prefix: String, label: String) -> int:
	var name := _tile_name(world, 1, cell)
	if not name.begins_with(prefix) or name == "WALL_POST":
		printerr("FAIL wall_junctions: %s %s is %s" % [label, cell, name])
		return 1
	return 0

func _cap_layers(world, cell: Vector2i, caps: Array, label: String) -> int:
	var drawn: Array[String] = []
	var want: Array[String] = []
	for i in WallBuilder.CAP_LAYERS.size():
		drawn.append(_tile_name(world, WallBuilder.CAP_LAYERS[i], cell))
		want.append(caps[i] if i < caps.size() else "")
	if drawn != want:
		printerr("FAIL wall_junctions: %s drew %s, want %s" % [label, drawn, want])
		return 1
	return 0

func _tile_name(world, layer: int, cell: Vector2i) -> String:
	if world.get_cell_source_id(layer, cell) == -1:
		return ""
	return _name_of(world.get_cell_atlas_coords(layer, cell))

func _name_of(atlas: Vector2i) -> String:
	for n in TileCatalog.TILES:
		if TileCatalog.TILES[n]["atlas"] == atlas and (n.begins_with("WALL_") or n.begins_with("PALISADE_") \
				or n.begins_with("TOWER_STONE_") or n.begins_with("CAP_COLLAR_") or n.begins_with("PROP_FLAG_")):
			return n
	return str(atlas)

func _collar_plus(world, tower: Structure) -> Variant:
	## Palisade cell plus tower anchors N, E, W, S whose corner cells touch it.
	for p: Vector2i in world.get_used_cells(0):
		if not world.predicted_clear(p):
			continue
		var anchors: Array[Vector2i] = [
			p + Vector2i(-1, -1), p + Vector2i(2, 0), p + Vector2i(-2, 2), p + Vector2i(1, 3),
		]
		var seen := {}
		var ok := true
		for a in anchors:
			var foot: Array = StructurePlacer.footprint(tower, a).keys()
			for c in foot:
				if seen.has(c) or c == p or world.get_cell_source_id(0, c) == -1 or not world.predicted_clear(c):
					ok = false
					break
				seen[c] = true
			if not ok:
				break
		if ok:
			return [p, anchors]
	return null


func _sample(world, cells: Array) -> Dictionary:
	var out := {}
	for c in cells:
		out[c] = [world.predict_cell(c)[1], world._walls.cap_names(c) if world.has_wall(c) else []]
	return out
