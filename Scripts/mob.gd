class_name Mob
extends Node2D
## One mob. The server runs its behaviour; every other peer receives position,
## facing and state through the MultiplayerSynchronizer and only animates.
##
## Wander: stand for a moment, then walk one way for a moment, staying on the
## type's home ground (grass or sand) and within WANDER_RADIUS of where it spawned.

enum State { IDLE, WALK }

const WANDER_RADIUS := 6 * 16  ## px from home
const IDLE_TIME := Vector2(1.0, 3.0)  ## seconds, min and max
const WALK_TIME := Vector2(0.6, 1.6)

@export var mob_type: String = MobCatalog.SLIME
@export var facing: int = MobCatalog.DOWN
@export var state: State = State.IDLE:
	set(value):
		if value != state:
			anim_time = 0.0
		state = value

var home := Vector2.ZERO
var direction := Vector2.ZERO
var anim_time := 0.0
var rng := RandomNumberGenerator.new()
var _timer := 0.0
var _world: TileMap

@onready var sprite: Sprite2D = $Sprite2D


func setup(type: String, at: Vector2, rng_seed: int) -> void:
	## Called by MobSpawner on every peer before the mob enters the tree.
	mob_type = type
	position = at
	home = at
	rng.seed = rng_seed
	_timer = rng.randf_range(IDLE_TIME.x, IDLE_TIME.y)


func _ready() -> void:
	sprite.texture = MobCatalog.sheet(mob_type)
	# Mobs live under World/Mobs, next to World/worldMap.
	_world = get_node_or_null("../../worldMap") as TileMap


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		think(delta)


func _process(delta: float) -> void:
	anim_time += delta
	sprite.frame_coords = MobCatalog.frame(anim_name(), facing, anim_time)


func anim_name() -> String:
	return "walk" if state == State.WALK else "idle"


func think(delta: float) -> void:
	## Server only: one behaviour step.
	_timer -= delta
	if state == State.WALK:
		if not step(direction * float(MobCatalog.stat(mob_type, "wander_speed")) * delta) or _timer <= 0.0:
			_start_idle()
	elif _timer <= 0.0:
		_start_walk()


func step(motion: Vector2) -> bool:
	## Move by `motion` if the feet stay on home ground; false when blocked.
	var target := position + motion
	if not can_stand_at(target):
		return false
	position = target
	return true


func can_stand_at(pos: Vector2) -> bool:
	## Home ground under the whole feet box, inside the wander radius.
	if pos.distance_to(home) > WANDER_RADIUS:
		return false
	if _world == null:
		return false
	var half: Vector2 = MobCatalog.stat(mob_type, "body") * 0.5
	var home_kind: int = MobCatalog.stat(mob_type, "home")
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, 0), Vector2(half.x, 0)]:
		if not MobSpawner.is_home_cell(_world, _world.local_to_map(pos + corner), home_kind):
			return false
	return true


func _start_idle() -> void:
	state = State.IDLE
	direction = Vector2.ZERO
	_timer = rng.randf_range(IDLE_TIME.x, IDLE_TIME.y)


func _start_walk() -> void:
	# Head back towards home when far out, else any of the four directions.
	var dirs: Array = MobCatalog.FACING_VECTORS
	direction = dirs[rng.randi_range(0, dirs.size() - 1)]
	if position.distance_to(home) > WANDER_RADIUS * 0.5:
		direction = MobCatalog.FACING_VECTORS[MobCatalog.facing_for(home - position)]
	facing = MobCatalog.facing_for(direction)
	state = State.WALK
	_timer = rng.randf_range(WALK_TIME.x, WALK_TIME.y)
