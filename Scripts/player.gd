extends CharacterBody2D

const MAX_SPEED = 130
const ACCEL = 120
const FRICTION = 95

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
const SWORD_DAMAGE := 1  ## half-hearts per sword hit
const REGEN_AMOUNT := 1  ## half-hearts per regen_timer tick
const BLINK_PERIOD_MS := 100  ## invulnerability blink: this long shown, this long faded

var lastAnimDirection: String = "Down"
var isAttacking: bool = false


func _ready():
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	if not is_multiplayer_authority(): return
	camera.make_current()
	joystick.connect("analogic_change", _on_player_joystick_analogic_change)
	var hud = get_node_or_null(HUD_PATH)
	if hud:
		hud.bind(health)

func _process(_delta):
	# Hidden while dead; blinks while invulnerable after a hit or a respawn.
	sprite.visible = not health.is_dead()
	var faded := health.is_invulnerable() and (Time.get_ticks_msec() / BLINK_PERIOD_MS) % 2 == 1
	sprite.modulate.a = 0.3 if faded else 1.0

func _physics_process(delta):
	if not is_multiplayer_authority(): return
	if health.is_dead():
		velocity = Vector2.ZERO
		return
	player_movement(delta)
	updateAnimation.rpc()
	

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

func player_movement(delta):
	input = get_input_axis()

	if input == Vector2.ZERO:  # no input
		if velocity.length() > (FRICTION * delta):
			# if we are moving we will slow down
			velocity -= velocity.normalized() * (FRICTION * delta)
		else:
			velocity = Vector2.ZERO
	else:  # moving the player
		velocity += (input * ACCEL * delta)
		velocity = velocity.limit_length(MAX_SPEED)
		
	move_and_slide()
	
func _on_player_joystick_analogic_change(move: Vector2) -> void:
	updateVelocityFromJoystick.rpc(move)

@rpc("call_local")
func updateVelocityFromJoystick(move: Vector2):
	if health.is_dead(): return
	velocity = move * ACCEL * 0.5
	velocity = velocity.limit_length(MAX_SPEED)

@rpc("call_local")
func updateAnimation():
	if isAttacking: return 

	var direction = "Down"
	if velocity.x < 0: direction = "Left"
	elif velocity.x > 0: direction = "Right"
	elif velocity.y < 0: direction = "Up"

	lastAnimDirection = direction
	animations.play("walk" + direction)


func spawn_position() -> Vector2:
	## Where this player respawns: the map's land spawn, as on joining.
	var main = get_node_or_null("/root/Flagoria")
	if main and main.has_method("_land_spawn_position"):
		return main._land_spawn_position()
	return position


func _on_damaged(_amount: int):
	combat_sfx.play_event("hit")
	combat_sfx.play_event("hurt")


func _on_died():
	combat_sfx.play_event("sting")
	weapon.visible = false
	# A dead player neither blocks movement nor hits until it respawns.
	body_shape.set_deferred("disabled", true)
	sword_shape.set_deferred("disabled", true)


func _on_respawned(at: Vector2):
	position = at
	velocity = Vector2.ZERO
	body_shape.set_deferred("disabled", false)

func _on_animation_player_animation_finished(anim_name):
	animations.play("walkDown")


func _on_regen_timer_timeout():
	health.heal(REGEN_AMOUNT)  # server only; full or dead players are skipped


func _on_hurt_box_area_entered(area):
	if area == $hurtBox: return

	var collision_player = area.get_parent().get_parent()
	if collision_player.name != name and collision_player.has_method("sword_active") and collision_player.sword_active():
		# A different player's sword, mid-swing. Every peer sees the overlap; only
		# the server's take_damage counts, and it syncs health and sounds to all.
		health.take_damage(SWORD_DAMAGE)
