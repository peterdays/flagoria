extends CharacterBody2D

const MAX_SPEED = 200
const ACCEL = 1000
const FRICTION = 600

var input = Vector2.ZERO

func _ready():
	if not is_multiplayer_authority(): return


func _physics_process(delta):
	if not is_multiplayer_authority(): return
	player_movement(delta)

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
