extends "res://tests/helpers/test_helpers.gd"
## Building-block socket compatibility and adjacency symmetry (#23).


func _test_building_block_sockets() -> int:
	## Time cost: under 0.2 s in tools/verify.sh.
	print("-- test_building_block_sockets")
	var fail := 0
	fail += _every_piece_has_tile_or_empty()
	fail += _catalog_tile_names()
	fail += _socket_partners_exist()
	fail += _compatibility_symmetric()
	fail += _adjacency_symmetric()
	fail += _write_debug_screenshot()
	if fail == 0:
		print("PASS test_building_block_sockets")
	return fail


func _every_piece_has_tile_or_empty() -> int:
	var want := {
		"empty": "",
		"floor": "GRASS_D",
		"wall_straight": "WALL_H",
		"wall_corner": "WALL_CORNER_OUT_NW",
		"door": "WALL_GATE_H_OPEN",
		"window": "WALL_H_DMG_CRACK",
		"roof_edge": "SKY_DOCK_N_END",
		"roof_fill": "SKY_DOCK_N_ROOT",
	}
	var fail := 0
	for id in want:
		var piece := BuildingBlockCatalog.by_id(id)
		if piece == null:
			printerr("FAIL building_block_sockets: missing piece %s" % id)
			fail += 1
			continue
		if piece.tile_name != want[id]:
			printerr("FAIL building_block_sockets: %s tile %s, want %s" % [id, piece.tile_name, want[id]])
			fail += 1
	return fail


func _catalog_tile_names() -> int:
	var fail := 0
	for piece: BuildingBlockPiece in BuildingBlockCatalog.all():
		if piece.tile_name == "":
			continue
		if not TileCatalog.TILES.has(piece.tile_name):
			printerr("FAIL building_block_sockets: %s unknown tile %s" % [piece.id, piece.tile_name])
			fail += 1
	return fail


func _all_socket_labels() -> Array[String]:
	var seen := {}
	for piece: BuildingBlockPiece in BuildingBlockCatalog.all():
		for side: String in BuildingBlockCatalog.SIDES:
			seen[piece.socket(side)] = true
	var out: Array[String] = []
	for label in seen:
		out.append(label)
	return out


func _socket_partners_exist() -> int:
	var fail := 0
	for label: String in _all_socket_labels():
		if not BuildingBlockCatalog.SOCKET_COMPAT.has(label):
			printerr("FAIL building_block_sockets: socket %s not in SOCKET_COMPAT" % label)
			fail += 1
			continue
		var has_partner := false
		for other: String in _all_socket_labels():
			if other == label:
				continue
			if BuildingBlockCatalog.socket_compatible(label, other):
				has_partner = true
				break
		if not has_partner:
			printerr("FAIL building_block_sockets: socket %s has no compatible partner" % label)
			fail += 1
	return fail


func _compatibility_symmetric() -> int:
	var fail := 0
	for a: String in BuildingBlockCatalog.SOCKET_COMPAT:
		for b: String in BuildingBlockCatalog.SOCKET_COMPAT:
			var ab := BuildingBlockCatalog.socket_compatible(a, b)
			var ba := BuildingBlockCatalog.socket_compatible(b, a)
			if ab != ba:
				printerr("FAIL building_block_sockets: compat asymmetric %s / %s" % [a, b])
				fail += 1
	return fail


func _adjacency_symmetric() -> int:
	var table: Dictionary = BuildingBlockCatalog.adjacency_table()
	var fail := 0
	for piece_a: String in table:
		for side_a: String in BuildingBlockCatalog.SIDES:
			var opp: String = BuildingBlockCatalog.OPPOSITE[side_a]
			for piece_b: String in table[piece_a][side_a]:
				var back: Dictionary = table.get(piece_b, {}).get(opp, {})
				if not back.has(piece_a):
					printerr(
							"FAIL building_block_sockets: adjacency %s %s -> %s but not %s %s -> %s"
							% [piece_a, side_a, piece_b, piece_b, opp, piece_a]
					)
					fail += 1
	return fail


func _write_debug_screenshot() -> int:
	## Headless runs have no display; composite tiles and labels like structure finals.
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(
			"res://art/flagoria/flagoria_tiles_v4.png"))
	if atlas == null:
		printerr("FAIL building_block_sockets: atlas did not load")
		return 1
	var pieces: Array[BuildingBlockPiece] = BuildingBlockCatalog.all()
	const TILE := 16
	const CELL := 64
	const COLS := 4
	var sheet_w := COLS * CELL + 16
	var rows := int(ceilf(float(pieces.size()) / float(COLS)))
	var sheet_h := rows * CELL + 28
	var sheet := Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.14, 1))
	for i in pieces.size():
		var piece: BuildingBlockPiece = pieces[i]
		var col := i % COLS
		var row := i / COLS
		var ox := 8 + col * CELL
		var oy := 8 + row * CELL
		if piece.tile_name != "" and TileCatalog.TILES.has(piece.tile_name):
			var at: Vector2i = TileCatalog.TILES[piece.tile_name]["atlas"]
			var patch := atlas.get_region(Rect2i(at.x * TILE, at.y * TILE, TILE, TILE))
			sheet.blit_rect(patch, Rect2i(0, 0, TILE, TILE), Vector2i(ox + CELL / 2 - TILE / 2, oy + CELL / 2 - TILE / 2))
		_draw_socket_markers(sheet, piece, Vector2i(ox, oy), CELL)
	var out := OS.get_cache_dir().path_join("building_block_pieces_headless.png")
	if sheet.save_png(out) != OK:
		printerr("FAIL building_block_sockets: could not write headless preview")
		return 1
	return 0


func _draw_socket_markers(img: Image, piece: BuildingBlockPiece, origin: Vector2i, cell: int) -> void:
	var colors := {
		"void": Color(0.45, 0.45, 0.5),
		"floor": Color(0.35, 0.7, 0.35),
		"wall": Color(0.75, 0.7, 0.55),
		"door": Color(0.85, 0.55, 0.25),
		"window": Color(0.45, 0.7, 0.85),
		"roof": Color(0.55, 0.4, 0.3),
		"eave": Color(0.7, 0.5, 0.35),
	}
	var cx := origin.x + cell / 2
	var cy := origin.y + cell / 2
	for side: String in BuildingBlockCatalog.SIDES:
		var col: Color = colors.get(piece.socket(side), Color.WHITE)
		match side:
			"N":
				for x in range(cx - 10, cx + 10):
					for y in range(origin.y, origin.y + 3):
						img.set_pixel(x, y, col)
			"S":
				for x in range(cx - 10, cx + 10):
					for y in range(origin.y + cell - 3, origin.y + cell):
						img.set_pixel(x, y, col)
			"E":
				for y in range(cy - 10, cy + 10):
					for x in range(origin.x + cell - 3, origin.x + cell):
						img.set_pixel(x, y, col)
			"W":
				for y in range(cy - 10, cy + 10):
					for x in range(origin.x, origin.x + 3):
						img.set_pixel(x, y, col)