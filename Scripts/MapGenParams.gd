class_name MapGenParams
extends Resource
## Tunable map-generation parameters. Defaults match the previous hardcoded behaviour.

# Seeds (0 means "pick a random seed when applied", matching prior randi() behaviour)
@export var altitude_seed: int = 0
@export var moisture_seed: int = 0
@export var temperature_seed: int = 0
@export var items_seed: int = 0

# FastNoiseLite — engine defaults except items frequency which was hardcoded to 1
@export var noise_type: int = 1  # FastNoiseLite.TYPE_SIMPLEX_SMOOTH
@export var altitude_frequency: float = 0.01
@export var moisture_frequency: float = 0.01
@export var temperature_frequency: float = 0.01
@export var items_frequency: float = 1.0
@export var fractal_octaves: int = 5
@export var fractal_lacunarity: float = 2.0
@export var fractal_gain: float = 0.5

# Chunk generation size around the player
@export var chunk_width: int = 32
@export var chunk_height: int = 32

# Terrain altitude thresholds (layer 0)
@export var water_max_alt: float = 0.2
@export var sand_max_alt: float = 0.25
@export var swamp_special_alt: float = 0.26

# Ground tile variation breakpoints on the items-chance noise
@export var ground_chance_a: float = -0.25
@export var ground_chance_b: float = 0.25
@export var ground_chance_c: float = 0.75

# Foliage (layer 1)
@export var bush_min_alt: float = 0.3
@export var bush_max_alt: float = 0.4
@export var bush_min_chance: float = 0.0
@export var tree_min_alt: float = 0.4
@export var tree_min_chance: float = 0.3


static func make_defaults() -> MapGenParams:
	return MapGenParams.new()


func duplicate_params() -> MapGenParams:
	var copy = MapGenParams.new()
	copy.from_dict(to_dict())
	return copy


func randomize_seeds() -> void:
	altitude_seed = randi()
	moisture_seed = randi()
	temperature_seed = randi()
	items_seed = randi()


func ensure_seeds() -> void:
	## Replace any zero seed with a fresh random value (0 is the "unset" sentinel).
	if altitude_seed == 0:
		altitude_seed = randi()
	if moisture_seed == 0:
		moisture_seed = randi()
	if temperature_seed == 0:
		temperature_seed = randi()
	if items_seed == 0:
		items_seed = randi()


func to_dict() -> Dictionary:
	return {
		"altitude_seed": altitude_seed,
		"moisture_seed": moisture_seed,
		"temperature_seed": temperature_seed,
		"items_seed": items_seed,
		"noise_type": noise_type,
		"altitude_frequency": altitude_frequency,
		"moisture_frequency": moisture_frequency,
		"temperature_frequency": temperature_frequency,
		"items_frequency": items_frequency,
		"fractal_octaves": fractal_octaves,
		"fractal_lacunarity": fractal_lacunarity,
		"fractal_gain": fractal_gain,
		"chunk_width": chunk_width,
		"chunk_height": chunk_height,
		"water_max_alt": water_max_alt,
		"sand_max_alt": sand_max_alt,
		"swamp_special_alt": swamp_special_alt,
		"ground_chance_a": ground_chance_a,
		"ground_chance_b": ground_chance_b,
		"ground_chance_c": ground_chance_c,
		"bush_min_alt": bush_min_alt,
		"bush_max_alt": bush_max_alt,
		"bush_min_chance": bush_min_chance,
		"tree_min_alt": tree_min_alt,
		"tree_min_chance": tree_min_chance,
	}


func from_dict(data: Dictionary) -> void:
	for key in to_dict().keys():
		if data.has(key):
			set(key, data[key])
