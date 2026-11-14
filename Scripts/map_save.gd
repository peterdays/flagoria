class_name MapSave
extends RefCounted
## Versioned world saves in user://saves/, one file per world. The writer
## stores gzip (FileAccess.COMPRESSION_GZIP) of one compact JSON document:
## the generation inputs plus sparse change sections (WorldSave). A file that
## is not gzip is the JSON itself, which is how version 1 and 2 were written,
## and those still load. Format: docs/world-saves.md.

## Identifies a world save; required from version 2.
const FORMAT_ID := "flagoria-world"
## Version 1: format_version and params only. Version 2: adds format, world
## and player. Version 3: adds game_version, created and updated, and the
## file is gzip. Older versions are migrated on load, see _migrate.
const FORMAT_VERSION := 3
## Written into game_version. There is no separate release number yet, so
## this stays "0". The loader ignores it; format_version decides compatibility.
const GAME_VERSION := "0"
## Refuse a gzip whose JSON would expand past this. A normal save is far smaller.
const MAX_SAVE_BYTES := 1048576
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
	var path := path_for(save_name)
	# Read an existing file before WRITE truncates it, so a second save of the
	# same world keeps the created time the first write stored.
	_stamp(world, path)
	var raw := _to_json(data, world).to_utf8_buffer()
	var compressed := raw.compress(FileAccess.COMPRESSION_GZIP)
	if compressed.is_empty():
		return {"path": "", "error": "cannot compress %s" % path}
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		return {"path": "", "error": "cannot create %s (error %s)" % [SAVE_DIR, err]}
	var replaced := _replace_save(path, compressed)
	if replaced != "":
		return {"path": "", "error": replaced}
	return {"path": path, "error": ""}


static func _replace_save(path: String, bytes: PackedByteArray) -> String:
	## Writes `bytes` beside `path` as `path.tmp`, keeps them only when that
	## file reads back as a save, then renames it over `path`. Returns "" or
	## an error. A failure leaves `path` as it was. A leftover temp from an
	## interrupted write is removed first, and again if this write fails.
	var tmp := path + ".tmp"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (error %s)" % [tmp, FileAccess.get_open_error()]
	file.store_buffer(bytes)
	file.close()
	var check := read_document(tmp)
	if check["error"] != "":
		DirAccess.remove_absolute(tmp)
		return "save did not read back (%s)" % check["error"]
	var renamed := DirAccess.rename_absolute(tmp, path)
	if renamed != OK:
		DirAccess.remove_absolute(tmp)
		return "cannot replace %s (error %s)" % [path, renamed]
	return ""


static func _stamp(world: WorldSave, path: String) -> void:
	## Fills the header on `world` for the write about to happen. created stays
	## when it is already set, or when `path` already holds one; otherwise it
	## is now. updated and game_version always become this write.
	if world.created <= 0 and FileAccess.file_exists(path):
		var existing := load_world(path)
		if existing["error"] == "" and existing["world"].created > 0:
			world.created = existing["world"].created
	var now := int(Time.get_unix_time_from_system())
	if world.created <= 0:
		world.created = now
	world.updated = now
	world.game_version = GAME_VERSION


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
		lines.append('"%s":%s' % [key, text])
	# One compact line. format and format_version stay first so the document
	# is identifiable after it is uncompressed.
	return (
		'{"format":"%s","format_version":%d,"game_version":%s,"created":%d,"updated":%d,"params":{%s},"world":%s,"player":%s}'
		% [
			FORMAT_ID,
			FORMAT_VERSION,
			JSON.stringify(world.game_version),
			world.created,
			world.updated,
			",".join(lines),
			JSON.stringify(world.world_to_dict(), "", true),
			JSON.stringify(world.player, "", true),
		]
	)


static func read_document(path: String) -> Dictionary:
	## The save's JSON value, decompressing gzip first when the file is one.
	## Returns {"data": Variant, "error": String}; error is "" on success.
	## Plain JSON (version 1 and 2, or a hand-written file) is read as text.
	var failed := func(error: String) -> Dictionary: return {"data": null, "error": error}
	if not FileAccess.file_exists(path):
		return failed.call("no map save at %s" % path)
	var bytes := FileAccess.get_file_as_bytes(path)
	var text := ""
	if bytes.size() >= 2 and bytes[0] == 0x1f and bytes[1] == 0x8b:
		var plain := bytes.decompress_dynamic(MAX_SAVE_BYTES, FileAccess.COMPRESSION_GZIP)
		if plain.is_empty():
			return failed.call("%s is not a map save (could not decompress)" % path)
		text = plain.get_string_from_utf8()
	else:
		text = bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		return failed.call("%s is not a map save (invalid JSON at line %s: %s)" % [path, json.get_error_line(), json.get_error_message()])
	return {"data": json.data, "error": ""}


static func load_map(path: String) -> Dictionary:
	## Returns {"params": MapGenParams or null, "error": String}; error is "" on success.
	var loaded := load_world(path)
	return {"params": loaded["world"].params if loaded["world"] else null, "error": loaded["error"]}


