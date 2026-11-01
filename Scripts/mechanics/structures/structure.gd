class_name Structure
extends RefCounted
## A small hand-drawn structure (guard post, wall piece, camp) in the plain-text
## `flagoria-structure 1` format: header, one shared legend, then a `ground`
## and an `object` layer of rows. Tiles are named by TileCatalog, never by
## atlas cell. parse() is lenient about pasted text; to_text() is canonical,
## so parse(text).to_text() == text for every canonical file.

const MAGIC := "flagoria-structure 1"
const MAX_SIZE := 16
const EMPTY := "."
const LAYERS := ["ground", "object"]
const ATTRIBUTES := ["auto", "team"]
## The palette: the only tiles each layer may use. Wall pieces, gate variants
## and team colours are chosen by the game when a structure is placed.
const ALLOWED := {
	"ground": ["GRASS_A", "GRASS_B", "GRASS_C", "GRASS_D", "SAND", "STONES", "FLOWER"],
	"object": ["WALL_H", "WALL_GATE_H", "WALL_POST", "PROP_FLAG_BLUE", "BUSH", "TREE", "TREE_PINE_SMALL"],
}

var name := ""
var version := 1
var size := Vector2i.ONE
var anchor := Vector2i.ZERO
var tags: PackedStringArray = []
var comments: PackedStringArray = []
## Legend character -> {"tile": String, "attributes": PackedStringArray}.
var legend := {}
## Layer name -> PackedStringArray of size.y rows, each size.x characters.
var layers := {"ground": PackedStringArray(), "object": PackedStringArray()}


static func parse(text: String) -> Dictionary:
	## {"structure": Structure or null, "errors": Array[String]}. Accepts CRLF,
	## any indentation, blank lines and ``` fences. Each error names its line.
	var s := Structure.new()
	var errors: Array[String] = []
	var lines: Array = []
	var number := 0
	for raw in text.replace("\r\n", "\n").split("\n"):
		number += 1
		var line := raw.strip_edges()
		if line != "" and not line.begins_with("```"):
			lines.append([number, line])
	if lines.is_empty() or lines[0][1] != MAGIC:
		errors.append("line 1: expected '%s'" % MAGIC)
		return {"structure": null, "errors": errors}
	var seen := {}
	var section := ""
	for entry in lines.slice(1):
		var at := "line %d: " % entry[0]
		var line: String = entry[1]
		if line.begins_with(";"):
			s.comments.append(line)
		elif line == "legend:" or line.trim_suffix(":") in LAYERS and line.ends_with(":"):
			section = line.trim_suffix(":")
			if seen.has(section):
				errors.append(at + "'%s' appears twice" % line)
			seen[section] = true
		elif section in LAYERS:
			s.layers[section].append(line)
		elif section == "legend":
			var m := RegEx.create_from_string("^(\\S+)\\s*=\\s*([A-Z0-9_]+)((?:\\s+\\S+)*)$").search(line)
			if m == null:
				errors.append(at + "legend entries look like 'c = TILE_NAME [auto] [team]'")
				continue
			var c := m.get_string(1)
			var attrs := m.get_string(3).strip_edges().split(" ", false)
			if c.length() != 1 or c == EMPTY or c == ";" or c.unicode_at(0) < 33 or c.unicode_at(0) > 126:
				errors.append(at + "legend character '%s' must be one printable ASCII character other than '.' and ';'" % c)
			elif s.legend.has(c):
				errors.append(at + "legend character '%s' is defined twice" % c)
			elif not TileCatalog.TILES.has(m.get_string(2)):
				errors.append(at + "unknown tile %s" % m.get_string(2))
			for a in attrs:
				if not a in ATTRIBUTES:
					errors.append(at + "unknown attribute '%s' (allowed: %s)" % [a, ", ".join(ATTRIBUTES)])
			s.legend[c] = {"tile": m.get_string(2), "attributes": attrs}
		else:
			var key := line.get_slice(":", 0).strip_edges()
			var value := line.trim_prefix(key).trim_prefix(":").strip_edges()
			if seen.has(key):
				errors.append(at + "'%s' appears twice" % key)
			seen[key] = true
			match key:
				"name":
					s.name = value
					if RegEx.create_from_string("^[a-z0-9_]+$").search(value) == null:
						errors.append(at + "name must match [a-z0-9_]+")
				"version":
					s.version = value.to_int()
					if not value.is_valid_int() or s.version < 1:
						errors.append(at + "version must be a whole number of at least 1")
				"size":
					var wh := value.split("x")
					s.size = Vector2i(wh[0].to_int(), wh[-1].to_int())
					if wh.size() != 2 or not wh[0].is_valid_int() or not wh[1].is_valid_int() \
							or s.size.x < 1 or s.size.y < 1 or s.size.x > MAX_SIZE or s.size.y > MAX_SIZE:
						errors.append(at + "size must be WxH with each side 1 to %d" % MAX_SIZE)
				"anchor":
					var xy := value.split(",")
					s.anchor = Vector2i(xy[0].to_int(), xy[-1].to_int())
					if xy.size() != 2 or not xy[0].strip_edges().is_valid_int() or not xy[1].strip_edges().is_valid_int():
						errors.append(at + "anchor must be x,y")
				"tags":
					for t in value.split(",", false):
						s.tags.append(t.strip_edges())
				_:
					errors.append(at + "unknown line '%s'" % line)
	for key in ["name", "version", "size", "anchor"]:
		if not seen.has(key):
			errors.append("missing '%s:'" % key)
	if not errors.is_empty():
		return {"structure": null, "errors": errors}
	if s.layers["ground"].is_empty():
		s.layers["ground"] = s._blank_rows()
	errors.append_array(s.validate())
	return {"structure": null if not errors.is_empty() else s, "errors": errors}


