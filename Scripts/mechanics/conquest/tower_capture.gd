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
## Host alone only: while multiplayer is on nothing moves (sync is #278).
## Lives under World next to worldMap, Mobs and the players; draws the bars.

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
@onready var _map: TileMap = get_node_or_null("../worldMap")
@onready var _mobs: Node = get_node_or_null("../Mobs")


func _ready() -> void:
	z_index = 10  # over the flag and wall layers


func _physics_process(delta: float) -> void:
	if tick(delta):
		queue_redraw()


func tick(delta: float) -> bool:
	## Advance every tower by `delta` s. Returns whether any progress changed.
	if _map == null or Interaction.multiplayer_on(multiplayer):
		return false
	var placer: StructurePlacer = _map._structures
	var owners := placer.placements()
	var towers := placer.towers()
	var changed := false
	for id: int in towers:
		var sides := sides_near(_centre(towers[id][0]))
		changed = _step(placer, id, owners[id]["owner"], sides, delta) or changed
	for id in progress.keys():
		if not towers.has(id):
			progress.erase(id)
	return changed


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


func sides_near(centre: Vector2) -> Dictionary:
	## Side -> true for every living player and live mob within CAPTURE_RADIUS
	## of `centre` (world px).
	var out := {}
	for node in get_parent().get_children():
		if node is CharacterBody2D and Mob.is_alive(node) and str(node.name).is_valid_int() \
				and node.global_position.distance_to(centre) <= CAPTURE_RADIUS:
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
	var towers: Dictionary = _map._structures.towers()
	for id: int in progress:
		if not towers.has(id):
			continue
		var at := to_local(_centre(towers[id][0])) + BAR_OFFSET
		var part: float = progress[id]["progress"] / CAPTURE_TIME
		draw_rect(Rect2(at - Vector2.ONE, BAR_SIZE + Vector2(2, 2)), BAR_BACK)
		draw_rect(Rect2(at, Vector2(BAR_SIZE.x * part, BAR_SIZE.y)), BAR_COLOURS.get(progress[id]["side"], BAR_OTHER))
