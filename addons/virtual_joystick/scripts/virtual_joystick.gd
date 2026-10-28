@tool
extends Node2D

signal analogic_change(move: Vector2)
signal analogic_released

@export var border: Texture2D:
	set(value):
		border = value
		_draw()
		
@export var stick: Texture2D:
	set(value):
		stick = value
		_draw()

@export var stick_active: Texture2D  ## the knob while a finger drags the stick; none keeps `stick`
@export var radius := Vector2(32, 32)  ## half the knob (the knob is top-left anchored)
@export var boundary := 64  ## knob travel from the centre
@export var start_radius := -1.0  ## a drag may start this far from the centre; below 0 uses `boundary`

var joystick = Sprite2D.new()
var touch = TouchScreenButton.new()
var ongoing_drag := -1
var return_accel := 20
var threshold := 10



func _draw() -> void:	
	if get_child_count() == 0:
		add_child(joystick)
		
	if joystick.get_child_count() == 0:
		joystick.add_child(touch)	
		
	joystick.texture = border if is_instance_valid(border) else preload("res://addons/virtual_joystick/sprites/joystick.png")
	touch.texture_normal = _knob()


func _knob() -> Texture2D:
	if ongoing_drag != -1 and is_instance_valid(stick_active):
		return stick_active
	return stick if is_instance_valid(stick) else preload("res://addons/virtual_joystick/sprites/stick.png")


func start_reach() -> float:
	## How far from the centre, in its parent's units, a touch may start a drag.
	return (start_radius if start_radius >= 0.0 else float(boundary)) * global_scale.x


func _ready() -> void:	
	touch.released.connect(func(): emit_signal("analogic_released"))	
	

func _process(delta: float) -> void:
	if ongoing_drag == -1:
		var pos_difference = (Vector2.ZERO - radius) - touch.position
		touch.position += pos_difference * return_accel * delta
		

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or ( event is InputEventScreenTouch and event.is_pressed()):
		var event_dist_from_center = (event.position - global_position).length()

		if event_dist_from_center <= start_reach() or event.get_index() == ongoing_drag:
			touch.global_position = event.position - radius * global_scale
			
			if get_button_pos().length() > boundary:
				touch.position = get_button_pos().normalized() * boundary - radius

			ongoing_drag = event.get_index()
			touch.texture_normal = _knob()
			emit_signal("analogic_change", get_button_pos().normalized())

	if event is InputEventScreenTouch and not event.is_pressed() and event.get_index() == ongoing_drag:
		ongoing_drag = -1
		touch.texture_normal = _knob()
		emit_signal("analogic_change", Vector2.ZERO)
		

func get_button_pos() -> Vector2:
	return touch.position + radius
	
func get_value() -> Vector2:
	if get_button_pos().length() > threshold:
		return get_button_pos().normalized()
		
	return Vector2.ZERO