func validate() -> Array[String]:
	## Grid shape, anchor, legend use and the per-layer palette.
	var errors: Array[String] = []
	if not Rect2i(Vector2i.ZERO, size).has_point(anchor):
		errors.append("anchor %d,%d is outside the %dx%d grid" % [anchor.x, anchor.y, size.x, size.y])
	var used := {}
	for layer in LAYERS:
		var rows: PackedStringArray = layers[layer]
		if rows.size() != size.y:
			errors.append("%s: %d rows, size says %d" % [layer, rows.size(), size.y])
		for y in rows.size():
			if rows[y].length() != size.x:
				errors.append("%s row %d: %d characters, size says %d" % [layer, y + 1, rows[y].length(), size.x])
			for c in rows[y]:
				if c == EMPTY:
					continue
				if not legend.has(c) and not used.has(layer + c):
					errors.append("%s row %d: '%s' is not in the legend" % [layer, y + 1, c])
				elif legend.has(c) and not legend[c]["tile"] in ALLOWED[layer] and not used.has(layer + c):
					errors.append("%s row %d: %s is not allowed on the %s layer" % [layer, y + 1, legend[c]["tile"], layer])
				used[c] = true
				used[layer + c] = true
	for c in legend:
		if not used.has(c):
			errors.append("legend character '%s' is never used" % c)
	if "\n".join(layers["object"]).replace(EMPTY, "").replace("\n", "") == "":
		errors.append("the object layer is empty")
	return errors


func to_text() -> String:
	## Canonical text: LF, keys in a fixed order, legend sorted by character,
	## an all-empty ground layer left out, and a trailing newline.
	var out := [MAGIC, "name: " + name, "version: %d" % version,
		"size: %dx%d" % [size.x, size.y], "anchor: %d,%d" % [anchor.x, anchor.y]]
	if not tags.is_empty():
		out.append("tags: " + ", ".join(tags))
	out.append_array(comments)
	out.append("legend:")
	var chars := legend.keys()
	chars.sort()
	for c in chars:
		out.append("  %s = %s" % [c, " ".join([legend[c]["tile"]] + Array(legend[c]["attributes"]))])
	for layer in LAYERS:
		if layer == "ground" and layers[layer] == _blank_rows():
			continue
		out.append(layer + ":")
		for row in layers[layer]:
			out.append("  " + row)
	return "\n".join(out) + "\n"


func _blank_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for y in size.y:
		rows.append(EMPTY.repeat(size.x))
	return rows
