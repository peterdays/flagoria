extends "res://tests/helpers/test_helpers.gd"
## Atlas v4 structure finals: v3 pixels unchanged, catalog coords, placement and collisions.


func _test_structure_final_tiles() -> int:
	## Time cost: about 0.3 s in tools/verify.sh (~0.8 s alone with --only).
	print("-- test_structure_final_tiles")
	var fail := 0
	fail += _v3_pixels_unchanged_in_v4()
	fail += _pre_v4_catalog_coords_unchanged()
	fail += _placement_pieces_in_tileset()
	fail += _write_structure_render()
	if fail == 0:
		print("PASS test_structure_final_tiles")
	return fail


func _v3_pixels_unchanged_in_v4() -> int:
	var v3_path := ProjectSettings.globalize_path("res://tests/golden/flagoria_tiles_v3_atlas.png")
	var v4_path := ProjectSettings.globalize_path("res://art/flagoria/flagoria_tiles_v4.png")
	var v3 := Image.load_from_file(v3_path)
	var v4 := Image.load_from_file(v4_path)
	if v3 == null or v4 == null:
		printerr("FAIL structure_final_tiles: atlas did not load")
		return 1
	if v4.get_size() != v3.get_size():
		printerr("FAIL structure_final_tiles: atlas size %s != %s" % [v4.get_size(), v3.get_size()])
		return 1
	var cols := v4.get_width() / 16
	var rows := v4.get_height() / 16
	var fail := 0
	for cy in rows:
		for cx in cols:
			var ox := cx * 16
			var oy := cy * 16
			var used := false
			for y in 16:
				for x in 16:
					if v3.get_pixel(ox + x, oy + y).a > 0.0:
						used = true
						break
				if used:
					break
			if not used:
				continue
			for y in 16:
				for x in 16:
					var p3 := v3.get_pixel(ox + x, oy + y)
					var p4 := v4.get_pixel(ox + x, oy + y)
					if p3 != p4:
						printerr("FAIL structure_final_tiles: cell (%d,%d) pixel (%d,%d) changed" % [cx, cy, x, y])
						fail += 1
						if fail >= 5:
							return fail
	return fail


func _pre_v4_catalog_coords_unchanged() -> int:
	var raw := FileAccess.get_file_as_string("res://tests/golden/tile_catalog_atlas_v3.json")
	var want: Dictionary = JSON.parse_string(raw)
	var fail := 0
	for n in want:
		if not TileCatalog.TILES.has(n):
			printerr("FAIL structure_final_tiles: catalog lost %s" % n)
			fail += 1
			continue
		var a: Vector2i = TileCatalog.TILES[n]["atlas"]
		var parts: PackedStringArray = want[n].split(",")
		var expect := Vector2i(int(parts[0]), int(parts[1]))
		if a != expect:
			printerr("FAIL structure_final_tiles: %s atlas %s, want %s" % [n, a, expect])
			fail += 1
	return fail


func _placement_pieces_in_tileset() -> int:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://docs/art/structures-final/placement.json"))
	var pieces: Array = data["pieces"]
	var tile_set: TileSet = load("res://art/flagoria/flagoria_tiles_v3.tres")
	var src: TileSetAtlasSource = tile_set.get_source(TileCatalog.SOURCE_ID)
	var structs := {}
	var fail := 0
	for piece in pieces:
		var name: String = piece["name"]
		structs[piece["struct"]] = true
		if not TileCatalog.TILES.has(name):
			printerr("FAIL structure_final_tiles: %s missing from catalog" % name)
			fail += 1
			continue
		var atlas: Vector2i = TileCatalog.TILES[name]["atlas"]
		var want_atlas := Vector2i(piece["atlas"][0], piece["atlas"][1])
		if atlas != want_atlas:
			printerr("FAIL structure_final_tiles: %s atlas %s, spec %s" % [name, atlas, want_atlas])
			fail += 1
		if not src.has_tile(atlas):
			printerr("FAIL structure_final_tiles: %s not in TileSet" % name)
			fail += 1
			continue
		fail += _collision_matches(src, atlas, piece.get("collision"))
	var team_bases := {}
	for piece in pieces:
		if piece.get("team") in ["BLUE", "RED"]:
			var n: String = piece["name"]
			var base := n.trim_suffix("_BLUE").trim_suffix("_RED")
			team_bases[base] = team_bases.get(base, 0) + 1
	for base in team_bases:
		if not TileCatalog.TILES.has(base + "_BLUE") or not TileCatalog.TILES.has(base + "_RED"):
			printerr("FAIL structure_final_tiles: %s missing _BLUE/_RED pair" % base)
			fail += 1
	for s in ["archer_post", "neutral_outpost", "barracks", "respawn_camp", "trading_post",
			"lumber_mill", "watchtower", "sky_dock"]:
		if not structs.has(s):
			printerr("FAIL structure_final_tiles: no pieces for %s" % s)
			fail += 1
	return fail


