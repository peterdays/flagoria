class_name MapSave
extends RefCounted
## Versioned JSON files in user://saves/ holding a world's generation inputs:
## every MapGenParams value, including the seeds the world was generated with.

const FORMAT_VERSION := 1
const SAVE_DIR := "user://saves/"
const SEED_KEYS := ["altitude_seed", "moisture_seed", "temperature_seed", "items_seed"]


static func path_for(save_name: String) -> String:
	return SAVE_DIR + save_name.validate_filename() + ".json"


static func save_map(params: MapGenParams, save_name: String) -> Dictionary:
	## Returns {"path": String, "error": String}; error is "" on success.
	var data := params.to_dict()
	for key in SEED_KEYS:
		if data[key] == 0:
			return {"path": "", "error": "%s is 0 (unresolved); save the seeds the world used" % key}
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		return {"path": "", "error": "cannot create %s (error %s)" % [SAVE_DIR, err]}
	var path := path_for(save_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"path": "", "error": "cannot write %s (error %s)" % [path, FileAccess.get_open_error()]}
	file.store_string(_to_json(data))
	return {"path": path, "error": ""}


static func _to_json(data: Dictionary) -> String:
	## JSON.stringify in Godot 4.1 rounds floats to 15 significant digits, and
	## SpinBox snapping produces values such as 0.19999999999999996, so floats
	## are written with as many digits as it takes to read back the same value.
	var keys := data.keys()
	keys.sort()
	var lines := PackedStringArray()
	for key in keys:
		var value = data[key]
		var text := str(value)
		if value is float:
			text = String.num(value, 15)
			if text.to_float() != value:
				text = String.num(value, 17)
		lines.append('\t\t"%s": %s' % [key, text])
	return '{\n\t"format_version": %s,\n\t"params": {\n%s\n\t}\n}\n' % [FORMAT_VERSION, ",\n".join(lines)]


static func load_map(path: String) -> Dictionary:
	## Returns {"params": MapGenParams or null, "error": String}; error is "" on success.
	if not FileAccess.file_exists(path):
		return {"params": null, "error": "no map save at %s" % path}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {
			"params": null,
			"error": "%s is not a map save (invalid JSON at line %s: %s)" % [path, json.get_error_line(), json.get_error_message()],
		}
	var parsed = json.data
	if not parsed is Dictionary or not parsed.has("format_version"):
		return {"params": null, "error": "%s is not a map save (no format_version)" % path}
	var version = parsed["format_version"]
	if typeof(version) != TYPE_FLOAT or version != FORMAT_VERSION:
		return {
			"params": null,
			"error": "%s has map save version %s; this build reads version %s" % [path, version, FORMAT_VERSION],
		}
	if not parsed.get("params") is Dictionary:
		return {"params": null, "error": "%s has no params section" % path}

	var params := MapGenParams.make_defaults()
	params.from_dict(parsed["params"])
	return {"params": params, "error": ""}
