extends CharacterBody2D

const MAX_SPEED = 130
const ACCEL = 120
const FRICTION = 95

var input = Vector2.ZERO

@onready var camera = $Camera2D
@onready var joystick = $/root/Flagoria/CanvasLayer1/player_joystick
@export var maxHealth = 30
@onready var currentHealth: int = maxHealth
@onready var animations = $AnimationPlayer

signal healthChanged


func _ready():
	if not is_multiplayer_authority(): return
	camera.make_current()
	joystick.connect("analogic_change", _on_player_joystick_analogic_change)

func _physics_process(delta):
	if not is_multiplayer_authority(): return
	player_movement(delta)
	updateAnimation()
	

func _unhandled_input(event):
	if not is_multiplayer_authority(): return

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
	velocity = move * ACCEL * 0.8
	velocity = velocity.limit_length(MAX_SPEED)
	
func updateAnimation():
	var direction = "Down"
	if velocity.x < 0: direction = "Left"
	elif velocity.x > 0: direction = "Right"
	elif velocity.y < 0: direction = "Up"
	
	animations.play("walk" + direction)
