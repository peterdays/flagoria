class_name BiomeCatalog
extends RefCounted
## Large-scale biome ids and hardcoded density / altitude bias for the first
## biome-map step. Per-biome terrain tables come in later work.

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
