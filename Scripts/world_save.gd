class_name WorldSave
extends RefCounted
## One saved world in memory: the generation inputs plus what was done to the
## world and by the player since it was generated. MapSave reads and writes
## it; docs/world-saves.md describes the file.
##
## Terrain is never stored: the generator rebuilds it from params. The change
## sections are sparse deltas against that generated world, keyed by chunk
## ("cx,cy") and then by cell, so a large world with a few changes stays
## small. They are empty until the features that fill them land.

## Change sections inside "world", in file order.
const WORLD_SECTIONS: Array[String] = ["tile_edits", "object_changes", "structures"]
## Side of a save chunk in cells. Chunk keys in the change sections use this
## fixed grid, not the map's chunk_width and chunk_height (draw sizes that
## the map params can change).
const CHUNK_SIZE := 32

## Generation inputs, seeds resolved.
var params: MapGenParams
## Changed tiles (#41): chunk -> {cell: tile}.
var tile_edits: Dictionary[String, Dictionary] = {}
## Changed world objects (#198): chunk -> {cell: change}.
var object_changes: Dictionary[String, Dictionary] = {}
## Placed structures (#42): chunk -> {cell: structure}.
var structures: Dictionary[String, Dictionary] = {}
## The player's own progress (#197).
var player: Dictionary = {}


func _init(inputs: MapGenParams = null) -> void:
	params = inputs


func world_to_dict() -> Dictionary:
	var out := {}
	for section in WORLD_SECTIONS:
		out[section] = get(section)
	return out


func world_from_dict(data: Dictionary) -> String:
	## Fills the change sections from a parsed "world" object; returns "" or
	## an error. A missing section is empty; one of the wrong shape is an error.
	for section in WORLD_SECTIONS:
		var chunks = data.get(section, {})
		if not chunks is Dictionary:
			return "world.%s is not an object" % section
		for chunk in chunks:
			if not chunks[chunk] is Dictionary:
				return "world.%s[%s] is not an object" % [section, chunk]
		(get(section) as Dictionary).assign(chunks)
	return ""


static func chunk_key(cell: Vector2i) -> String:
	## "cx,cy" of the save chunk that holds `cell` (CHUNK_SIZE cells a side).
	return "%d,%d" % [floori(cell.x / float(CHUNK_SIZE)), floori(cell.y / float(CHUNK_SIZE))]


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func parse_cell(key: String) -> Variant:
	## The Vector2i a cell_key names, or null when `key` is not "x,y".
	var parts := key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(parts[0].to_int(), parts[1].to_int())


static func split_changes(changes: Dictionary, per_part: int) -> Array[Dictionary]:
	## `changes` (chunk -> {cell: entry}) cut into parts of at most
	## `per_part` cell entries each, in the same chunk -> cell shape; always
	## at least one part (empty when `changes` is). Used for the join cut list
	## (#354).
	var parts: Array[Dictionary] = [{}]
	var in_part := 0
	for chunk in changes:
		for key in changes[chunk]:
			if in_part == per_part:
				parts.append({})
				in_part = 0
			if not parts[-1].has(chunk):
				parts[-1][chunk] = {}
			parts[-1][chunk][key] = changes[chunk][key]
			in_part += 1
	return parts
