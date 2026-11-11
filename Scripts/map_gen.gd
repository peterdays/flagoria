extends Node
## Autoload holding the active map-generation parameters for the session.

const SAVE_PATH := "user://map_gen_params.cfg"
const SAVE_SECTION := "map_gen"

## A map save succeeded (save_map_inputs or save_world); UiSfx plays "saved".
signal map_saved(path: String)

var params: MapGenParams = MapGenParams.make_defaults()
## The save load_map_inputs read last, until a host takes it.
var _loaded_world: WorldSave = null


func _ready() -> void:
	load_from_disk()


func reset_to_defaults() -> void:
	params = MapGenParams.make_defaults()


func randomize_seeds() -> void:
	params.randomize_seeds()


func randomize_specs() -> void:
	params.randomize_specs()


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


func save_map_inputs(save_name: String) -> String:
	## Saves the active params to MapSave.path_for(save_name); returns "" or an error.
	## After hosting, the active params hold the resolved seeds.
	return save_world(WorldSave.new(params), save_name)["error"]


func save_world(world: WorldSave, save_name: String) -> Dictionary:
	## MapSave.save_world, then map_saved on success. {"path", "error"}.
	var result := MapSave.save_world(world, save_name)
	if result["error"] == "":
		map_saved.emit(result["path"])
	return result


func load_map_inputs(path: String) -> String:
	## Makes a saved world the active params for the next host, and keeps its
	## change sections for take_loaded_world; returns "" or an error.
	var result := MapSave.load_world(path)
	if result["error"] == "":
		params = result["world"].params
		_loaded_world = result["world"]
	return result["error"]


func has_loaded_world() -> bool:
	return _loaded_world != null


func clear_loaded_world() -> void:
	## Drop a world that was loaded but is not the one about to be hosted.
	_loaded_world = null


func take_loaded_world(world_params: MapGenParams) -> WorldSave:
	## The world load_map_inputs read, when `world_params` (the params a
	## host is starting with) are still its params; null otherwise, e.g.
	## after the params were edited. One use: the next call returns null.
	var world := _loaded_world
	_loaded_world = null
	if world == null or world.params.to_dict() != world_params.to_dict():
		return null
	return world


func apply_to_world_map(world_map: Node) -> void:
	if world_map and world_map.has_method("apply_map_params"):
		world_map.apply_map_params(params)
