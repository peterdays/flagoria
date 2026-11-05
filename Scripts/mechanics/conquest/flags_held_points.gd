class_name FlagsHeldPoints
extends Node
## Pays Points.FLAGS_HELD_POINTS every INTERVAL seconds for each flag tower
## a player owns (#275). Only peer owners (id > 0) count; OWNER_MOBS and
## OWNER_NEUTRAL do not. Host alone only: while multiplayer is on nothing is
## awarded (live sync is #278). Lives next to Points / Discovery.

const INTERVAL := 5.0  ## seconds between awards for owned flag towers

@export var points_path := NodePath("../Points")
@export var map_path := NodePath("../World/worldMap")

var _elapsed := 0.0


func _physics_process(delta: float) -> void:
	if Interaction.multiplayer_on(multiplayer):
		_elapsed = 0.0
		return
	_elapsed += delta
	while _elapsed >= INTERVAL:
		_elapsed -= INTERVAL
		tick()


func tick() -> int:
	## Award FLAGS_HELD_POINTS once per player-owned flag tower. Returns how
	## many towers were paid. Tests call this directly so nothing waits on
	## INTERVAL. No-op while multiplayer is on or when this peer is not the
	## server.
	if Interaction.multiplayer_on(multiplayer) or not multiplayer.is_server():
		return 0
	var map: TileMap = get_node_or_null(map_path)
	var points: Points = get_node_or_null(points_path)
	if map == null or points == null or map._structures == null:
		return 0
	var paid := 0
	var owners: Dictionary = map._structures.placements()
	for id: int in map._structures.towers():
		var owner: int = owners.get(id, {}).get("owner", 0)
		if owner <= 0:
			continue
		if points.award(owner, Points.FLAGS_HELD_POINTS, "flags_held"):
			paid += 1
	return paid
