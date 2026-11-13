class_name TowerCapture
extends Node2D
## Flag towers change hands (#274): a placement's `team` flag is its tower.
## Living players (side = peer id) and mobs that are not dying (side
## StructurePlacer.OWNER_MOBS) inside CAPTURE_RADIUS of the flag cell's
## centre take part. Every tick, per tower:
## - the owner's side inside: progress pauses (a defender holds it);
## - two or more other sides inside: contested, progress freezes;
## - one other side inside: its progress grows; a side that is not the one
##   holding progress first drains the old progress to 0, then starts its own;
## - nobody inside: progress drains at the same rate.
## Progress reaching CAPTURE_TIME hands the tower to that side
## (StructurePlacer.set_owner: owner entry and flag colour only).
## Mobs have no seeking yet (#280); they count when they wander or chase in.
## In multiplayer only the host advances progress (#497). Clients apply
## receive_capture_state. A late joiner gets capture_snapshot from the host.
## Lives under World next to worldMap, Mobs and the players; draws the bars.
## The tower list is cached and refreshed on worldMap.ground_changed so a
## tick does not deep-copy placements()/towers(); players are gathered once
## per tick instead of scanning World children per tower (#378).

const CAPTURE_TIME := 5.0  ## s for one side alone to take a tower
const CAPTURE_RADIUS := 32.0  ## px (2 cells) from the flag cell's centre
const BAR_SIZE := Vector2(16, 3)  ## px, drawn above the flag cell
const BAR_OFFSET := Vector2(-8, -14)  ## px from the flag cell's centre
const BAR_BACK := Color(0.08, 0.07, 0.12, 0.85)
const BAR_COLOURS := {1: Color(0.23, 0.44, 0.88), StructurePlacer.OWNER_MOBS: Color(0.61, 0.33, 0.77)}
const BAR_OTHER := Color(0.88, 0.29, 0.29)

## Placement id -> {"side": the side the progress belongs to, "progress": s}.
## Only towers with progress above 0 are listed.
var progress: Dictionary = {}
## Placement id -> its `team` flag cells; refreshed on ground_changed.
var _towers: Dictionary = {}
@onready var _map: TileMap = get_node_or_null("../worldMap")
@onready var _mobs: Node = get_node_or_null("../Mobs")


func _ready() -> void:
	z_index = 10  # over the flag and wall layers
	if _map != null and _map.has_signal("ground_changed"):
		_map.ground_changed.connect(_on_ground_changed)
	_refresh_towers()


func _on_ground_changed(_cells: Rect2i) -> void:
	_refresh_towers()


func _refresh_towers() -> void:
	## One deep copy when the map's structures change; ticks read `_towers`.
	if _map == null or _map._structures == null:
		_towers = {}
		return
	_towers = _map._structures.towers()


func _physics_process(delta: float) -> void:
	if tick(delta):
		queue_redraw()


func tick(delta: float) -> bool:
	## Advance every tower by `delta` s. Returns whether any progress changed.
	## A client does not advance: it shows the host's snapshot.
	if _map == null:
		return false
	if Interaction.multiplayer_on(multiplayer) and not multiplayer.is_server():
		return false
	var placer: StructurePlacer = _map._structures
	var players := _player_list()
	var changed := false
	for id: int in _towers:
		var sides := sides_near(_centre(_towers[id][0]), players)
		changed = _step(placer, id, placer.owner_of(id), sides, delta) or changed
	for id in progress.keys():
		if not _towers.has(id):
			progress.erase(id)
	if changed and Interaction.multiplayer_on(multiplayer) and multiplayer.is_server():
		receive_capture_state.rpc(capture_snapshot())
	return changed


func capture_snapshot() -> Array:
	## `[id, owner, side, progress]` for every flag tower. Progress is 0 and
	## side is the owner when nobody is capturing. The join snapshot and each
	## live update use this.
	_refresh_towers()
	if _map == null or _map._structures == null:
		return []
	var placer: StructurePlacer = _map._structures
	var out := []
	for id: int in _towers:
		var owner := placer.owner_of(id)
		var state: Dictionary = progress.get(id, {})
		out.append([id, owner, int(state.get("side", owner)), float(state.get("progress", 0.0))])
	return out


