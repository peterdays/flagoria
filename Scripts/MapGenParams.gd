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
@export_range(0.001, 1.0, 0.001) var altitude_frequency: float = 0.01
@export_range(0.001, 1.0, 0.001) var moisture_frequency: float = 0.01
@export_range(0.001, 1.0, 0.001) var temperature_frequency: float = 0.01
@export_range(0.01, 4.0, 0.01) var items_frequency: float = 1.0
@export_range(1, 10) var fractal_octaves: int = 5
@export_range(0.1, 4.0, 0.1) var fractal_lacunarity: float = 2.0
@export_range(0.0, 2.0, 0.05) var fractal_gain: float = 0.5

# Chunk generation size around the player
@export_range(8, 128) var chunk_width: int = 32
@export_range(8, 128) var chunk_height: int = 32
# Frames between chunk regenerations around the local player
@export_range(1, 120) var chunk_refresh_frames: int = 15

# Terrain altitude thresholds (layer 0)
@export_range(-1.0, 1.0, 0.01) var water_max_alt: float = 0.2
@export_range(-1.0, 1.0, 0.01) var sand_max_alt: float = 0.25
@export_range(-1.0, 1.0, 0.01) var swamp_special_alt: float = 0.26
# Island shape: altitude is raised near the world origin and lowered past
# island_radius tiles, so land fades into sea. 0 radius turns it off.
@export_range(0, 512) var island_radius: int = 0
@export_range(0.0, 4.0, 0.05) var island_falloff: float = 1.0

# Ground tile variation breakpoints on the items-chance noise
@export_range(-1.0, 1.0, 0.05) var ground_chance_a: float = -0.25
@export_range(-1.0, 1.0, 0.05) var ground_chance_b: float = 0.25
@export_range(-1.0, 1.0, 0.05) var ground_chance_c: float = 0.75

# Foliage (layer 1)
@export_range(-1.0, 1.0, 0.01) var bush_min_alt: float = 0.3
@export_range(-1.0, 1.0, 0.01) var bush_max_alt: float = 0.4
@export_range(-1.0, 1.0, 0.05) var bush_min_chance: float = 0.0
@export_range(-1.0, 1.0, 0.01) var tree_min_alt: float = 0.4
@export_range(-1.0, 1.0, 0.05) var tree_min_chance: float = 0.3


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


func exported_properties() -> Array[Dictionary]:
	## Property-list entries for every @export variable, in declaration order.
	var props: Array[Dictionary] = []
	for prop in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["usage"] & PROPERTY_USAGE_EDITOR:
			props.append(prop)
	return props


func to_dict() -> Dictionary:
	var data := {}
	for prop in exported_properties():
		data[prop["name"]] = get(prop["name"])
	return data


func from_dict(data: Dictionary) -> void:
	for key in to_dict().keys():
		if data.has(key):
			set(key, data[key])
