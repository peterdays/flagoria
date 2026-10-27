class_name DiscoveryPoints
extends Node
## Pays Points.DISCOVERY_POINTS to the first player in this world to stand in
## each map chunk. The map is split into a fixed grid of chunks the size of
## the generation window (chunk_width x chunk_height cells). Only the server
## decides: it looks at every living player's position each CHECK_FRAMES
## physics frames, and a chunk counts once a player is seen in it on two
## checks in a row. A synced position can be briefly stale (a client's own
## player arrives at (0, 0) before it is placed), so one sample alone never
## pays. Each chunk pays once per world; a new map starts over.

const CHECK_FRAMES := 15

@export var points_path := NodePath("../Points")
@export var world_path := NodePath("../World")
@export var map_path := NodePath("../World/worldMap")

var _discovered := {}  ## chunk (Vector2i) -> peer id of its discoverer
var _last_chunk := {}  ## peer id -> chunk it was in at the previous check
var _frames := 0


func _ready() -> void:
	var map := get_node_or_null(map_path)
	if map and map.has_signal("ground_changed"):
		map.ground_changed.connect(_on_ground_changed)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < CHECK_FRAMES:
		return
	_frames = 0
	check_players()


func check_players() -> void:
	## Server: one check of every living player's chunk.
	if not multiplayer.is_server():
		return
	var world := get_node_or_null(world_path)
	var map: TileMap = get_node_or_null(map_path)
	if world == null or map == null:
		return
	for child in world.get_children():
		if not child is CharacterBody2D or not str(child.name).is_valid_int():
			continue
		var health = child.get_node_or_null("Health")
		if health and health.is_dead():
			_last_chunk.erase(str(child.name).to_int())
			continue
		observe(str(child.name).to_int(), chunk_of(map.local_to_map(child.position), map))


func observe(peer_id: int, chunk: Vector2i) -> bool:
	## Server: peer_id was seen in chunk. Pays and returns true when this is
	## the second check in a row in a chunk no one has discovered yet.
	if not multiplayer.is_server():
		return false
	var stayed: bool = _last_chunk.get(peer_id) == chunk
	_last_chunk[peer_id] = chunk
	if not stayed or _discovered.has(chunk):
		return false
	var points: Points = get_node_or_null(points_path)
	if points == null or not points.award(peer_id, Points.DISCOVERY_POINTS, "discovery"):
		return false
	_discovered[chunk] = peer_id
	return true


func discoverer_of(chunk: Vector2i) -> int:
	## Peer id that discovered chunk, or 0.
	return _discovered.get(chunk, 0)


static func chunk_of(cell: Vector2i, map: Node) -> Vector2i:
	## The grid chunk holding cell, chunks being the map's chunk size.
	var w: int = maxi(1, map.chunk_width)
	var h: int = maxi(1, map.chunk_height)
	return Vector2i(floori(cell.x / float(w)), floori(cell.y / float(h)))


func _on_ground_changed(cells: Rect2i) -> void:
	# An empty rect means the map was cleared for new parameters: a new world.
	if cells.has_area():
		return
	_discovered.clear()
	_last_chunk.clear()
