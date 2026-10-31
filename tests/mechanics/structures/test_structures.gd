extends "res://tests/helpers/test_helpers.gd"
## Structure files: parse, export, lenient paste and errors.


func _test_structure_round_trip() -> int:
	## Every shipped res://structures/*.txt parses with no errors, its name
	## matches the file name, and it re-exports byte for byte.
	print("-- test_structure_round_trip")
	var fail := 0
	var files := Array(DirAccess.get_files_at("res://structures")).filter(func(f): return f.ends_with(".txt"))
	if not "guard_post.txt" in files:
		printerr("FAIL structure_round_trip: res://structures/guard_post.txt is missing")
		fail += 1
	for file in files:
		var text := FileAccess.get_file_as_string("res://structures/" + file)
		var result := Structure.parse(text)
		if result["structure"] == null:
			printerr("FAIL structure_round_trip %s: %s" % [file, "; ".join(result["errors"])])
			fail += 1
			continue
		var s: Structure = result["structure"]
		if s.name + ".txt" != file:
			printerr("FAIL structure_round_trip %s: name is %s" % [file, s.name])
			fail += 1
		if s.to_text() != text:
			printerr("FAIL structure_round_trip %s is not canonical, re-export:\n%s" % [file, s.to_text()])
			fail += 1
	if fail == 0:
		print("PASS test_structure_round_trip (%d files)" % files.size())
	return fail


func _test_structure_lenient_paste() -> int:
	## CRLF, ``` fences, tab indentation and blank lines parse to the same structure.
	print("-- test_structure_lenient_paste")
	var text := FileAccess.get_file_as_string("res://structures/guard_post.txt")
	var pasted := "\n\n```\n" + text.replace("\n  ", "\n\t").replace("\n", "\r\n") + "```\n\n"
	var result := Structure.parse(pasted)
	if result["structure"] == null or result["structure"].to_text() != text:
		printerr("FAIL structure_lenient_paste: %s" % "; ".join(result["errors"]))
		return 1
	print("PASS test_structure_lenient_paste")
	return 0


func _test_structure_rejects() -> int:
	## Each broken variant of the guard post gives one error naming the problem.
	print("-- test_structure_rejects")
	var fail := 0
	var good := FileAccess.get_file_as_string("res://structures/guard_post.txt")
	var cases := [
		["# = WALL_H auto", "# = WALL_NOPE auto", "unknown tile WALL_NOPE"],
		["# = WALL_H auto", "# = WALL_V auto", "WALL_V is not allowed on the object layer"],
		["s = SAND", "s = TREE", "TREE is not allowed on the ground layer"],
		["  #...#", "  #..#", "object row 2: 4 characters"],
		["  #...#", "  #.X.#", "object row 2: 'X' is not in the legend"],
		["  T = WALL_POST", "  T = WALL_POST\n  T = BUSH", "'T' is defined twice"],
		["  T = WALL_POST", "  T = WALL_POST\n  . = BUSH", "legend character '.'"],
		["  T = WALL_POST", "  T = WALL_POST\n  b = BUSH", "'b' is never used"],
		["# = WALL_H auto", "# = WALL_H solid", "unknown attribute 'solid'"],
		["size: 5x4", "size: 17x4", "size must be WxH"],
		["anchor: 2,3", "anchor: 2,4", "anchor 2,4 is outside"],
		["flagoria-structure 1", "flagoria-structure 2", "expected 'flagoria-structure 1'"],
		["name: guard_post", "name: Guard Post", "name must match"],
		["anchor: 2,3\n", "", "missing 'anchor:'"],
		["  ##G##\n", "  ##G##\n  #####\n", "object: 5 rows, size says 4"],
	]
	for c in cases:
		var errors := _structure_errors(good.replace(c[0], c[1]))
		if errors.size() != 1 or not c[2] in errors[0]:
			printerr("FAIL structure_rejects want '%s', got %s" % [c[2], errors])
			fail += 1
	var empty := _structure_errors("flagoria-structure 1\nname: x\nversion: 1\nsize: 1x1\nanchor: 0,0\nlegend:\nobject:\n  .\n")
	if empty.size() != 1 or not "object layer is empty" in empty[0]:
		printerr("FAIL structure_rejects want 'object layer is empty', got %s" % [empty])
		fail += 1
	if fail == 0:
		print("PASS test_structure_rejects (%d cases)" % (cases.size() + 1))
	return fail


func _test_structure_export_filter() -> int:
	## Android exports use "all_resources", which leaves .txt files out of the
	## APK unless every preset includes structures/*.txt.
	print("-- test_structure_export_filter")
	var presets := ConfigFile.new()
	if presets.load("res://export_presets.cfg") != OK:
		printerr("FAIL structure_export_filter: cannot read export_presets.cfg")
		return 1
	var fail := 0
	for section in presets.get_sections():
		if section.count(".") != 1:
			continue
		var filters := str(presets.get_value(section, "include_filter", "")).split(",", false)
		if not "structures/*.txt" in Array(filters).map(func(f): return f.strip_edges()):
			printerr("FAIL structure_export_filter: %s include_filter lacks structures/*.txt" % section)
			fail += 1
	if fail == 0:
		print("PASS test_structure_export_filter")
	return fail
