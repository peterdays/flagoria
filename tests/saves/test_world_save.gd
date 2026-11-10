extends "res://tests/helpers/test_helpers.gd"
## One save in memory (Scripts/world_save.gd) and its versions.

## Compressed size ceilings printed by the size test. A fresh world is the
## header and the generation inputs. A few hundred edits is 300 plank cells.
const FRESH_BUDGET := 1024
const EDITED_BUDGET := 8192
const EDIT_COUNT := 300


func _test_world_save_round_trip() -> int:
	## A world save keeps its generation inputs, change sections and player
	## section through save + load, says which format and version it is, and
	## the file is gzip. Saving the same file again keeps created.
	print("-- test_world_save_round_trip")
	var fail := 0
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	var world := WorldSave.new(params)
	world.tile_edits["0,0"] = {"3,4": "SAND"}
	world.object_changes["-1,2"] = {"-20,70": {"removed": true}}
	world.structures["1,1"] = {"40,40": {"name": "guard_post"}}
	world.player = {"position": [12.5, -3.25]}  # JSON numbers read back as floats; the object stays opaque (#197)
	var saved := MapSave.save_world(world, "test_world_round_trip")
	var loaded := MapSave.load_world(saved["path"])
	var bytes := FileAccess.get_file_as_bytes(saved["path"])
	var doc := MapSave.read_document(saved["path"])
	if saved["error"] != "" or loaded["error"] != "" or doc["error"] != "":
		printerr("FAIL world_save_round_trip save=%s load=%s read=%s" % [saved["error"], loaded["error"], doc["error"]])
		DirAccess.remove_absolute(saved["path"])
		return 1
	var got: WorldSave = loaded["world"]
	var header: Dictionary = doc["data"]
	var gzip := bytes.size() >= 2 and bytes[0] == 0x1f and bytes[1] == 0x8b
	if not gzip or header["format"] != MapSave.FORMAT_ID or header["format_version"] != MapSave.FORMAT_VERSION \
			or loaded["version"] != MapSave.FORMAT_VERSION or header["game_version"] != MapSave.GAME_VERSION:
		printerr("FAIL world_save_round_trip header format=%s version=%s gzip=%s" % [header.get("format"), header.get("format_version"), gzip])
		fail += 1
	if got.game_version != MapSave.GAME_VERSION or got.created <= 0 or got.updated < got.created \
			or got.created != int(header["created"]) or got.updated != int(header["updated"]):
		printerr("FAIL world_save_round_trip stamps game=%s created=%s updated=%s" % [got.game_version, got.created, got.updated])
		fail += 1
	if got.params.to_dict() != params.to_dict():
		printerr("FAIL world_save_round_trip params changed")
		fail += 1
	for section in ["tile_edits", "object_changes", "structures", "player"]:
		if got.get(section) != world.get(section):
			printerr("FAIL world_save_round_trip %s saved=%s loaded=%s" % [section, world.get(section), got.get(section)])
			fail += 1
	# A later save of the same file, from a fresh in-memory world, keeps created.
	var again := MapSave.save_world(WorldSave.new(params), "test_world_round_trip")
	var again_loaded := MapSave.load_world(again["path"])
	DirAccess.remove_absolute(saved["path"])
	if again["error"] != "" or again_loaded["error"] != "" or again_loaded["world"].created != got.created \
			or again_loaded["world"].updated < got.updated or again_loaded["world"].game_version != MapSave.GAME_VERSION:
		printerr("FAIL world_save_round_trip second save created=%s want %s updated=%s"
				% [again_loaded["world"].created if again_loaded["world"] else 0, got.created,
				again_loaded["world"].updated if again_loaded["world"] else 0])
		fail += 1
	if fail == 0:
		print("PASS test_world_save_round_trip")
	return fail


