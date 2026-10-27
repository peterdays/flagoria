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
