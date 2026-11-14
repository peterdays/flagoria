class_name LandScore
extends Node2D
## Score is the land inside your city walls that a flag tower of yours
## actually covers (#279). Each owned flag covers a disk of `range_cells`
## (Euclidean, in cells). An interior cell counts once when it sits in a
## city you own and inside that disk. Cells in the city but outside every
## such disk do not count. The host applies the count through Points
## (`set_land`, reason `land`), which replaces the flags-held timer while
## `enabled` is true. A tap on a flag cell selects that tower and draws the
## disk. Clients draw the ring locally; they do not award.

## Default disk. A starting castle's flag sits at most 2 cells from any
## courtyard cell, so 5 covers that courtyard. A wider city needs another
## tower. Flags-held stays available when `enabled` is false.
static var range_cells := 5
static var enabled := true

const RING := Color(0.98, 0.86, 0.32, 0.95)
const RING_FILL := Color(0.98, 0.86, 0.32, 0.16)

@export var points_path := NodePath("../../Points")
@export var map_path := NodePath("../worldMap")
@export var cities_path := NodePath("../Cities")

var selected_tower := -1
var _seen := {}  ## peer id -> true once land was applied, so a drop to 0 still syncs
@onready var _map: TileMap = get_node_or_null(map_path)
@onready var _cities: Cities = get_node_or_null(cities_path)


func _ready() -> void:
	z_index = 12  # over the city tint, under nothing the player aims with


func _physics_process(_delta: float) -> void:
	tick()
	if selected_tower >= 0:
		queue_redraw()


func tick() -> void:
	## Host: rebuild cities if they are stale, then set each player's land
	## count. A client returns without awarding. Tests call this directly.
	if not enabled or not multiplayer.is_server():
		return
	var points: Points = get_node_or_null(points_path)
	if points == null or _map == null or _cities == null or _map._structures == null:
		return
	_cities.tick()
	var counts := covered_counts()
	var peers := {}
	for id in counts:
		peers[int(id)] = true
	for id in _seen:
		peers[int(id)] = true
	for id in peers:
		var cells := int(counts.get(id, 0))
		points.set_land(int(id), cells)
		if cells > 0:
			_seen[int(id)] = true
		else:
			_seen.erase(int(id))


func covered_of(peer_id: int) -> int:
	return int(covered_counts().get(peer_id, 0))


func covered_counts() -> Dictionary:
	## peer id -> interior cells of that peer's cities inside one of their
	## flag disks. A cell in two of their cities counts once.
	var out := {}
	if _map == null or _cities == null or _map._structures == null:
		return out
	var towers: Dictionary = _map._structures.towers()
	var placed: Dictionary = _map._structures.placements()
	var origins := {}
	for id in towers:
		var owner := int(placed.get(id, {}).get("owner", 0))
		if owner <= 0:
			continue
		if not origins.has(owner):
			origins[owner] = []
		for cell in towers[id]:
			origins[owner].append(cell)
	var r2 := range_cells * range_cells
	for city_id in _cities.cities:
		var owner := _cities.owner_of(int(city_id))
		if owner <= 0 or not origins.has(owner):
			continue
		var seen: Dictionary = out.get(owner, {})
		for cell in _cities.cities[city_id]["interior"]:
			if seen.has(cell):
				continue
			if _in_disk(cell, origins[owner], r2):
				seen[cell] = true
		out[owner] = seen
	var counts := {}
	for owner in out:
		counts[int(owner)] = int(out[owner].size())
	return counts


func select_cell(cell: Vector2i) -> int:
	## Select the flag tower on `cell`, or clear the ring when it is not a
	## flag. Returns the tower id, or -1.
	selected_tower = _tower_at(cell)
	queue_redraw()
	return selected_tower


func ring_radius_px() -> float:
	var tile := 16.0
	if _map != null and _map.tile_set != null:
		tile = float(_map.tile_set.tile_size.x)
	return float(range_cells) * tile


func _unhandled_input(event: InputEvent) -> void:
	## A tap on a flag cell selects that tower. Other touches are left alone,
	## so a swing or a build drag still happens.
	if _map == null or not event is InputEventScreenTouch or not event.pressed:
		return
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var cell := _map.local_to_map(_map.to_local(world_pos))
	if _tower_at(cell) < 0:
		return
	select_cell(cell)
	get_viewport().set_input_as_handled()


func _draw() -> void:
	if selected_tower < 0 or _map == null or _map._structures == null:
		return
	var towers: Dictionary = _map._structures.towers()
	if not towers.has(selected_tower) or towers[selected_tower].is_empty():
		return
	var flag: Vector2i = towers[selected_tower][0]
	var centre := to_local(_map.to_global(_map.map_to_local(flag)))
	var radius := ring_radius_px()
	draw_circle(centre, radius, RING_FILL)
	draw_arc(centre, radius, 0.0, TAU, 64, RING, 2.0, true)


func _tower_at(cell: Vector2i) -> int:
	if _map == null or _map._structures == null:
		return -1
	var towers: Dictionary = _map._structures.towers()
	for id in towers:
		for flag in towers[id]:
			if flag == cell:
				return int(id)
	return -1


func _in_disk(cell: Vector2i, flags: Array, r2: int) -> bool:
	for flag in flags:
		var d: Vector2i = cell - flag
		if d.x * d.x + d.y * d.y <= r2:
			return true
	return false