static func load_world(path: String) -> Dictionary:
	## Returns {"world": WorldSave or null, "error": String, "version": int},
	## where version is the file's own format version (older ones are
	## migrated in memory; the file changes on its next save).
	var failed := func(error: String) -> Dictionary: return {"world": null, "error": error, "version": 0}
	var doc := read_document(path)
	if doc["error"] != "":
		return failed.call(doc["error"])
	var parsed = doc["data"]
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
	_migrate(parsed, int(FileAccess.get_modified_time(path)))
	if not parsed.get("params") is Dictionary:
		return failed.call("%s has no params section" % path)
	if not parsed["world"] is Dictionary or not parsed["player"] is Dictionary:
		return failed.call("%s has a world or player section that is not an object" % path)
	if typeof(parsed.get("game_version")) != TYPE_STRING:
		return failed.call("%s game_version is not a string" % path)
	if not _is_unix_time(parsed.get("created")):
		return failed.call("%s created is not a whole number of seconds" % path)
	if not _is_unix_time(parsed.get("updated")):
		return failed.call("%s updated is not a whole number of seconds" % path)

	var params := MapGenParams.make_defaults()
	# Saves written before biomes existed have no biome_frequency; they load
	# with biomes off so the saved world regenerates as it was.
	params.biome_frequency = 0.0
	# Saves written before biome_edge have no such field; they load with the
	# old 0.5 cut-off so their biome regions stay where they were.
	params.biome_edge = 0.5
	# Saves written before pines existed have no pine_min_chance; they load
	# with pines off (a chance threshold no cell reaches) for the same reason.
	params.pine_min_chance = 2.0
	# Saves written before bushy trees have no bushy_tree_min_moist; they load
	# with bushy trees off (a threshold no moisture reaches).
	params.bushy_tree_min_moist = 2.0
	# Saves written before swamp scrub have no swamp_bush_min_chance; they load
	# with no bushes on swamp (a chance threshold no cell reaches).
	params.swamp_bush_min_chance = 2.0
	# Saves written before birches have no birch_min_chance; they load with none.
	params.birch_min_chance = 2.0
	params.from_dict(parsed["params"])
	var world := WorldSave.new(params)
	var section_error := world.world_from_dict(parsed["world"])
	if section_error != "":
		return failed.call("%s: %s" % [path, section_error])
	world.player = parsed["player"]
	world.game_version = parsed["game_version"]
	world.created = int(parsed["created"])
	world.updated = int(parsed["updated"])
	return {"world": world, "error": "", "version": int(version)}


static func _is_unix_time(value) -> bool:
	## True for a non-negative whole number of seconds. JSON parses numbers
	## as floats; migration writes ints. Both are accepted.
	if value is int:
		return value >= 0
	if value is float:
		return value >= 0.0 and value == floorf(value)
	return false


static func _migrate(parsed: Dictionary, file_mtime: int) -> void:
	## Brings a parsed save of any supported version up to FORMAT_VERSION, one
	## step per version. Each step only adds what its version introduced.
	## `file_mtime` is the file's modified time, the only clock an older file has.
	if int(parsed["format_version"]) == 1:
		# Version 1 held the generation inputs only: no changes were saved.
		parsed["format"] = FORMAT_ID
		parsed["world"] = {}
		parsed["player"] = {}
		parsed["format_version"] = 2
	if int(parsed["format_version"]) == 2:
		# Version 2 had no game version and no clock. Both stamps use the
		# file's modified time. game_version stays empty until the next save.
		var when := file_mtime if file_mtime > 0 else 0
		parsed["game_version"] = ""
		parsed["created"] = when
		parsed["updated"] = when
		parsed["format_version"] = 3
	parsed.get_or_add("world", {})
	parsed.get_or_add("player", {})


static func list_saves(dir: String = SAVE_DIR) -> Array[Dictionary]:
	## The saved maps in dir, newest first: {"name", "path", "modified"}, where
	## name is the file name without ".json" and modified is Unix seconds.
	## Files are not parsed; load_map reports a broken one. A `name.json.tmp`
	## left by an interrupted write is not a world.
	var rows: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return rows
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".tmp"):
			continue
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
	if err != OK:
		return "cannot rename %s to %s (error %s)" % [save_name, clean, err]
	WorldSavePreview.rename_save(save_name, clean)
	return ""


static func delete_save(save_name: String, dir: String = SAVE_DIR) -> String:
	## Deletes a save in dir; returns "" or an error.
	var bad := _bad_name_error(save_name)
	if bad != "":
		return bad
	var path := dir + save_name + ".json"
	if not FileAccess.file_exists(path):
		return "no map save named %s" % save_name
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return "cannot delete %s (error %s)" % [save_name, err]
	WorldSavePreview.remove(save_name)
	return ""


static func _bad_name_error(save_name: String) -> String:
	## A save name names one file in the saves folder; anything that could
	## reach another folder ("../x", "a/b") is refused rather than resolved.
	if save_name == "" or save_name != save_name.validate_filename() or "/" in save_name or "\\" in save_name or ".." in save_name:
		return "not a map save name: %s" % save_name
	return ""
