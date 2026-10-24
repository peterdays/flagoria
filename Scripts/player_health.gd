class_name PlayerHealth
extends Node
## One player's health, counted in half-hearts (2 points = 1 heart).
##
## The server owns health: take_damage, heal and the respawn countdown only
## act on the server (peer 1, which is also the only peer offline). Every
## change reaches all peers through a reliable call_local RPC, so each peer's
## copy, sounds and HUD match. A peer that spawns this node later asks the
## server for the current value. Each player node has its own PlayerHealth.

signal health_changed(current: int, maximum: int)
## A hit landed and took `amount` half-hearts (fires on every peer).
signal damaged(amount: int)
signal died
signal respawned(at: Vector2)

const SERVER_ID := 1

@export var max_health := 6  ## half-hearts: 6 = 3 hearts
@export var invulnerable_time := 1.0  ## seconds after a hit or a respawn
@export var respawn_delay := 1.0  ## seconds between death and respawn

var health := 6
var _invulnerable_left := 0.0
var _respawn_left := -1.0


func _enter_tree() -> void:
	# The player node gives its whole subtree to the owning peer; health stays with the server.
	set_multiplayer_authority(SERVER_ID, false)


func _ready() -> void:
	health = max_health
	if not multiplayer.is_server():
		_request_state.rpc_id(SERVER_ID)


func is_dead() -> bool:
	return health <= 0


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func heart_count() -> int:
	return ceili(max_health / 2.0)


func take_damage(amount: int) -> bool:
	## Server only. Returns true when the hit landed. Ignored while dead or
	## invulnerable; health stops at 0, which starts the respawn countdown.
	if not is_multiplayer_authority() or amount <= 0 or is_dead() or is_invulnerable():
		return false
	_apply_damage.rpc(maxi(health - amount, 0))
	if is_dead():
		_respawn_left = respawn_delay
	return true


func heal(amount: int) -> bool:
	## Server only. Returns true when health went up. Capped at max_health;
	## a dead player is not healed (respawn restores health).
	if not is_multiplayer_authority() or amount <= 0 or is_dead() or health >= max_health:
		return false
	_set_health.rpc(mini(health + amount, max_health), _invulnerable_left)
	return true


func set_health_now(value: int) -> void:
	## Server only, for tools and tests: set health with no sound and no
	## invulnerability. 0 starts the respawn countdown.
	if not is_multiplayer_authority():
		return
	value = clampi(value, 0, max_health)
	_respawn_left = respawn_delay if value == 0 else -1.0
	_set_health.rpc(value, 0.0)


func respawn() -> void:
	## Server only: full health at the spawn point, then invulnerable_time.
	if not is_multiplayer_authority():
		return
	_respawn_left = -1.0
	_do_respawn.rpc(_spawn_position())


func advance(delta: float) -> void:
	## Count down invulnerability on every peer and, on the server, the respawn.
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	if _respawn_left >= 0.0 and is_multiplayer_authority():
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			respawn()


func _physics_process(delta: float) -> void:
	advance(delta)


func _spawn_position() -> Vector2:
	var player := get_parent()
	if player and player.has_method("spawn_position"):
		return player.spawn_position()
	return player.position if player is Node2D else Vector2.ZERO


@rpc("authority", "call_local", "reliable")
func _apply_damage(new_health: int) -> void:
	var lost := health - new_health
	health = new_health
	_invulnerable_left = invulnerable_time
	damaged.emit(lost)
	health_changed.emit(health, max_health)
	if health == 0:
		died.emit()


@rpc("authority", "call_local", "reliable")
func _set_health(new_health: int, invulnerable_left: float) -> void:
	health = new_health
	_invulnerable_left = invulnerable_left
	health_changed.emit(health, max_health)


@rpc("authority", "call_local", "reliable")
func _do_respawn(at: Vector2) -> void:
	health = max_health
	_invulnerable_left = invulnerable_time
	respawned.emit(at)
	health_changed.emit(health, max_health)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server():
		_set_health.rpc_id(multiplayer.get_remote_sender_id(), health, _invulnerable_left)
