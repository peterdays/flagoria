class_name StructureSaves
extends RefCounted
## Placed structures and free-form walls in world saves (world.structures,
## #42; docs/world-saves.md). A placement is an entry on its anchor cell
## ({"structure", "owner", "order"}), a free-form wall an entry on its cell
## ({"wall": "palisade"}). Tower ownership is the placement's owner, so flag
## colours and cities (rebuilt from the towers and walls) come back with them.
## Host alone: a joining peer gets the restored list with the map (#278).

const _WorldMap := preload("res://Scripts/TileMap.gd")

const PALISADE := "palisade"


static func to_changes(map: _WorldMap) -> Dictionary[String, Dictionary]:
	## The map's placements and free-form walls as world.structures entries.
	var out: Dictionary[String, Dictionary] = {}
	var order := 0
	for entry in map.structures_for_sync():  # [name, owner, anchor, rotation?] in id order
		var cell_data := {"structure": entry[0], "owner": entry[1], "order": order}
		if entry.size() >= 4 and int(entry[3]) != 0:
			cell_data["rotation"] = int(entry[3])
		_put(out, entry[2], cell_data)
		order += 1
	for cell: Vector2i in map._walls._wall_cells:
		_put(out, cell, {"wall": PALISADE})
	return out


static func restore(changes: Dictionary, map: _WorldMap) -> int:
	## Put back the placements, then the free-form walls (so they join the
	## structure walls), from to_changes entries. Call it after the params are
	## applied, before any chunk is drawn. A placement naming no shipped
	## structure, a wall on a cell that no longer generates land, and bad keys
	## are dropped; other entries are left alone. Returns placements + walls.
	var cities := map.get_parent().get_node_or_null("Cities") as Cities
	if cities != null and not changes.is_empty():
		cities.on_world_cleared()
	var placed := []
	var walls: Array[Vector2i] = []
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			var cell = WorldSave.parse_cell(str(key))
			if cell == null or not entry is Dictionary:
				continue
			if entry.get("structure") is String and StructurePlacer.load_named(entry["structure"]) != null:
				var turns := int(entry.get("rotation", 0))
				placed.append([int(entry.get("order", 0)), entry["structure"], int(entry.get("owner", 0)), cell, turns])
			elif entry.get("wall") == PALISADE and map.ground_is_walkable(map.predict_cell(cell)[0]):
				walls.append(cell)
	placed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var list := placed.map(func(p: Array) -> Array:
		var row: Array = [p[1], p[2], p[3]]
		if p.size() >= 5 and int(p[4]) != 0:
			row.append(int(p[4]))
		return row)
	var count: int = map.replace_structures(list) if not list.is_empty() else 0
	if not walls.is_empty() and map.place_wall_cells(walls):
		count += walls.size()
	if count > 0 and cities != null:
		cities.refresh_after_structure_restore()
	return count


static func adopt_start_castle(map: _WorldMap, owner: int) -> bool:
	## When a restored save already holds peer `owner`'s castle, make its gate
	## front the spawn (as place_start_castle does) and return true, so no
	## second castle is placed on a loaded world.
	var placements := map.placed_structures()
	var ids := placements.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = placements[id]
		if p["name"] == StartCastle.structure().name and p["owner"] == owner:
			map._castle_front = p["anchor"] + StartCastle.GATE_FRONT
			map.spawn_point = map._castle_front
			return true
	return false


static func _put(out: Dictionary, cell: Vector2i, entry: Dictionary) -> void:
	var chunk := WorldSave.chunk_key(cell)
	if not out.has(chunk):
		out[chunk] = {}
	out[chunk][WorldSave.cell_key(cell)] = entry