func _collision_matches(src: TileSetAtlasSource, atlas: Vector2i, collision) -> int:
	var td: TileData = src.get_tile_data(atlas, 0)
	var count := td.get_collision_polygons_count(0)
	if collision == null or (collision is Array and collision.is_empty()):
		if count != 0:
			printerr("FAIL structure_final_tiles: %s should have no collision" % atlas)
			return 1
		return 0
	if count != collision.size():
		printerr("FAIL structure_final_tiles: %s polygon count %d, want %d" % [atlas, count, collision.size()])
		return 1
	for i in collision.size():
		var rect: Array = collision[i]
		var want := _rect_polygon(rect)
		var got := td.get_collision_polygon_points(0, i)
		if got.size() != want.size():
			printerr("FAIL structure_final_tiles: %s poly %d point count" % [atlas, i])
			return 1
		for j in want.size():
			if got[j].distance_to(want[j]) > 0.01:
				printerr("FAIL structure_final_tiles: %s poly %d point %d got %s want %s" % [atlas, i, j, got[j], want[j]])
				return 1
	return 0


func _rect_polygon(rect: Array) -> PackedVector2Array:
	var x1: float = rect[0]
	var y1: float = rect[1]
	var x2: float = rect[2]
	var y2: float = rect[3]
	return PackedVector2Array([
		Vector2(x1, y1), Vector2(x2, y1), Vector2(x2, y2), Vector2(x1, y2),
	])


func _write_structure_render() -> int:
	var tile_set: TileSet = load("res://art/flagoria/flagoria_tiles_v3.tres")
	var src: TileSetAtlasSource = tile_set.get_source(TileCatalog.SOURCE_ID)
	var atlas: Image = src.texture.get_image()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://docs/art/structures-final/placement.json"))
	var by_struct: Dictionary = {}
	for piece in data["pieces"]:
		var s: String = piece["struct"]
		if not by_struct.has(s):
			by_struct[s] = []
		by_struct[s].append(piece)
	var col := 0
	var row_h := 1
	for s in ["archer_post", "neutral_outpost", "barracks", "respawn_camp", "trading_post",
			"lumber_mill", "watchtower", "sky_dock"]:
		var items: Array = by_struct.get(s, [])
		var ox := col * 20
		var oy := 0
		var max_dy := 0
		for piece in items:
			var off = piece.get("offset")
			var at := Vector2i(ox, oy)
			if off is Array and off.size() == 2:
				at += Vector2i(off[0], off[1])
			max_dy = maxi(max_dy, at.y - oy)
			var name: String = piece["name"]
			if not TileCatalog.TILES.has(name):
				continue
			var cell: Vector2i = TileCatalog.TILES[name]["atlas"]
			if not src.has_tile(cell):
				printerr("FAIL structure_final_tiles: render missing %s" % name)
				return 1
		col += 1
		row_h = maxi(row_h, max_dy + 1)
	var sheet := Image.create(col * 20 * 16 + 16, row_h * 16 + 16, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	col = 0
	for s in ["archer_post", "neutral_outpost", "barracks", "respawn_camp", "trading_post",
			"lumber_mill", "watchtower", "sky_dock"]:
		var items: Array = by_struct.get(s, [])
		var ox := col * 20
		var oy := 0
		for piece in items:
			var off = piece.get("offset")
			var at := Vector2i(ox, oy)
			if off is Array and off.size() == 2:
				at += Vector2i(off[0], off[1])
			var name: String = piece["name"]
			if not TileCatalog.TILES.has(name):
				continue
			var cell: Vector2i = TileCatalog.TILES[name]["atlas"]
			var patch := atlas.get_region(Rect2i(cell.x * 16, cell.y * 16, 16, 16))
			sheet.blit_rect(patch, Rect2i(0, 0, 16, 16), Vector2i(at.x * 16 + 8, at.y * 16 + 8))
		col += 1
	var out := "res://docs/screenshots/structure_finals_tileset.png"
	sheet.save_png(out)
	var golden := "res://tests/golden/structure_finals_tileset.png"
	if not FileAccess.file_exists(golden):
		sheet.save_png(golden)
	elif sheet.get_data() != Image.load_from_file(golden).get_data():
		printerr("FAIL structure_final_tiles: render differs from tests/golden/structure_finals_tileset.png")
		return 1
	return 0
