class_name BiomeCatalog
extends RefCounted
## Large-scale biome ids with hardcoded per-biome island density, altitude
## bias, ground terrain table, plant table and structure table. Every table
## applies only when biomes are on.

const OCEANIC := 0
const TEMPERATE := 1
const CONTINENTAL := 2
const ARCHIPELAGO_DENSE := 3

## Fraction of archipelago squares kept when biomes are on (count unlimited).
const DENSITY := {
	OCEANIC: 0.2,
	TEMPERATE: 1.0,
	CONTINENTAL: 1.0,
	ARCHIPELAGO_DENSE: 1.0,
}

## Added to altitude in generate_chunk when biomes are on (continuous path).
const ALTITUDE_BIAS := {
	OCEANIC: -0.15,
	TEMPERATE: 0.0,
	CONTINENTAL: 0.1,
	ARCHIPELAGO_DENSE: 0.05,
}

## Per-biome ground mix (layer 0 and ground decorations). TEMPERATE is the
## identity row, so it matches the terrain with biomes off.
## sand_band: added to sand_max_alt and swamp_special_alt (beach width).
## swamp_moisture: land with moisture below this is swamp (0 with biomes off).
## flower_chance: added to flower_min_chance (higher = fewer flowers).
const TERRAIN := {
	OCEANIC: {"sand_band": 0.08, "swamp_moisture": -0.25, "flower_chance": 0.3},
	TEMPERATE: {"sand_band": 0.0, "swamp_moisture": 0.0, "flower_chance": 0.0},
	CONTINENTAL: {"sand_band": -0.02, "swamp_moisture": -0.25, "flower_chance": -0.2},
	ARCHIPELAGO_DENSE: {"sand_band": 0.04, "swamp_moisture": 0.2, "flower_chance": 0.0},
}

## Per-biome plant density (layer 1 foliage). TEMPERATE is the identity row,
## so it matches the plants with biomes off. Higher = fewer plants.
## tree_chance: added to tree_min_chance.
## bush_chance: added to bush_min_chance.
const PLANTS := {
	OCEANIC: {"tree_chance": 0.3, "bush_chance": 0.2},
	TEMPERATE: {"tree_chance": 0.0, "bush_chance": 0.0},
	CONTINENTAL: {"tree_chance": -0.25, "bush_chance": 0.0},
	ARCHIPELAGO_DENSE: {"tree_chance": 0.15, "bush_chance": -0.25},
}

## Per-biome structures: walkable stones on GROUND_DECOR_LAYER. A walkable land
## cell without a plant (beaches included) gets stones where the items chance
## is above stone_chance. Values above 1 mean never; TEMPERATE has none, so it
## still matches the map with biomes off.
const STRUCTURES := {
	OCEANIC: {"stone_chance": 0.3},
	TEMPERATE: {"stone_chance": 2.0},
	CONTINENTAL: {"stone_chance": 0.35},
	ARCHIPELAGO_DENSE: {"stone_chance": 2.0},
}


static func from_noise(value: float) -> int:
	## Map FastNoiseLite output in roughly [-1, 1] to a biome id.
	if value < -0.5:
		return OCEANIC
	if value < 0.0:
		return TEMPERATE
	if value < 0.5:
		return CONTINENTAL
	return ARCHIPELAGO_DENSE


static func density(biome_id: int) -> float:
	return float(DENSITY.get(biome_id, 1.0))


static func altitude_bias(biome_id: int) -> float:
	return float(ALTITUDE_BIAS.get(biome_id, 0.0))


static func terrain(biome_id: int, key: String) -> float:
	## One TERRAIN value; unknown biomes fall back to the TEMPERATE row.
	var row: Dictionary = TERRAIN.get(biome_id, TERRAIN[TEMPERATE])
	return float(row[key])


static func plants(biome_id: int, key: String) -> float:
	## One PLANTS value; unknown biomes fall back to the TEMPERATE row.
	var row: Dictionary = PLANTS.get(biome_id, PLANTS[TEMPERATE])
	return float(row[key])


static func structures(biome_id: int, key: String) -> float:
	## One STRUCTURES value; unknown biomes fall back to the TEMPERATE row.
	var row: Dictionary = STRUCTURES.get(biome_id, STRUCTURES[TEMPERATE])
	return float(row[key])
