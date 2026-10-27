class_name MapSave
extends RefCounted
## Versioned JSON world saves in user://saves/: a world's generation inputs
## (every MapGenParams value, including the seeds the world was generated
## with) plus sparse change sections (WorldSave). Format: docs/world-saves.md.

## Identifies a world save; required from version 2.
const FORMAT_ID := "flagoria-world"
## Version 1: format_version and params only. Version 2: adds format, world
## and player. Older versions are migrated on load, see _migrate.
const FORMAT_VERSION := 2
const SAVE_DIR := "user://saves/"


static func path_for(save_name: String) -> String:
	return SAVE_DIR + save_name.validate_filename() + ".json"


static func save_map(params: MapGenParams, save_name: String) -> Dictionary:
	## Saves generation inputs with empty change sections.
	## Returns {"path": String, "error": String}; error is "" on success.
	return save_world(WorldSave.new(params), save_name)


static func save_world(world: WorldSave, save_name: String) -> Dictionary:
	## Returns {"path": String, "error": String}; error is "" on success.
	var data := world.params.to_dict()
	# Every *_seed value, so a seed added to MapGenParams is checked too.
	for key in data.keys():
		if key.ends_with("_seed") and data[key] == 0:
			return {"path": "", "error": "%s is 0 (unresolved); save the seeds the world used" % key}
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		return {"path": "", "error": "cannot create %s (error %s)" % [SAVE_DIR, err]}
	var path := path_for(save_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"path": "", "error": "cannot write %s (error %s)" % [path, FileAccess.get_open_error()]}
	file.store_string(_to_json(data, world))
	return {"path": path, "error": ""}


static func _to_json(data: Dictionary, world: WorldSave) -> String:
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
	return (
		'{\n\t"format": "%s",\n\t"format_version": %s,\n\t"params": {\n%s\n\t},\n\t"world": %s,\n\t"player": %s\n}\n'
		% [
			FORMAT_ID,
			FORMAT_VERSION,
			",\n".join(lines),
			JSON.stringify(world.world_to_dict(), "", true),
			JSON.stringify(world.player, "", true),
		]
	)


static func load_map(path: String) -> Dictionary:
	## Returns {"params": MapGenParams or null, "error": String}; error is "" on success.
	var loaded := load_world(path)
	return {"params": loaded["world"].params if loaded["world"] else null, "error": loaded["error"]}


static func load_world(path: String) -> Dictionary:
	## Returns {"world": WorldSave or null, "error": String, "version": int},
	## where version is the file's own format version (older ones are
	## migrated in memory; the file changes on its next save).
	var failed := func(error: String) -> Dictionary: return {"world": null, "error": error, "version": 0}
	if not FileAccess.file_exists(path):
		return failed.call("no map save at %s" % path)
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return failed.call("%s is not a map save (invalid JSON at line %s: %s)" % [path, json.get_error_line(), json.get_error_message()])
	var parsed = json.data
	if not parsed is Dictionary or not parsed.has("format_version"):
		return failed.call("%s is not a map save (no format_version)" % path)
	var version = parsed["format_version"]
	if typeof(version) != TYPE_FLOAT or version != floorf(version) or version < 1:
		return failed.call("%s has an unknown map save version %s" % [path, version])
	if version > FORMAT_VERSION:
		return failed.call(
			"%s has map save version %d, from a newer build; this build reads versions 1 to %d" % [path, version, FORMAT_VERSION]
		)
	if version >= 2 and parsed.get("format") != FORMAT_ID:
		return failed.call("%s is not a world save (format %s, want %s)" % [path, parsed.get("format"), FORMAT_ID])
	_migrate(parsed)
	if not parsed.get("params") is Dictionary:
		return failed.call("%s has no params section" % path)
	if not parsed["world"] is Dictionary or not parsed["player"] is Dictionary:
		return failed.call("%s has a world or player section that is not an object" % path)

	var params := MapGenParams.make_defaults()
	# Saves written before biomes existed have no biome_frequency; they load
	# with biomes off so the saved world regenerates as it was.
	params.biome_frequency = 0.0
	params.from_dict(parsed["params"])
	var world := WorldSave.new(params)
	var section_error := world.world_from_dict(parsed["world"])
	if section_error != "":
		return failed.call("%s: %s" % [path, section_error])
	world.player = parsed["player"]
	return {"world": world, "error": "", "version": int(version)}


static func _migrate(parsed: Dictionary) -> void:
	## Brings a parsed save of any supported version up to FORMAT_VERSION, one
	## step per version. Each step only adds what its version introduced.
	if parsed["format_version"] == 1:
		# Version 1 held the generation inputs only: no changes were saved.
		parsed["format"] = FORMAT_ID
		parsed["world"] = {}
		parsed["player"] = {}
		parsed["format_version"] = 2.0
	parsed.get_or_add("world", {})
	parsed.get_or_add("player", {})


static func list_saves(dir: String = SAVE_DIR) -> Array[Dictionary]:
	## The saved maps in dir, newest first: {"name", "path", "modified"}, where
	## name is the file name without ".json" and modified is Unix seconds.
	## Files are not parsed; load_map reports a broken one.
	var rows: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return rows
	for file_name in DirAccess.get_files_at(dir):
		if file_name.get_extension() == "json":
			var path := dir + file_name
			rows.append({"name": file_name.get_basename(), "path": path, "modified": FileAccess.get_modified_time(path)})
	rows.sort_custom(func(a, b): return a["modified"] > b["modified"] or (a["modified"] == b["modified"] and a["name"] < b["name"]))
	return rows


static func rename_save(save_name: String, new_name: String, dir: String = SAVE_DIR) -> String:
	## Renames a save in dir; returns "" or an error. The new name goes through
	## validate_filename like save_map's, and an existing save is never replaced.
	var bad := _bad_name_error(save_name)
	if bad != "":
		return bad
	var path := dir + save_name + ".json"
	var clean := new_name.strip_edges().validate_filename()
	if not FileAccess.file_exists(path):
		return "no map save named %s" % save_name
	if clean == "":
		return "a save needs a name"
	var new_path := dir + clean + ".json"
	if FileAccess.file_exists(new_path):
		return "a map save named %s already exists" % clean
	var err := DirAccess.rename_absolute(path, new_path)
	return "" if err == OK else "cannot rename %s to %s (error %s)" % [save_name, clean, err]


static func delete_save(save_name: String, dir: String = SAVE_DIR) -> String:
	## Deletes a save in dir; returns "" or an error.
	var bad := _bad_name_error(save_name)
	if bad != "":
		return bad
	var path := dir + save_name + ".json"
	if not FileAccess.file_exists(path):
		return "no map save named %s" % save_name
	var err := DirAccess.remove_absolute(path)
	return "" if err == OK else "cannot delete %s (error %s)" % [save_name, err]


static func _bad_name_error(save_name: String) -> String:
	## A save name names one file in the saves folder; anything that could
	## reach another folder ("../x", "a/b") is refused rather than resolved.
	if save_name == "" or save_name != save_name.validate_filename() or "/" in save_name or "\\" in save_name or ".." in save_name:
		return "not a map save name: %s" % save_name
	return ""