func sync_to_peer(peer_id: int) -> void:
	## Host: send the current owner and progress to a peer that just joined.
	if multiplayer.is_server():
		receive_capture_state.rpc_id(peer_id, capture_snapshot())


@rpc("authority", "reliable", "call_remote")
func receive_capture_state(entries: Array) -> void:
	## Owner and progress the host decided. Ignored unless peer 1 sent it.
	if multiplayer.get_remote_sender_id() != 1:
		return
	if _map == null or _map._structures == null:
		return
	var seen := {}
	for entry in entries:
		if not entry is Array or entry.size() < 4:
			continue
		var id := int(entry[0])
		var owner := int(entry[1])
		var side := int(entry[2])
		var prog := float(entry[3])
		seen[id] = true
		if _map._structures.owner_of(id) != 0 and _map._structures.owner_of(id) != owner:
			_map._structures.set_owner(id, owner)
		if prog <= 0.0:
			progress.erase(id)
		else:
			progress[id] = {"side": side, "progress": prog}
	for id in progress.keys():
		if not seen.has(id):
			progress.erase(id)
	queue_redraw()


func _step(placer: StructurePlacer, id: int, owner: int, sides: Dictionary, delta: float) -> bool:
	var state: Dictionary = progress.get(id, {"side": owner, "progress": 0.0})
	var before: float = state["progress"]
	var attackers := sides.keys().filter(func(s: int) -> bool: return s != owner)
	if sides.has(owner) or attackers.size() >= 2:
		return false  # held by a defender, or contested
	if attackers.size() == 1 and (state["side"] == attackers[0] or before <= 0.0):
		state = {"side": attackers[0], "progress": before + delta}
	else:
		state["progress"] = maxf(0.0, before - delta)
	if state["progress"] >= CAPTURE_TIME:
		placer.set_owner(id, state["side"])
		progress.erase(id)
	elif state["progress"] <= 0.0:
		progress.erase(id)
	else:
		progress[id] = state
	return state["progress"] != before


func _player_list() -> Array:
	## Living peer-named player bodies under World (one scan per tick).
	var out: Array = []
	var world := get_parent()
	if world == null:
		return out
	for node in world.get_children():
		if node is CharacterBody2D and Mob.is_alive(node) and str(node.name).is_valid_int():
			out.append(node)
	return out


func sides_near(centre: Vector2, players: Variant = null) -> Dictionary:
	## Side -> true for every living player and live mob within CAPTURE_RADIUS
	## of `centre` (world px). Pass the list from `_player_list` so a tick
	## scans World children once; omit it for a one-off call.
	var out := {}
	var list: Array = players if players is Array else _player_list()
	for node in list:
		if node.global_position.distance_to(centre) <= CAPTURE_RADIUS:
			out[int(str(node.name))] = true
	if _mobs != null:
		for node in _mobs.get_children():
			if node is Mob and node.state != Mob.State.DYING \
					and node.global_position.distance_to(centre) <= CAPTURE_RADIUS:
				out[StructurePlacer.OWNER_MOBS] = true
	return out


func _centre(cell: Vector2i) -> Vector2:
	return _map.to_global(_map.map_to_local(cell))


func _draw() -> void:
	if _map == null:
		return
	for id: int in progress:
		if not _towers.has(id):
			continue
		var at := to_local(_centre(_towers[id][0])) + BAR_OFFSET
		var part: float = progress[id]["progress"] / CAPTURE_TIME
		draw_rect(Rect2(at - Vector2.ONE, BAR_SIZE + Vector2(2, 2)), BAR_BACK)
		draw_rect(Rect2(at, Vector2(BAR_SIZE.x * part, BAR_SIZE.y)), BAR_COLOURS.get(progress[id]["side"], BAR_OTHER))
