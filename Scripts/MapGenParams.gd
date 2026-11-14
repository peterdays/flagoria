class_name MapGenParams
extends Resource
## Tunable map-generation parameters. Defaults match the previous hardcoded behaviour.

# Seeds (0 means "pick a random seed when applied", matching prior randi() behaviour)
@export var altitude_seed: int = 0
@export var moisture_seed: int = 0
@export var temperature_seed: int = 0
@export var items_seed: int = 0
@export var biome_seed: int = 0

# FastNoiseLite — engine defaults except items frequency which was hardcoded to 1
@export var noise_type: int = 1  # FastNoiseLite.TYPE_SIMPLEX_SMOOTH
@export_range(0.001, 1.0, 0.001) var altitude_frequency: float = 0.01
@export_range(0.001, 1.0, 0.001) var moisture_frequency: float = 0.01
@export_range(0.001, 1.0, 0.001) var temperature_frequency: float = 0.01
@export_range(0.01, 4.0, 0.01) var items_frequency: float = 1.0
# Large-scale biome regions, on by default for new worlds. 0 frequency turns
# biomes off (no density modulation); map saves without the field load as 0.
@export_range(0.0, 0.05, 0.0001) var biome_frequency: float = 0.003
# Biome noise cut-off: below -biome_edge is OCEANIC, from +biome_edge up is
# ARCHIPELAGO_DENSE. The biome noise stays within about +/-0.33 for 80 % of
# the world, so 0.2 gives each outer biome about a fifth of it; at the old
# 0.5 they covered under 2 % each. Map saves without the field load as 0.5.
@export_range(0.05, 1.0, 0.05) var biome_edge: float = 0.2
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
# Archipelago: one island per square of archipelago_spacing tiles, its centre
# moved by up to archipelago_jitter of half a square. Altitude is shaped
# around the nearest centre like island_radius, using
# archipelago_island_radius and island_falloff. 0 spacing turns it off.
# Optional world bound: archipelago_world_extent is half-width in tiles of the
# square around the origin that may hold islands (0 = unbounded grid).
# archipelago_island_count > 0 keeps that many squares, with or without an
# extent: the spawn square (0, 0) first, then the nearest to the origin. The
# other squares are sea. Count 0 keeps one island per square in the extent.
@export_range(0, 1024) var archipelago_spacing: int = 0
@export_range(1, 512) var archipelago_island_radius: int = 24
@export_range(0.0, 1.0, 0.05) var archipelago_jitter: float = 0.5
@export_range(0, 4096) var archipelago_world_extent: int = 0
@export_range(0, 256) var archipelago_island_count: int = 0

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
# Flowers (TileCatalog.FLOWER) on moist land in an altitude band just above the sand,
# below the bushes. Bushes and trees take precedence where bands overlap.
@export_range(-1.0, 1.0, 0.01) var flower_min_alt: float = 0.25
@export_range(-1.0, 1.0, 0.01) var flower_max_alt: float = 0.3
@export_range(-1.0, 1.0, 0.05) var flower_min_chance: float = 0.3
# Pines (TileCatalog.PINE) on dry high ground, where moisture is too low for
# trees: altitude above pine_min_alt, moisture in (pine_min_moist, 0] and
# chance above pine_min_chance. Biomes on only; BiomeCatalog.PLANTS shifts
# the chance per biome, and pines never grow on swamp.
@export_range(-1.0, 2.0, 0.01) var pine_min_alt: float = 0.5
@export_range(-1.0, 0.0, 0.01) var pine_min_moist: float = -0.25
@export_range(-1.0, 2.0, 0.05) var pine_min_chance: float = 0.3
# Bushy trees (TileCatalog.TREE_BUSHY): a tree cell turns into the bushy
# broadleaf variant where moisture is above bushy_tree_min_moist plus the
# biome's bushy_moist (BiomeCatalog.PLANTS). Biomes on only.
@export_range(0.0, 2.0, 0.05) var bushy_tree_min_moist: float = 0.3
# Swamp scrub (TileCatalog.BUSH on swamp): a swamp cell grows a bush where its
# chance is above swamp_bush_min_chance plus the biome's swamp_bush_chance
# (BiomeCatalog.PLANTS). Biomes on only.
@export_range(-1.0, 2.0, 0.05) var swamp_bush_min_chance: float = 0.3
# Birches (TileCatalog.TREE_BIRCH_BOTTOM/TOP): a plain tree cell in
# CONTINENTAL becomes a two-cell birch when chance is above birch_min_chance
# plus the biome's birch_chance (BiomeCatalog.PLANTS). Biomes on only.
@export_range(-1.0, 2.0, 0.05) var birch_min_chance: float = 0.55


