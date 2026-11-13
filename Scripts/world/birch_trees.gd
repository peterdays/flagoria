class_name BirchTrees
extends RefCounted
## Two-cell birch trees on CONTINENTAL broadleaf land (biomes on only). The
## bottom cell blocks like TREE; the top draws on layer 1 one tile north with
## no collision. TileMap calls these helpers from set_tile_type_z1 and
## predict_cell; TreeCuts clears the top when the bottom is chopped.

const _WorldMap := preload("res://Scripts/TileMap.gd")
const BOTTOM := TileCatalog.TREE_BIRCH_BOTTOM
const TOP := TileCatalog.TREE_BIRCH_TOP
const NORTH := Vector2i(0, -1)


static func top_cell(bottom: Vector2i) -> Vector2i:
	return bottom + NORTH


static func bottom_would_grow(map: _WorldMap, cell: Vector2i, alt: float, moist: float, chance: float, biome_id: int) -> bool:
	## True when plant_tile would be a plain oak here and the birch chance band
	## passes (before top-cell placement rules).
	if map.biome_frequency <= 0.0:
		return false
	var tree_chance := map.tree_min_chance + BiomeCatalog.plants(biome_id, "tree_chance")
	if not (moist > 0 and alt > map.tree_min_alt and chance > tree_chance):
		return false
	if moist > map.bushy_tree_min_moist + BiomeCatalog.plants(biome_id, "bushy_moist"):
		return false
	return chance > map.birch_min_chance + BiomeCatalog.plants(biome_id, "birch_chance")


static func top_can_hold(map: _WorldMap, top: Vector2i) -> bool:
	## Walkable land above a birch bottom with no other layer-1 plant there in
	## the generated map (flowers and stones on decor still allowed).
	var ground: Vector2i
	if map.get_cell_source_id(0, top) != -1:
		ground = map.get_cell_atlas_coords(0, top)
	else:
		var b := map.biome_at(top)
		var alt := map.cell_altitude(top, b)
		var moist := map.moisture.get_noise_2d(top.x, top.y)
		var chance := map.items_chance.get_noise_2d(top.x, top.y)
		ground = map.ground_tile(alt, moist, chance, b)
	if not map.ground_is_walkable(ground):
		return false
	if map.biome_frequency > 0.0 and ground == TileCatalog.SAND:
		return false
	var b := map.biome_at(top)
	var alt := map.cell_altitude(top, b)
	var moist := map.moisture.get_noise_2d(top.x, top.y)
	var chance := map.items_chance.get_noise_2d(top.x, top.y)
	return PlantPicker.plant_tile(map, alt, moist, chance, b) == _WorldMap.NO_PLANT


static func bottom_can_place(map: _WorldMap, bottom: Vector2i) -> bool:
	return top_can_hold(map, top_cell(bottom))


static func canopy_for(map: _WorldMap, cell: Vector2i) -> Vector2i:
	## BIRCH_TOP when the cell below would grow a birch bottom that fits, else NO_PLANT.
	var below := cell - NORTH
	if not bottom_would_grow(map, below,
			map.cell_altitude(below, map.biome_at(below)),
			map.moisture.get_noise_2d(below.x, below.y),
			map.items_chance.get_noise_2d(below.x, below.y),
			map.biome_at(below)):
		return _WorldMap.NO_PLANT
	return TOP if bottom_can_place(map, below) else _WorldMap.NO_PLANT


static func paint_top(map: _WorldMap, bottom: Vector2i) -> void:
	var top := top_cell(bottom)
	map.erase_cell(1, top)
	map.set_cell(1, top, TileCatalog.SOURCE_ID, TOP)


static func clear_top(map: _WorldMap, bottom: Vector2i) -> void:
	var top := top_cell(bottom)
	map.erase_cell(1, top)
	map.erase_cell(map.GROUND_DECOR_LAYER, top)
	map._predict_cache.erase(top)


static func is_tree_tile(atlas: Vector2i) -> bool:
	return atlas == BOTTOM


static func foliage_tile(map: _WorldMap, cell: Vector2i, alt: float, moist: float, chance: float, biome_id: int, beach: bool) -> Vector2i:
	## Layer-1 plant from noise before sprouts and stones; birch canopy wins first.
	var canopy := canopy_for(map, cell)
	if canopy != _WorldMap.NO_PLANT:
		return canopy
	if map.biome_frequency <= 0.0 or not beach:
		var tile := PlantPicker.plant_tile(map, alt, moist, chance, biome_id)
		if tile == TileCatalog.TREE and bottom_would_grow(map, cell, alt, moist, chance, biome_id) \
				and bottom_can_place(map, cell):
			return BOTTOM
		return tile
	return _WorldMap.NO_PLANT


static func paint_bottom(map: _WorldMap, bottom: Vector2i) -> void:
	map.set_cell(1, bottom, TileCatalog.SOURCE_ID, BOTTOM)
	paint_top(map, bottom)
