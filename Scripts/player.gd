extends CharacterBody2D

const MAX_SPEED = 130
const ACCEL = 120
const FRICTION = 95
## Top speed with the touch joystick, in px/s. The joystick has always moved
## the player at ACCEL * 0.5 = 60 px/s, under the keyboard's MAX_SPEED; kept
## as is because matching MAX_SPEED would change how touch play feels.
const JOYSTICK_MAX_SPEED = 60

var input = Vector2.ZERO

@onready var camera = $Camera2D
@onready var joystick = $/root/Flagoria/CanvasLayer1/player_joystick
@onready var animations = $AnimationPlayer
@onready var weapon = $weapon
@onready var combat_sfx: CombatSfx = $CombatSfx
@onready var health: PlayerHealth = $Health
@onready var sprite: Sprite2D = $Sprite2D
@onready var sword: Area2D = $weapon/sword
@onready var sword_shape: CollisionShape2D = $weapon/sword/CollisionShape2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

const HUD_PATH := "/root/Flagoria/CanvasLayer1/HeartsHud"
const MapZoom := preload("res://Scripts/map_zoom.gd")
const SWORD_DAMAGE := 1  ## half-hearts per sword hit
const REGEN_AMOUNT := 1  ## half-hearts per regen_timer tick
const BLINK_PERIOD_MS := 100  ## invulnerability blink: this long shown, this long faded

const RESPAWN_HOLD_MS := 1000  ## longest a copy waits for its owner to catch up with a respawn

## On copies the owner moves: the respawn spot to hold while the owner's
## synced position is still the one from before it saw the respawn.
var _respawn_hold := Vector2.INF
var _respawn_hold_until := 0
## The owner's health.respawn_count when it sent an update, synced with
## its position. A copy holds the spawn until this reaches the number the
## server gave the respawn, so it needs no baseline of its own.
var owner_respawns := 0
## Physics frames left with the body's collision off after a respawn moved
## it. The physics server moves a body to a new position only at its next
## step, so for one tick the bodies of players who also just respawned still
## stand where they died. Colliding then pushes the owner off the server's
## spot, or (taking a body's top for a floor) carries it along when that
## body jumps to its own spot (found in a multi-peer play-test).
var _respawn_ghost_ticks := 0

var lastAnimDirection: String = "Down"
## The walk facing this player last sent with updateAnimation; the owner sends
## a new one only when the facing changes, not every physics frame.
var _sent_walk_direction := ""
## The walk facing the owner last sent; replayed when an attack ends.
var _walk_direction := "Down"
var isAttacking: bool = false


func _ready():
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	health.health_changed.connect(_apply_dead_state.unbind(2))
	health.state_received.connect(_apply_dead_state.unbind(2))
	var sync := get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.synchronized.connect(_on_synchronized)
	if not is_multiplayer_authority(): return
	camera.make_current()
	# A peer that joins later gets the current walk facing on the next frame.
	multiplayer.peer_connected.connect(func(_id): _sent_walk_direction = "")
	var map_zoom := MapZoom.new()  # local camera only; zoom is never synced
	map_zoom.name = "MapZoom"
	camera.add_child(map_zoom)
	var hud = get_node_or_null(HUD_PATH)
	if hud:
		hud.bind(health)

func _process(_delta):
	# Hidden while dead; blinks while invulnerable after a hit or a respawn.
	sprite.visible = not health.is_dead()
	var faded := health.is_invulnerable() and (Time.get_ticks_msec() / BLINK_PERIOD_MS) % 2 == 1
	sprite.modulate.a = 0.3 if faded else 1.0

func _physics_process(delta):
	if _respawn_ghost_ticks > 0:
		_respawn_ghost_ticks -= 1
		if _respawn_ghost_ticks == 0:
			_apply_dead_state()
	if not is_multiplayer_authority(): return
	if health.is_dead():
		velocity = Vector2.ZERO
		return
	player_movement(delta)
	var direction := walk_direction()
	if direction != _sent_walk_direction:
		_sent_walk_direction = direction
		updateAnimation.rpc(direction)
	

func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	if health.is_dead(): return
	
	if Input.is_action_just_pressed("attack"):
		attack_animation.rpc()

@rpc("call_local")  # the call local calls in all remotes and the local too
func attack_animation():
	animations.stop()
	combat_sfx.play_event("swing")
	animations.play("attack" + lastAnimDirection)
	isAttacking = true
	weapon.visible = true
	sword_shape.set_deferred("disabled", false)  # the sword only hits during a swing
	await animations.animation_finished
	weapon.visible = false
	sword_shape.set_deferred("disabled", true)
	isAttacking = false


