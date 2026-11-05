class_name Cities
extends Node2D
## Closed wall loops around a flag tower make a city (#277). For each placement
## with a team flag, a flood fill from the flag through non-barrier cells finds
## the enclosed region. Barriers are free-form walls and structure WALL_* /
## PALISADE_* cells (including gates). Water and map edges do not close a city:
## reaching either means the region is open (Pedro card t293s1076).
## City record: tower id, wall cells, interior cells. Owner follows the tower's
## owner (capture via #274 transfers the city). Breaking the loop dissolves it.
## Boundary tint is drawn here; the minimap paints the same walls.
## Host alone only: while multiplayer is on the list stays empty (sync is #278).

const STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const CHECK_FRAMES := 15
const MAX_FLOOD := 8000
const TINT := {
	1: Color(0.23, 0.44, 0.88, 0.35),
	StructurePlacer.OWNER_MOBS: Color(0.61, 0.33, 0.77, 0.35),
	StructurePlacer.OWNER_NEUTRAL: Color(0.55, 0.55, 0.6, 0.35),
}
const TINT_OTHER := Color(0.88, 0.29, 0.29, 0.35)

## tower id -> {"walls": Dictionary cell->true, "interior": Dictionary cell->true}
var cities: Dictionary = {}
@onready var _map: TileMap = get_node_or_null("../worldMap")
var _frames := 0
var _stamp := 0


func _ready() -> void:
	z_index = 9  # under capture bars (10), over walls


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames % CHECK_FRAMES != 0:
		return
	var changed := tick()
	# Redraw whenever cities exist so a capture retints without geometry change.
	if changed or not cities.is_empty():
		queue_redraw()


func tick() -> bool:
	## Rebuild when walls or placements change. Returns whether the city list
	## changed. Tests call this directly.
	if _map == null:
		return false
	if Interaction.multiplayer_on(multiplayer):
		if cities.is_empty():
			return false
		cities.clear()
		_stamp = 0
		return true
	var stamp := _geometry_stamp()
	if stamp == _stamp:
		return false
	_stamp = stamp
	return rebuild()


func rebuild() -> bool:
	## Scan every flag tower and replace `cities`. True when the set changed.
	var before := cities.duplicate(true)
	cities.clear()
	if _map == null or Interaction.multiplayer_on(multiplayer):
		return not before.is_empty()
	var towers: Dictionary = _map._structures.towers()
	for id: int in towers:
		var found := _city_from_tower(id, towers[id])
		if not found.is_empty():
			cities[id] = found
	return _cities_differ(before, cities)


func owner_of(tower_id: int) -> int:
	## Live owner of the city for `tower_id`, or 0 when there is no such city.
	if not cities.has(tower_id):
		return 0
	return _map._structures.placements().get(tower_id, {}).get("owner", 0)


func wall_cells() -> Dictionary:
	## Every city wall cell -> owning tower id (for the minimap).
	var out := {}
	for id: int in cities:
		for cell: Vector2i in cities[id]["walls"]:
			out[cell] = id
	return out


func _city_from_tower(id: int, flags: Array) -> Dictionary:
	## Flood from the tower's flag cells. Empty when the region escapes to
	## water or past the map edge, or when no wall barrier bounds it.
	if flags.is_empty():
		return {}
	var interior := {}
	var todo: Array[Vector2i] = []
	for f in flags:
		todo.append(f)
	var escaped := false
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		if interior.has(cell) or _is_barrier(cell):
			continue
		if _is_escape(cell):
			escaped = true
			break
		interior[cell] = true
		if interior.size() > MAX_FLOOD:
			escaped = true
			break
		for s in STEPS:
			todo.append(cell + s)
	if escaped or interior.is_empty():
		return {}
	var walls := {}
	for cell: Vector2i in interior:
		for s in STEPS:
			var n: Vector2i = cell + s
			if _is_barrier(n):
				walls[n] = true
	if walls.is_empty():
		return {}
	return {"walls": walls, "interior": interior}


func _is_barrier(cell: Vector2i) -> bool:
	## Free-form walls and structure WALL_* / PALISADE_* (gates included).
	if _map.has_wall(cell):
		return true
	if not _map._structures.has_cell(cell):
		return false
	var atlas: Vector2i = _map._structures.object_at(cell)
	if atlas == _map.NO_PLANT:
		return false
	return not WallBuilder._atlas_wall_name(atlas).is_empty()


func _is_escape(cell: Vector2i) -> bool:
	## Water / non-walkable ground, or past the archipelago world bound.
	var e: int = _map.archipelago_world_extent
	if _map.archipelago_spacing > 0 and e > 0 and (absi(cell.x) > e or absi(cell.y) > e):
		return true
	var p: Array = _map.predict_cell(cell)
	return not _map.ground_is_walkable(p[0])


func _geometry_stamp() -> int:
	var h: int = _map._walls._wall_cells.size() * 10007
	for cell: Vector2i in _map._walls._wall_cells:
		h = ((h * 31) + cell.x * 131 + cell.y) & 0x7fffffff
	var placed: Dictionary = _map._structures.placements()
	h = (h + placed.size() * 99991) & 0x7fffffff
	for id in placed:
		var a: Vector2i = placed[id]["anchor"]
		h = ((h * 17) + id * 101 + a.x * 13 + a.y + int(placed[id]["owner"]) * 7919) & 0x7fffffff
	return h


func _cities_differ(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return true
	for id in a:
		if not b.has(id):
			return true
		if a[id]["walls"].size() != b[id]["walls"].size():
			return true
		if a[id]["interior"].size() != b[id]["interior"].size():
			return true
	return false


func _draw() -> void:
	if _map == null:
		return
	var placed: Dictionary = _map._structures.placements()
	for id: int in cities:
		var owner: int = placed.get(id, {}).get("owner", 0)
		var colour: Color = TINT.get(owner, TINT_OTHER)
		for cell: Vector2i in cities[id]["walls"]:
			var centre := to_local(_map.to_global(_map.map_to_local(cell)))
			draw_rect(Rect2(centre - Vector2(8, 8), Vector2(16, 16)), colour)
