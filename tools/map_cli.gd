class_name MapCli
extends RefCounted
## The `map render` and `map stats` commands of tools/cli.gd. Both generate
## the origin chunk (chunk_width x chunk_height of the params) with
## worldMap.generate_chunk, the way the game does, and read back the placed
## tiles. Same params and seed give byte-identical output.

const USAGE := """usage: godot --headless --path . --script res://tools/cli.gd -- <command> [options]
  map render [--params <file>|default] [--seed <n>] [--format ascii] [--out <path>]
  map stats  [--params <file>|default] [--seed <n>] [--out <path>]
--params: a map save (.json, see MapSave) or "default" (the default).
--seed n: altitude, moisture, temperature, items and biome seeds n .. n+4.
Without --seed every seed must come from --params.
Exit codes: 0 ok, 1 error, 2 bad usage."""

## ASCII legend: one character per tile type. A plant or stones is drawn
## instead of the ground under it.
const LEGEND := {
	"water": "~", "sand": ".", "swamp": "%", "swamp_special": "&", "grass": ",",
	"tree": "T", "bush": "b", "flower": "*", "stones": "o", "unknown": "?",
}


static func tile_names() -> Dictionary:
	## Atlas coords -> tile type name. The four grass variants are one type.
	return {
		TileCatalog.WATER: "water", TileCatalog.SAND: "sand", TileCatalog.SWAMP: "swamp",
		TileCatalog.SWAMP_SPECIAL: "swamp_special", TileCatalog.GRASS_A: "grass",
		TileCatalog.GRASS_B: "grass", TileCatalog.GRASS_C: "grass", TileCatalog.GRASS_D: "grass",
		TileCatalog.TREE: "tree", TileCatalog.BUSH: "bush", TileCatalog.FLOWER: "flower",
		TileCatalog.STONES: "stones",
	}


static func parse(args: PackedStringArray) -> Dictionary:
	## {"command", "options", "error"}; command is "map render" or "map stats".
	if args.size() < 2 or args[0] != "map" or not args[1] in ["render", "stats"]:
		return {"error": "unknown command '%s'" % " ".join(args)}
	var options := {"params": "default", "seed": "", "format": "ascii", "out": ""}
	var i := 2
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if not args[i].begins_with("--") or not options.has(key) or i + 1 >= args.size():
			return {"error": "bad option '%s'" % args[i]}
		options[key] = args[i + 1]
		i += 2
	if options["format"] != "ascii":
		return {"error": "--format %s is not supported yet (ascii only)" % options["format"]}
	return {"command": args[0] + " " + args[1], "options": options, "error": ""}


static func params_for(params_arg: String, seed_text: String) -> Dictionary:
	## {"params": MapGenParams or null, "error": String}.
	var params := MapGenParams.make_defaults()
	if params_arg != "default":
		var loaded := MapSave.load_map(params_arg)
		if loaded["error"] != "":
			return {"params": null, "error": loaded["error"]}
		params = loaded["params"]
	if seed_text != "":
		if not seed_text.is_valid_int() or seed_text.to_int() < 1:
			return {"params": null, "error": "--seed must be a positive whole number"}
		var n := seed_text.to_int()
		params.altitude_seed = n
		params.moisture_seed = n + 1
		params.temperature_seed = n + 2
		params.items_seed = n + 3
		params.biome_seed = n + 4
	for key in params.to_dict().keys():
		if key.ends_with("_seed") and params.get(key) == 0:
			return {"params": null, "error": "%s is 0 (random); pass --seed or a map save" % key}
	return {"params": params, "error": ""}


static func generate(world: Node, params: MapGenParams) -> Array:
	## Rows of tile type names over the origin chunk, top row first.
	world.apply_map_params(params)
	world.generate_chunk(Vector2(0, 0))
	var names := tile_names()
	var rows := []
	for y in range(-params.chunk_height / 2, params.chunk_height - params.chunk_height / 2):
		var row := []
		for x in range(-params.chunk_width / 2, params.chunk_width - params.chunk_width / 2):
			var cell := Vector2i(x, y)
			var top: Vector2i = world.get_cell_atlas_coords(1, cell)
			if top == Vector2i(-1, -1):
				top = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell)
			var ground: String = names.get(world.get_cell_atlas_coords(0, cell), "unknown")
			row.append([ground, names.get(top, "unknown") if top != Vector2i(-1, -1) else ""])
		rows.append(row)
	return rows


static func ascii(rows: Array) -> String:
	var lines := PackedStringArray()
	for row in rows:
		var line := ""
		for cell in row:
			line += LEGEND[cell[1] if cell[1] != "" else cell[0]]
		lines.append(line)
	return "\n".join(lines) + "\n"


static func stats(rows: Array) -> String:
	## JSON: tile type counts (ground and plants), water/land ratio, island
	## count (4-connected land) and tree/bush density per land cell.
	var counts := {}
	var land := {}
	for y in rows.size():
		for x in rows[y].size():
			for name in rows[y][x]:
				if name != "":
					counts[name] = counts.get(name, 0) + 1
			if rows[y][x][0] != "water":
				land[Vector2i(x, y)] = true
	var islands := 0
	var seen := {}
	for start in land.keys():
		if seen.has(start):
			continue
		islands += 1
		var stack := [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if land.has(c + d) and not seen.has(c + d):
					seen[c + d] = true
					stack.append(c + d)
	var land_cells := land.size()
	var water_cells: int = counts.get("water", 0)
	var data := {
		"width": rows[0].size() if rows.size() > 0 else 0,
		"height": rows.size(),
		"tiles": counts,
		"land_cells": land_cells,
		"water_cells": water_cells,
		"water_land_ratio": snappedf(float(water_cells) / land_cells, 0.0001) if land_cells > 0 else null,
		"islands": islands,
		"tree_density": snappedf(float(counts.get("tree", 0)) / land_cells, 0.0001) if land_cells > 0 else 0.0,
		"bush_density": snappedf(float(counts.get("bush", 0)) / land_cells, 0.0001) if land_cells > 0 else 0.0,
	}
	return JSON.stringify(data, "\t", true) + "\n"
