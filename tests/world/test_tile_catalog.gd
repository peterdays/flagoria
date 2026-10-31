extends "res://tests/helpers/test_helpers.gd"
## Tile names (Scripts/tile_catalog.gd).


func _test_tile_catalog() -> int:
	## Every TileCatalog.<NAME> used in Scripts/ is in TileCatalog.TILES, every
	## entry exists in the world TileSet, and map scripts pass no raw atlas
	## coords to set_cell.
	print("-- test_tile_catalog")
	var fail := 0
	var used := {}
	var name_re := RegEx.create_from_string("TileCatalog\\.([A-Z][A-Z0-9_]*)")
	var raw_re := RegEx.create_from_string("set_cell\\([^\\n]*Vector2i\\(")
	for file in DirAccess.get_files_at("res://Scripts"):
		if not file.ends_with(".gd") or file == "tile_catalog.gd":
			continue
		var text := FileAccess.get_file_as_string("res://Scripts/" + file)
		for m in name_re.search_all(text):
			used[m.get_string(1)] = file
		if raw_re.search(text) != null:
			printerr("FAIL tile_catalog: raw atlas coords in set_cell in %s" % file)
			fail += 1
	if used.is_empty():
		printerr("FAIL tile_catalog: no TileCatalog names found in Scripts/")
		fail += 1
	for n in used:
		if n == "SOURCE_ID" or n == "TILES":
			continue
		if not TileCatalog.TILES.has(n):
			printerr("FAIL tile_catalog: %s used in %s is missing from TILES" % [n, used[n]])
			fail += 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	var tile_set: TileSet = scene.get_node("World/worldMap").tile_set
	for n in TileCatalog.TILES:
		var entry: Dictionary = TileCatalog.TILES[n]
		var src = tile_set.get_source(entry["source_id"]) if tile_set.has_source(entry["source_id"]) else null
		if not src is TileSetAtlasSource or not src.has_tile(entry["atlas"]):
			printerr("FAIL tile_catalog: %s %s not in TileSet source %s" % [n, entry["atlas"], entry["source_id"]])
			fail += 1
	## The map fill tiles keep their cells across tileset versions, so saved
	## maps and the pinned tests stay valid.
	var pinned := {
		"WATER": Vector2i(5, 6), "SAND": Vector2i(5, 4), "SWAMP": Vector2i(14, 7),
		"SWAMP_SPECIAL": Vector2i(27, 7), "GRASS_A": Vector2i(5, 0), "GRASS_B": Vector2i(5, 1),
		"GRASS_C": Vector2i(6, 0), "GRASS_D": Vector2i(6, 1), "BUSH": Vector2i(7, 3),
		"TREE": Vector2i(7, 0), "FLOWER": Vector2i(9, 3), "STONES": Vector2i(0, 7),
		"PINE": Vector2i(7, 2),
	}
	for n in pinned:
		if not TileCatalog.TILES.has(n) or TileCatalog.TILES[n]["atlas"] != pinned[n]:
			printerr("FAIL tile_catalog: %s moved from %s" % [n, pinned[n]])
			fail += 1
	## STONES reuses the small-rocks art cell and PINE the small pine on purpose.
	var aliases := {"STONES": "ROCK_FLOAT_S", "PINE": "TREE_PINE_SMALL"}
	var cells := {}
	for n in TileCatalog.TILES:
		var a: Vector2i = TileCatalog.TILES[n]["atlas"]
		if cells.has(a) and aliases.get(n, "") != cells[a] and aliases.get(cells[a], "") != n:
			printerr("FAIL tile_catalog: %s and %s share cell %s" % [cells[a], n, a])
			fail += 1
		cells[a] = n
	## Collision drives walkability: water blocks, ground fill does not.
	var src0: TileSetAtlasSource = tile_set.get_source(TileCatalog.SOURCE_ID)
	for n in ["WATER", "TREE", "BUSH", "PINE"]:
		if src0.get_tile_data(TileCatalog.TILES[n]["atlas"], 0).get_collision_polygons_count(0) == 0:
			printerr("FAIL tile_catalog: %s has no collision polygon" % n)
			fail += 1
	for n in ["SAND", "SWAMP", "SWAMP_SPECIAL", "GRASS_A", "GRASS_B", "GRASS_C", "GRASS_D", "FLOWER", "STONES"]:
		if src0.get_tile_data(TileCatalog.TILES[n]["atlas"], 0).get_collision_polygons_count(0) != 0:
			printerr("FAIL tile_catalog: %s should be walkable" % n)
			fail += 1
	## Plank bridges: 28 walkable cells, row 15/16 sky pieces and the same
	## pieces over water two rows down.
	var planks := 0
	for n in TileCatalog.TILES:
		if not n.begins_with("BRIDGE_PLANK_"):
			continue
		planks += 1
		var a: Vector2i = TileCatalog.TILES[n]["atlas"]
		if src0.get_tile_data(a, 0).get_collision_polygons_count(0) != 0:
			printerr("FAIL tile_catalog: %s should be walkable" % n)
			fail += 1
		if n.ends_with("_WATER") and TileCatalog.TILES.get(n.trim_suffix("_WATER"), {}).get("atlas") != a - Vector2i(0, 2):
			printerr("FAIL tile_catalog: %s is not two rows below its sky piece" % n)
			fail += 1
	if planks != 28:
		printerr("FAIL tile_catalog: expected 28 plank bridge pieces, got %d" % planks)
		fail += 1
	## Island terrain: one terrain set with every ISLAND_BLOB_ base piece in it.
	if tile_set.get_terrain_sets_count() <= TileCatalog.ISLAND_TERRAIN_SET \
			or tile_set.get_terrain_name(TileCatalog.ISLAND_TERRAIN_SET, TileCatalog.ISLAND_TERRAIN) != "Island":
		printerr("FAIL tile_catalog: no Island terrain in the world TileSet")
		fail += 1
	else:
		var bases := 0
		for n in TileCatalog.TILES:
			if not n.begins_with("ISLAND_BLOB_"):
				continue
			if not n.contains("_W"):
				bases += 1
			var td: TileData = src0.get_tile_data(TileCatalog.TILES[n]["atlas"], 0)
			if td.terrain_set != TileCatalog.ISLAND_TERRAIN_SET or td.terrain != TileCatalog.ISLAND_TERRAIN:
				printerr("FAIL tile_catalog: %s is not an Island terrain tile" % n)
				fail += 1
		if bases != 47:
			printerr("FAIL tile_catalog: expected 47 island blob pieces, got %d" % bases)
			fail += 1
	scene.free()
	if fail == 0:
		print("PASS test_tile_catalog")
	return fail
