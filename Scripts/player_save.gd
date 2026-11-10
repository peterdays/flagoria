class_name PlayerSave
extends RefCounted
## The player section of a world save (#197): where this peer is, their
## health, wood, score, charted ground and the chunks that already paid
## discovery points. Held items are not stored; there are none yet.
##
## An empty section, or a section a file does not have, is the default
## player: the map's spawn, full health, no wood, no score, nothing charted.
## A bad value on one key falls back to that default and the rest still load.
## docs/world-saves.md describes the keys. The container (MapSave) stores the
## object as it was written.


static func capture(game: Node) -> Dictionary:
	## The player section for the world `game` is playing.
	var body := _body(game)
	var who := _who(body)
	var out := {
		"wood": _wood_of(game),
		"score": _score_of(game, who),
		"charted": _chart_to_dict(_chart(game)),
		"discovered": _found(game),
	}
	if body is Node2D:
		out["position"] = [body.position.x, body.position.y]
		var health := body.get_node_or_null("Health")
		if health:
			out["health"] = int(health.health)
	return out


static func position_of(data: Dictionary) -> Variant:
	## The saved world position, or null when the section does not name one
	## (the player then uses the map's spawn).
	var raw = data.get("position", null)
	if not raw is Array or raw.size() != 2 or not _is_number(raw[0]) or not _is_number(raw[1]):
		return null
	return Vector2(float(raw[0]), float(raw[1]))


static func apply(game: Node, body: Node, data: Dictionary) -> void:
	## Puts `data` onto `body` and the scene-level wood, score, chart and
	## discovery set. Missing and bad keys become the default player.
	var who := _who(body)
	_apply_chart(game, data.get("charted", {}))
	_apply_wood(game, data.get("wood", 0))
	_apply_score(game, who, data.get("score", 0))
	_apply_found(game, data.get("discovered", {}))
	if body is Node2D:
		var at: Variant = position_of(data)
		if at is Vector2:
			body.position = at
		var health := body.get_node_or_null("Health")
		if health and health.has_method("set_health_now"):
			health.set_health_now(_health_of(data.get("health", null), int(health.max_health)))


static func _body(game: Node) -> Node:
	var world := game.get_node_or_null("World")
	if world == null:
		return null
	var id := "1"
	if game.multiplayer:
		id = str(game.multiplayer.get_unique_id())
	var body := world.get_node_or_null(id)
	return body if body is Node2D else null


static func _who(body: Node) -> int:
	if body and str(body.name).is_valid_int():
		return int(str(body.name))
	return 1


static func _chart(game: Node) -> ExploredMap:
	var panel := game.get_node_or_null("CanvasLayer1/MinimapPanel")
	if panel == null:
		return null
	return panel.explored


static func _chart_to_dict(chart: ExploredMap) -> Dictionary:
	var out := {}
	if chart == null:
		return out
	for chunk in chart.chunks():
		var bits := chart.chunk_bits(chunk)
		if bits.size() != ExploredMap.CHUNK_BYTES:
			continue
		# The key is the chunk index, the same "cx,cy" the chart uses.
		out[WorldSave.cell_key(chunk)] = Marshalls.raw_to_base64(bits)
	return out


static func _chart_from_dict(data) -> Dictionary:
	## chunk (Vector2i) -> bitset. A bad chunk is dropped.
	var out := {}
	if not data is Dictionary:
		return out
	for key in data:
		var chunk: Variant = WorldSave.parse_cell(str(key))
		if chunk == null or not data[key] is String:
			continue
		var bits := Marshalls.base64_to_raw(data[key])
		if bits.size() != ExploredMap.CHUNK_BYTES:
			continue
		out[chunk] = bits
	return out


static func _apply_chart(game: Node, data) -> void:
	var panel := game.get_node_or_null("CanvasLayer1/MinimapPanel")
	if panel and panel.has_method("restore_chart"):
		panel.restore_chart(_chart_from_dict(data))


static func _wood_of(game: Node) -> int:
	var inventory := game.get_node_or_null("Inventory")
	return int(inventory.count_of(Inventory.WOOD)) if inventory else 0


static func _apply_wood(game: Node, value) -> void:
	var inventory := game.get_node_or_null("Inventory")
	if inventory == null:
		return
	var want := maxi(_whole(value, 0), 0)
	var have: int = inventory.count_of(Inventory.WOOD)
	if want > have:
		inventory.add(Inventory.WOOD, want - have)
	elif have > want:
		inventory.spend(Inventory.WOOD, have - want)


static func _score_of(game: Node, who: int) -> int:
	var points := game.get_node_or_null("Points")
	return int(points.total_of(who)) if points else 0


static func _apply_score(game: Node, who: int, value) -> void:
	var points := game.get_node_or_null("Points")
	if points and points.has_method("restore_total"):
		points.restore_total(who, maxi(_whole(value, 0), 0))


static func _found(game: Node) -> Dictionary:
	var discovery := game.get_node_or_null("Discovery")
	return discovery.save_found() if discovery and discovery.has_method("save_found") else {}


static func _apply_found(game: Node, data) -> void:
	var discovery := game.get_node_or_null("Discovery")
	if discovery and discovery.has_method("restore_found"):
		discovery.restore_found(data if data is Dictionary else {})


static func _health_of(value, max_health: int) -> int:
	var n := _whole(value, -1)
	if n < 0 or n > max_health:
		return max_health
	return n


static func _whole(value, fallback: int) -> int:
	## JSON reads numbers as floats. A whole number of either type counts;
	## anything else uses `fallback`.
	if _is_number(value) and float(value) == floorf(float(value)):
		return int(value)
	return fallback


static func _is_number(value) -> bool:
	return value is int or value is float
