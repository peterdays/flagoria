extends Node
## Autoload holding the active map-generation parameters for the session.

const SAVE_PATH := "user://map_gen_params.cfg"
const SAVE_SECTION := "map_gen"

var params: MapGenParams = MapGenParams.make_defaults()


func _ready() -> void:
	load_from_disk()


func reset_to_defaults() -> void:
	params = MapGenParams.make_defaults()


func randomize_seeds() -> void:
	params.randomize_seeds()


func save_to_disk() -> void:
	var cfg = ConfigFile.new()
	var data = params.to_dict()
	for key in data.keys():
		cfg.set_value(SAVE_SECTION, key, data[key])
	cfg.save(SAVE_PATH)


func load_from_disk() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var data = {}
	for key in params.to_dict().keys():
		if cfg.has_section_key(SAVE_SECTION, key):
			data[key] = cfg.get_value(SAVE_SECTION, key)
	if not data.is_empty():
		params.from_dict(data)


func apply_to_world_map(world_map: Node) -> void:
	if world_map and world_map.has_method("apply_map_params"):
		world_map.apply_map_params(params)