func sword_active() -> bool:
	## True while this player's swing can hit: mid-attack and alive.
	return isAttacking and not health.is_dead()

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func get_input_axis():
	input.x = int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left"))
	input.y = int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up"))
	return input.normalized()

func get_joystick_axis() -> Vector2:
	## The touch joystick's direction while a finger holds it, read every
	## physics frame: the joystick only signals on touch and drag events, so a
	## finger held still sends nothing.
	if not is_instance_valid(joystick) or joystick.ongoing_drag == -1:
		return Vector2.ZERO
	return joystick.get_button_pos().normalized()

func player_movement(delta):
	input = get_input_axis()
	var max_speed := MAX_SPEED
	if input == Vector2.ZERO:
		input = get_joystick_axis()
		if input != Vector2.ZERO:
			max_speed = JOYSTICK_MAX_SPEED

	if input == Vector2.ZERO:  # no input
		if velocity.length() > (FRICTION * delta):
			# if we are moving we will slow down
			velocity -= velocity.normalized() * (FRICTION * delta)
		else:
			velocity = Vector2.ZERO
	else:  # moving the player
		velocity += (input * ACCEL * delta)
		velocity = velocity.limit_length(max_speed)
		
	move_and_slide()

func walk_direction() -> String:
	## The walk animation's facing for the owner's current velocity.
	if velocity.x < 0: return "Left"
	if velocity.x > 0: return "Right"
	if velocity.y < 0: return "Up"
	return "Down"

@rpc("call_local")
func updateAnimation(direction: String):
	_walk_direction = direction
	if isAttacking: return

	lastAnimDirection = direction
	animations.play("walk" + direction)


func spawn_position() -> Vector2:
	## Where this player respawns: a free spot near the map's land spawn, as
	## on joining.
	var main = get_node_or_null("/root/Flagoria")
	if main and main.has_method("_land_spawn_position"):
		return main._land_spawn_position(self)
	return position


func _on_damaged(_amount: int):
	combat_sfx.play_event("hit")
	combat_sfx.play_event("hurt")


func _on_died():
	combat_sfx.play_event("sting")


func _apply_dead_state():
	# Follows health state, however it arrived (a hit, set_health_now, a
	# respawn, or a late copy's state reply): a dead player neither blocks
	# movement nor hits until it respawns. The sprite hides in _process.
	var dead := health.is_dead()
	body_shape.set_deferred("disabled", dead or _respawn_ghost_ticks > 0)
	if dead:
		weapon.visible = false
		sword_shape.set_deferred("disabled", true)


func _on_respawned(at: Vector2):
	if is_multiplayer_authority():
		owner_respawns = health.respawn_count
	else:
		_respawn_hold = at
		_respawn_hold_until = Time.get_ticks_msec() + RESPAWN_HOLD_MS
	position = at
	velocity = Vector2.ZERO
	# On every peer: this body neither pushes nor is pushed until the
	# physics server has every respawned body at its new spot.
	_respawn_ghost_ticks = 1
	body_shape.set_deferred("disabled", true)


func _on_synchronized():
	# The owner keeps sending its pre-respawn position until the respawn
	# reaches it; keep the copy at the spawn until an update the owner sent
	# after it respawned (or the hold runs out), then follow again.
	if _respawn_hold == Vector2.INF:
		return
	if owner_respawns >= health.respawn_count or Time.get_ticks_msec() > _respawn_hold_until:
		_respawn_hold = Vector2.INF
	else:
		position = _respawn_hold

func _on_animation_player_animation_finished(anim_name):
	# An attack ended: back to the walk facing the owner last sent, which no
	# longer arrives every frame.
	lastAnimDirection = _walk_direction
	animations.play("walk" + _walk_direction)


func _on_regen_timer_timeout():
	health.heal(REGEN_AMOUNT)  # server only; full or dead players are skipped


func _on_hurt_box_area_entered(area):
	# An area never reports itself, and the hurtBox is on no layer anyway.
	var collision_player = area.get_parent().get_parent()
	if collision_player.name != name and collision_player.has_method("sword_active") and collision_player.sword_active():
		# A different player's sword, mid-swing. Every peer sees the overlap; only
		# the server's take_damage counts, and it syncs health and sounds to all.
		health.take_damage(SWORD_DAMAGE)