func _test_world_save_section_round_trips() -> int:
	## Each change section, and the player section, survives a save on its own.
	print("-- test_world_save_section_round_trips")
	var fail := 0
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	var samples := {
		"tile_edits": {"0,0": {"3,4": {"tile": "SAND"}}},
		"object_changes": {"-1,2": {"-20,70": {"removed": true}}},
		"structures": {"1,1": {"40,40": {"name": "guard_post"}}},
		"player": {"note": "keep"},
	}
	for section in ["tile_edits", "object_changes", "structures", "player"]:
		var world := WorldSave.new(params)
		if section == "player":
			world.player = samples[section]
		else:
			(world.get(section) as Dictionary).assign(samples[section])
		var name := "test_ws_section_%s" % section
		var saved := MapSave.save_world(world, name)
		var loaded := MapSave.load_world(saved["path"])
		DirAccess.remove_absolute(saved["path"])
		var got = loaded["world"].get(section) if loaded["world"] else null
		if saved["error"] != "" or loaded["error"] != "" or got != samples[section]:
			printerr("FAIL world_save_section_round_trips %s save=%s load=%s got=%s" % [section, saved["error"], loaded["error"], got])
			fail += 1
		else:
			print("  %s round-trip ok" % section)
	if fail == 0:
		print("PASS test_world_save_section_round_trips")
	return fail


func _test_world_save_size_budget() -> int:
	## A fresh world, and a world with a few hundred chunk-keyed edits, each
	## stay under a stated compressed-size budget.
	print("-- test_world_save_size_budget")
	var fail := 0
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	var fresh := MapSave.save_world(WorldSave.new(params), "test_ws_size_fresh")
	var fresh_bytes := FileAccess.get_file_as_bytes(fresh["path"])
	var fresh_json := fresh_bytes.decompress_dynamic(MapSave.MAX_SAVE_BYTES, FileAccess.COMPRESSION_GZIP).size()
	DirAccess.remove_absolute(fresh["path"])
	var edited := WorldSave.new(params)
	for i in EDIT_COUNT:
		var cell := Vector2i(i, 0)
		var chunk := WorldSave.chunk_key(cell)
		edited.tile_edits.get_or_add(chunk, {})[WorldSave.cell_key(cell)] = {"tile": "BRIDGE_PLANK_H_START_WATER"}
	var saved := MapSave.save_world(edited, "test_ws_size_edits")
	var edit_bytes := FileAccess.get_file_as_bytes(saved["path"])
	var edit_json := edit_bytes.decompress_dynamic(MapSave.MAX_SAVE_BYTES, FileAccess.COMPRESSION_GZIP).size()
	var loaded := MapSave.load_world(saved["path"])
	DirAccess.remove_absolute(saved["path"])
	var edit_count := 0
	if loaded["world"]:
		for chunk in loaded["world"].tile_edits:
			edit_count += loaded["world"].tile_edits[chunk].size()
	if fresh["error"] != "" or fresh_bytes.size() > FRESH_BUDGET or fresh_bytes.size() < 2:
		printerr("FAIL world_save_size_budget fresh %d bytes (budget %d) error=%s" % [fresh_bytes.size(), FRESH_BUDGET, fresh["error"]])
		fail += 1
	if saved["error"] != "" or loaded["error"] != "" or edit_bytes.size() > EDITED_BUDGET or edit_count != EDIT_COUNT:
		printerr("FAIL world_save_size_budget %d edits %d bytes (budget %d) count=%d error=%s"
				% [EDIT_COUNT, edit_bytes.size(), EDITED_BUDGET, edit_count, saved["error"] if saved["error"] != "" else loaded["error"]])
		fail += 1
	if fail == 0:
		print("PASS test_world_save_size_budget (fresh %d gzip bytes, %d json, budget %d; %d edits %d gzip bytes, %d json, budget %d)"
				% [fresh_bytes.size(), fresh_json, FRESH_BUDGET, EDIT_COUNT, edit_bytes.size(), edit_json, EDITED_BUDGET])
	return fail


