class_name AttackAim
extends Node2D
## Mouse aim for the local player's attack (#231). In combat mode, holding
## the left mouse button on the map aims: a translucent cone from the hero
## shows the swing the attack will make, and releasing the button attacks in
## that direction. Right-click cancels. The sword swings in one of four
## directions, so the aim snaps to the nearest one and the cone shows that
## swing, never an angle the hit will not land on. The aim is local only; the
## attack goes out through the player's attack_animation RPC with its
## direction. Clicks that start on a HUD control, mouse events the engine
## makes from touches, interact mode and a dead player never aim. Space still
## attacks at once in the facing direction.

const DIRECTIONS := ["Up", "Down", "Left", "Right"]
const RANGE := 22.0  ## world px: past the sword's hitbox at mid-swing
const ARC := PI * 0.75  ## the swing's sweep, centred on the aim direction
const ORIGIN := Vector2(0, -3)  ## where the cone starts, in the player's space
const ARC_POINTS := 16
const FILL_COLOR := Color(0.949, 0.918, 0.945, 0.3)
const LINE_COLOR := Color(0.949, 0.918, 0.945, 0.9)
const INTERACTION_PATH := "/root/Flagoria/World/Interaction"

var player: Node2D  ## the local player; this node is its child
var aiming := false
var _pointer := Vector2.ZERO  ## viewport position of the cursor while aiming


func _ready() -> void:
	player = get_parent()
	z_index = 3  # over the trees


static func direction_name(v: Vector2) -> String:
	## The swing direction nearest to `v`; "" for a zero vector. A diagonal
	## exactly between two directions picks the horizontal one.
	if v == Vector2.ZERO:
		return ""
	if absf(v.x) >= absf(v.y):
		return "Left" if v.x < 0 else "Right"
	return "Up" if v.y < 0 else "Down"


static func direction_vector(direction: String) -> Vector2:
	match direction:
		"Up": return Vector2.UP
		"Down": return Vector2.DOWN
		"Left": return Vector2.LEFT
		"Right": return Vector2.RIGHT
	return Vector2.ZERO


func aim_direction() -> String:
	## The direction the attack goes if the button is released now.
	var target := get_canvas_transform().affine_inverse() * _pointer
	return direction_name(target - to_global(ORIGIN))


func can_aim() -> bool:
	if player == null or player.health.is_dead():
		return false
	var interaction := get_node_or_null(INTERACTION_PATH)
	return interaction == null or interaction.mode == Interaction.Mode.COMBAT


func cancel() -> void:
	aiming = false
	queue_redraw()


func _process(_delta: float) -> void:
	if aiming and not can_aim():
		cancel()
	if aiming:
		queue_redraw()  # the player and the camera move under a still cursor


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouse) or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		if aiming:
			_pointer = event.position
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and aiming:
		cancel()
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed and not aiming and can_aim() and not _on_hud(button.position):
			aiming = true
			_pointer = button.position
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not button.pressed and aiming:
			_pointer = button.position
			var direction := aim_direction()
			cancel()
			if can_aim():
				player.attack_toward(direction)
			get_viewport().set_input_as_handled()


func _on_hud(pos: Vector2) -> bool:
	var zoom := player.get_node_or_null("Camera2D/MapZoom")
	return zoom != null and zoom.starts_on_hud(pos)


func cone_points() -> PackedVector2Array:
	## The cone for the current aim, in this node's space.
	var points := PackedVector2Array([ORIGIN])
	var angle := direction_vector(aim_direction()).angle()
	for i in ARC_POINTS + 1:
		var a := angle - ARC / 2.0 + ARC * i / ARC_POINTS
		points.append(ORIGIN + Vector2.from_angle(a) * RANGE)
	return points


func _draw() -> void:
	if not aiming or aim_direction() == "":
		return
	var points := cone_points()
	draw_colored_polygon(points, FILL_COLOR)
	points.append(ORIGIN)
	draw_polyline(points, LINE_COLOR, 1.0)
