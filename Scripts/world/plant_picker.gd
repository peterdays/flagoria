class_name PlantPicker
extends RefCounted
## Which plant or stones one walkable cell gets, from its altitude, moisture,
## chance and biome. Moved from Scripts/TileMap.gd, which keeps wrappers with
## the same names (plant_tile, structure_tile) and passes itself as `map` for
## the Map Settings values.

const _WorldMap := preload("res://Scripts/TileMap.gd")
## MapGenParams fields the picker reads from `map`; TileMap.apply_map_params copies them.
const PARAMS := [
	"bush_min_alt", "bush_max_alt", "bush_min_chance", "tree_min_alt", "tree_min_chance",
	"flower_min_alt", "flower_max_alt", "flower_min_chance", "pine_min_alt", "pine_min_moist",
	"pine_min_chance", "bushy_tree_min_moist", "swamp_bush_min_chance", "birch_min_chance",
]


static func plant_tile(map: _WorldMap, alt: float, moist: float, chance: float, biome_id: int = BiomeCatalog.TEMPERATE) -> Vector2i:
	## Bush, tree, bushy tree, pine or flower for one walkable cell, or NO_PLANT. With biomes
	## on, BiomeCatalog.PLANTS shifts the tree, bush, pine, bushy tree and swamp scrub
	## thresholds and BiomeCatalog.TERRAIN the flower one; off, no pines, bushy trees or
	## swamp scrub, Map Settings apply.
	var bush_chance := map.bush_min_chance
	var tree_chance := map.tree_min_chance
	var flower_chance := map.flower_min_chance
	if map.biome_frequency > 0.0:
		bush_chance += BiomeCatalog.plants(biome_id, "bush_chance")
		tree_chance += BiomeCatalog.plants(biome_id, "tree_chance")
		flower_chance += BiomeCatalog.terrain(biome_id, "flower_chance")
	if moist > 0 and alt > map.bush_min_alt and alt <= map.bush_max_alt and chance > bush_chance:
		return TileCatalog.BUSH
	if moist > 0 and alt > map.tree_min_alt and chance > tree_chance:
		if map.biome_frequency > 0.0 and moist > map.bushy_tree_min_moist + BiomeCatalog.plants(biome_id, "bushy_moist"):
			return TileCatalog.TREE_BUSHY
		return TileCatalog.TREE
	if map.biome_frequency > 0.0 and moist <= 0 and alt > map.pine_min_alt:
		# Dry high ground; the moisture floor never goes below the biome's
		# swamp threshold, so pines stay off swamp.
		var pine_moist := maxf(map.pine_min_moist, BiomeCatalog.terrain(biome_id, "swamp_moisture"))
		if moist > pine_moist and chance > map.pine_min_chance + BiomeCatalog.plants(biome_id, "pine_chance"):
			return TileCatalog.PINE
	if map.biome_frequency > 0.0 and moist < BiomeCatalog.terrain(biome_id, "swamp_moisture"):
		# Swamp scrub: callers skip sand, so walkable land this wet is swamp.
		if chance > map.swamp_bush_min_chance + BiomeCatalog.plants(biome_id, "swamp_bush_chance"):
			return TileCatalog.BUSH
	if moist > 0 and alt > map.flower_min_alt and alt <= map.flower_max_alt and chance > flower_chance:
		return TileCatalog.FLOWER
	return _WorldMap.NO_PLANT


static func structure_tile(map: _WorldMap, chance: float, biome_id: int = BiomeCatalog.TEMPERATE) -> Vector2i:
	## Stones for one walkable cell with no plant, or NO_PLANT. Only with biomes on
	## (BiomeCatalog.STRUCTURES sets the chance per biome); off, the map is unchanged.
	if map.biome_frequency <= 0.0:
		return _WorldMap.NO_PLANT
	if chance > BiomeCatalog.structures(biome_id, "stone_chance"):
		return TileCatalog.STONES
	return _WorldMap.NO_PLANT