## Playable ranges for Random specs (#335): narrower than @export_range where
## the editor limits allow broken maps (all water, no land, missing biomes).
## Keys match exported property names. Values are [min, max, step]. Seeds and
## noise_type are handled separately; chunk_width/height/refresh_frames are
## left alone. Ordered pairs (water/sand, foliage bands, ground chances) are
## enforced in randomize_specs().
const PLAYABLE_RANGES := {
	"altitude_frequency": [0.005, 0.02, 0.001],
	"moisture_frequency": [0.005, 0.02, 0.001],
	"temperature_frequency": [0.005, 0.02, 0.001],
	"items_frequency": [0.3, 2.0, 0.01],
	"biome_frequency": [0.002, 0.008, 0.0005],
	"biome_edge": [0.1, 0.25, 0.05],
	"fractal_octaves": [3, 7, 1],
	"fractal_lacunarity": [1.5, 2.5, 0.1],
	"fractal_gain": [0.3, 0.7, 0.05],
	"water_max_alt": [0.12, 0.26, 0.01],
	"sand_gap": [0.03, 0.1, 0.01],  ## sand_max_alt - water_max_alt
	"swamp_gap": [0.01, 0.05, 0.01],  ## swamp_special_alt - sand_max_alt
	"island_radius": [80, 200, 1],  ## used when shape mode is island; 0 means off
	"island_falloff": [0.5, 2.0, 0.05],
	"archipelago_spacing": [64, 160, 1],
	"archipelago_island_radius": [40, 64, 1],
	"archipelago_jitter": [0.2, 0.7, 0.05],
	"archipelago_world_extent": [256, 1024, 1],
	"archipelago_island_count": [3, 12, 1],
	"ground_chance_a": [-0.5, -0.1, 0.05],
	"ground_chance_span": [0.25, 0.5, 0.05],  ## gap a->b and b->c
	"bush_min_chance": [-0.2, 0.2, 0.05],
	"tree_min_chance": [0.1, 0.5, 0.05],
	"flower_min_chance": [0.1, 0.5, 0.05],
	"pine_min_alt": [0.4, 0.7, 0.01],
	"pine_min_moist": [-0.5, -0.1, 0.01],
	"pine_min_chance": [0.1, 0.5, 0.05],
	"bushy_tree_min_moist": [0.15, 0.5, 0.05],
	"swamp_bush_min_chance": [0.15, 0.5, 0.05],
	"birch_min_chance": [0.35, 0.75, 0.05],
	"foliage_band": [0.03, 0.08, 0.01],  ## height of flower then bush bands above sand
}

## Properties Random specs never changes (#335).
const RANDOM_SPECS_SKIP := ["chunk_width", "chunk_height", "chunk_refresh_frames"]


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
	biome_seed = randi()

func randomize_specs() -> void:
	## Set every map-gen property (except chunk_*) to a random value inside
	## PLAYABLE_RANGES, randomise seeds, and keep ordered thresholds in order
	## (#335). Shape mode is island or archipelago so the result stays playable.
	randomize_seeds()
	# Cellular (and Perlin) often stay in one biome band across a coverage
	# sample; keep continuous types that hit every biome for BIOME_COVERAGE_OK (#335).
	noise_type = [
		FastNoiseLite.TYPE_VALUE,
		FastNoiseLite.TYPE_VALUE_CUBIC,
		FastNoiseLite.TYPE_SIMPLEX,
		FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
	][randi() % 4]
	altitude_frequency = _rand_range("altitude_frequency")
	moisture_frequency = _rand_range("moisture_frequency")
	temperature_frequency = _rand_range("temperature_frequency")
	items_frequency = _rand_range("items_frequency")
	biome_frequency = _rand_range("biome_frequency")
	biome_edge = _rand_range("biome_edge")
	fractal_octaves = int(_rand_range("fractal_octaves"))
	fractal_lacunarity = _rand_range("fractal_lacunarity")
	fractal_gain = _rand_range("fractal_gain")
	water_max_alt = _rand_range("water_max_alt")
	sand_max_alt = water_max_alt + _rand_range("sand_gap")
	swamp_special_alt = sand_max_alt + _rand_range("swamp_gap")
	island_falloff = _rand_range("island_falloff")
	# Shape: island (most common) or archipelago — mutually exclusive. Open
	# (island_radius=0 and archipelago_spacing=0) is skipped: unlucky noise near
	# the origin can still be all water even with a capped water_max_alt (#335).
	var shape := 1 if randi() % 100 < 70 else 2
	island_radius = 0
	archipelago_spacing = 0
	archipelago_world_extent = 0
	archipelago_island_count = 0
	archipelago_island_radius = int(_rand_range("archipelago_island_radius"))
	archipelago_jitter = _rand_range("archipelago_jitter")
	if shape == 1:
		island_radius = int(_rand_range("island_radius"))
	else:
		archipelago_spacing = int(_rand_range("archipelago_spacing"))
		archipelago_island_radius = int(_rand_range("archipelago_island_radius"))
		archipelago_jitter = _rand_range("archipelago_jitter")
		# Half the time bound the world and pick a count.
		if randf() < 0.5:
			archipelago_world_extent = int(_rand_range("archipelago_world_extent"))
			archipelago_island_count = int(_rand_range("archipelago_island_count"))
	ground_chance_a = _rand_range("ground_chance_a")
	var span := _rand_range("ground_chance_span")
	ground_chance_b = ground_chance_a + span
	ground_chance_c = minf(0.95, ground_chance_b + span)
	var band := _rand_range("foliage_band")
	flower_min_alt = sand_max_alt
	flower_max_alt = flower_min_alt + band
	bush_min_alt = flower_max_alt
	bush_max_alt = bush_min_alt + band
	tree_min_alt = bush_min_alt
	bush_min_chance = _rand_range("bush_min_chance")
	tree_min_chance = _rand_range("tree_min_chance")
	flower_min_chance = _rand_range("flower_min_chance")
	pine_min_alt = _rand_range("pine_min_alt")
	pine_min_moist = _rand_range("pine_min_moist")
	pine_min_chance = _rand_range("pine_min_chance")
	bushy_tree_min_moist = _rand_range("bushy_tree_min_moist")
	swamp_bush_min_chance = _rand_range("swamp_bush_min_chance")
	birch_min_chance = _rand_range("birch_min_chance")


func _rand_range(key: String) -> float:
	var r: Array = PLAYABLE_RANGES[key]
	var lo: float = r[0]
	var hi: float = r[1]
	var step: float = r[2]
	if step <= 0.0:
		return randf_range(lo, hi)
	var n := int(round((hi - lo) / step))
	return lo + float(randi() % (n + 1)) * step




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
	if biome_seed == 0:
		biome_seed = randi()


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