func _test_world_save_version_check() -> int:
	## The current version loads, plain or without optional sections. A newer
	## version, an unknown version, another format, a bad clock and a malformed
	## change section are refused with a clear error. Version 2 still loads.
	print("-- test_world_save_version_check")
	var fail := 0
	var params := '"params": {"altitude_seed": 7}'
	var header := '"format":"flagoria-world","format_version":3,"game_version":"0","created":10,"updated":20'
	var cases := {
		"test_ws_current": ['{%s, %s, "world": {}, "player": {}}' % [header, params], ""],
		"test_ws_no_sections": ['{%s, %s}' % [header, params], ""],
		"test_ws_v2": ['{"format": "flagoria-world", "format_version": 2, %s}' % params, ""],
		"test_ws_future": ['{"format": "flagoria-world", "format_version": 4, %s}' % params, "version 4, from a newer build"],
		"test_ws_fraction": ['{"format": "flagoria-world", "format_version": 1.5, %s}' % params, "unknown map save version"],
		"test_ws_other_format": ['{"format": "other", "format_version": 3, %s}' % params, "not a world save"],
		"test_ws_no_format": ['{"format_version": 3, %s}' % params, "not a world save"],
		"test_ws_bad_section": [
			'{%s, %s, "world": {"tile_edits": {"0,0": 5}}}' % [header, params],
			"world.tile_edits[0,0] is not an object",
		],
		"test_ws_bad_player": ['{%s, %s, "player": []}' % [header, params], "not an object"],
		"test_ws_bad_game": ['{"format":"flagoria-world","format_version":3,"game_version":1,"created":10,"updated":20, %s}' % params, "game_version"],
		"test_ws_bad_time": ['{"format":"flagoria-world","format_version":3,"game_version":"0","created":1.5,"updated":20, %s}' % params, "created"],
		# Truncated gzip. The engine prints "Decompression failed" for this case.
		"test_ws_bad_gzip": [PackedByteArray([0x1f, 0x8b, 0x00]), "could not decompress"],
	}
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	for save_name in cases.keys():
		var path := MapSave.path_for(save_name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		var payload = cases[save_name][0]
		if payload is PackedByteArray:
			file.store_buffer(payload)
		else:
			file.store_string(payload)
		file.close()
		var result := MapSave.load_world(path)
		var mtime := int(FileAccess.get_modified_time(path))
		DirAccess.remove_absolute(path)
		var want: String = cases[save_name][1]
		var ok: bool = (result["error"] == "" and result["world"] != null and result["world"].params.altitude_seed == 7) if want == "" \
				else (result["world"] == null and want in result["error"])
		if save_name == "test_ws_current" and ok:
			ok = result["version"] == 3 and result["world"].created == 10 and result["world"].updated == 20 \
					and result["world"].game_version == "0"
		if save_name == "test_ws_v2" and ok:
			ok = result["version"] == 2 and result["world"].game_version == "" \
					and result["world"].created == mtime and result["world"].updated == mtime
		if not ok:
			printerr("FAIL world_save_version_check %s error=%s want %s" % [save_name, result["error"], want if want != "" else "a load"])
			fail += 1
	if fail == 0:
		print("PASS test_world_save_version_check")
	return fail


func _test_world_save_migrates_v1() -> int:
	## Every format version has a fixture in tests/fixtures/ that still loads.
	## Version 1 and 2 stay plain JSON. Version 3 is the gzip the writer emits.
	## A version 1 map save loads with the same inputs and empty change
	## sections, and saving it again writes the current version without
	## moving created.
	print("-- test_world_save_migrates_v1")
	var fail := 0
	for version in range(1, MapSave.FORMAT_VERSION + 1):
		var fixture := "res://tests/fixtures/world_save_v%d.json" % version
		var raw_bytes := FileAccess.get_file_as_bytes(fixture)
		var is_gzip := raw_bytes.size() >= 2 and raw_bytes[0] == 0x1f and raw_bytes[1] == 0x8b
		if (version >= 3) != is_gzip:
			printerr("FAIL world_save_migrates_v1 %s gzip=%s" % [fixture, is_gzip])
			fail += 1
		var loaded := MapSave.load_world(fixture)
		if loaded["error"] != "" or loaded["version"] != version:
			printerr("FAIL world_save_migrates_v1 %s error=%s version=%s" % [fixture, loaded["error"], loaded["version"]])
			fail += 1
			continue
		var world: WorldSave = loaded["world"]
		var doc := MapSave.read_document(fixture)
		var raw: Dictionary = doc["data"]["params"] if doc["error"] == "" else {}
		for key in raw:
			if world.params.get(key) != raw[key]:
				printerr("FAIL world_save_migrates_v1 %s %s=%s want %s" % [fixture, key, world.params.get(key), raw[key]])
				fail += 1
		if not world.world_to_dict().values().all(func(s): return s.is_empty()) or not world.player.is_empty():
			printerr("FAIL world_save_migrates_v1 %s change sections not empty" % fixture)
			fail += 1
		if version < 3:
			var mtime := int(FileAccess.get_modified_time(fixture))
			if world.game_version != "" or world.created != mtime or world.updated != mtime:
				printerr("FAIL world_save_migrates_v1 %s stamps game=%s created=%s updated=%s mtime=%s"
						% [fixture, world.game_version, world.created, world.updated, mtime])
				fail += 1
		var saved := MapSave.save_world(world, "test_ws_migrated_v%d" % version)
		var again := MapSave.load_world(saved["path"])
		DirAccess.remove_absolute(saved["path"])
		var kept: bool = again["error"] == "" and again["version"] == MapSave.FORMAT_VERSION \
				and again["world"].params.to_dict() == world.params.to_dict() \
				and again["world"].game_version == MapSave.GAME_VERSION \
				and (world.created <= 0 or again["world"].created == world.created)
		if not kept:
			printerr("FAIL world_save_migrates_v1 %s re-save error=%s version=%s created=%s"
					% [fixture, again["error"], again["version"], again["world"].created if again["world"] else 0])
			fail += 1
	if fail == 0:
		print("PASS test_world_save_migrates_v1 (fixtures v1 to v%d)" % MapSave.FORMAT_VERSION)
	return fail


func _test_world_save_keeps_previous_on_failed_write() -> int:
	## A new save is written to path.tmp and renamed over the previous file
	## only after it reads back. A partial temp file, and bytes that do not
	## read back, leave the previous save loadable. The list skips .tmp files.
	print("-- test_world_save_keeps_previous_on_failed_write")
	var fail := 0
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	params.altitude_seed = 4242
	var saved := MapSave.save_world(WorldSave.new(params), "test_ws_durable")
	var path: String = saved["path"]
	if saved["error"] != "" or path == "":
		printerr("FAIL world_save_keeps_previous setup %s" % saved["error"])
		return 1
	var before := FileAccess.get_file_as_bytes(path)
	var tmp := path + ".tmp"
	var partial := FileAccess.open(tmp, FileAccess.WRITE)
	if partial == null:
		printerr("FAIL world_save_keeps_previous cannot write a partial temp")
		DirAccess.remove_absolute(path)
		return 1
	partial.store_string("partial")
	partial.close()
	var still := MapSave.load_world(path)
	var listed_tmp := false
	var listed_save := false
	for row in MapSave.list_saves():
		var row_path := str(row["path"])
		if row_path.ends_with(".tmp"):
			listed_tmp = true
		if row_path == path:
			listed_save = true
	if still["error"] != "" or still["world"].params.altitude_seed != 4242 \
			or FileAccess.get_file_as_bytes(path) != before or listed_tmp or not listed_save \
			or not FileAccess.file_exists(tmp):
		printerr("FAIL world_save_keeps_previous interrupted load=%s listed_tmp=%s listed_save=%s"
				% [still["error"], listed_tmp, listed_save])
		fail += 1
	var bad := MapSave._replace_save(path, PackedByteArray([0x00, 0x01, 0x02]))
	var after_bad := MapSave.load_world(path)
	if bad == "" or FileAccess.file_exists(tmp) or FileAccess.get_file_as_bytes(path) != before \
			or after_bad["error"] != "" or after_bad["world"].params.altitude_seed != 4242:
		printerr("FAIL world_save_keeps_previous failed write error=%s tmp_left=%s load=%s"
				% [bad, FileAccess.file_exists(tmp), after_bad["error"]])
		fail += 1
	# The next save removes a leftover temp, then replaces the file.
	var stale := FileAccess.open(tmp, FileAccess.WRITE)
	stale.store_string("stale")
	stale.close()
	params.altitude_seed = 4343
	var again := MapSave.save_world(WorldSave.new(params), "test_ws_durable")
	var loaded := MapSave.load_world(path)
	if again["error"] != "" or FileAccess.file_exists(tmp) or loaded["error"] != "" \
			or loaded["world"].params.altitude_seed != 4343:
		printerr("FAIL world_save_keeps_previous next save error=%s tmp_left=%s seed=%s"
				% [again["error"], FileAccess.file_exists(tmp),
				loaded["world"].params.altitude_seed if loaded["world"] else 0])
		fail += 1
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(tmp)
	if fail == 0:
		print("PASS test_world_save_keeps_previous_on_failed_write")
	return fail
