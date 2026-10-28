class_name AttackAim
extends Node2D
## Aim for the local player's attack (#231), by mouse or by dragging the
## on-screen attack button. In combat mode, holding the left mouse button on
## the map aims: a translucent cone from the hero shows the swing the attack
## will make, and releasing the button attacks in that direction.
## Right-click cancels.

## Touch: a finger that lands on the attack button aims once it has moved
## more than TOUCH_DEAD_ZONE from the button's centre; the cone points the way
## the finger is from that centre, and lifting the finger swings that way. A
## tap (lifted without leaving the dead zone) swings the way the hero faces,
## as before. Dragging back into the dead zone cancels: the cone goes and
## lifting there does not swing; dragging out again aims again. The finger is
## tracked by its touch index, so the move stick can be held meanwhile.

## The button is found by group: any CanvasItem in ATTACK_BUTTON_GROUP with
## `hits(screen_pos) -> bool` and `aim_center() -> Vector2` works, so its look
## (texture, scene) can change without touching this script. The cone's look
## is `style` (AimConeStyle). The sword swings in one of four
## directions, so the aim snaps to the nearest one and the cone shows that
## swing, never an angle the hit will not land on. The aim is local only; the
## attack goes out through the player's attack_animation RPC with its
## direction. Clicks that start on a HUD control, mouse events the engine
## makes from touches, interact mode and a dead player never aim. Space still
## attacks at once in the facing direction.

const DIRECTIONS := ["Up", "Down", "Left", "Right"]
const ARC := PI * 0.75  ## the swing's sweep, centred on the aim direction
const ORIGIN := Vector2(0, -3)  ## where the cone starts, in the player's space
const ARC_POINTS := 16
const TOUCH_DEAD_ZONE := 8.0  ## screen px from the button's centre: inside is a tap, or a cancel
const ATTACK_BUTTON_GROUP := "attack_button"
const INTERACTION_PATH := "/root/Flagoria/World/Interaction"

var player: Node2D  ## the local player; this node is its child
var aiming := false
var _pointer := Vector2.ZERO  ## viewport position of the cursor while aiming
var style: AimConeStyle = AimConeStyle.new()
var _touch_index := -1  ## the finger on the attack button, or -1
var _touch_offset := Vector2.ZERO  ## that finger's position from the button's centre
var _touch_aimed := false  ## the finger has left the dead zone since it landed


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
	## The direction the attack goes if the button is released now; "" when
	## nothing is aimed (a touch still inside the dead zone).
	if _touch_index != -1:
		if _touch_offset.length() <= TOUCH_DEAD_ZONE:
			return ""
		return direction_name(_touch_offset)
	var target := get_canvas_transform().affine_inverse() * _pointer
	return direction_name(target - to_global(ORIGIN))


func can_aim() -> bool:
	if player == null or player.health.is_dead():
		return false
	var interaction := get_node_or_null(INTERACTION_PATH)
	return interaction == null or interaction.mode == Interaction.Mode.COMBAT


func cancel() -> void:
	## Drops the aim; a finger on the button stays tracked but cannot swing.
	aiming = false
	if _touch_index != -1:
		_touch_aimed = true
		_touch_offset = Vector2.ZERO
	queue_redraw()


func attack_button():
	## The on-screen attack button (untyped: any node with hits/aim_center).
	return get_tree().get_first_node_in_group(ATTACK_BUTTON_GROUP)


func _offset_from_button(pos: Vector2) -> Vector2:
	var button = attack_button()
	return pos - button.aim_center() if button != null else Vector2.ZERO


func _input(event: InputEvent) -> void:
	# Touches go here, not to _unhandled_input: the move stick and the map
	# zoom read touches in _input too, and a finger on the button must be seen
	# whatever they do with the other fingers.
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_touch_offset = _offset_from_button(event.position)
		if _touch_offset.length() > TOUCH_DEAD_ZONE and can_aim():
			_touch_aimed = true
			aiming = true
		elif aiming:
			aiming = false  # back in the dead zone: cancelled until it leaves again
		queue_redraw()


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var button = attack_button()
		if _touch_index == -1 and button != null and button.is_visible_in_tree() \
				and button.hits(event.position):
			_touch_index = event.index
			_touch_offset = event.position - button.aim_center()
			_touch_aimed = false
		return
	if event.index != _touch_index:
		return
	_touch_offset = _offset_from_button(event.position)
	var direction := aim_direction() if aiming else ""
	var tap := not _touch_aimed
	_touch_index = -1
	_touch_aimed = false
	aiming = false
	queue_redraw()
	if direction != "" and can_aim():
		player.attack_toward(direction)
	elif tap:
		player.attack_toward("")  # a tap swings the way the hero faces, as before


func _process(_delta: float) -> void:
	if aiming and not can_aim():
		cancel()
	if aiming:
		queue_redraw()  # the player and the camera move under a still cursor


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouse) or event.device == InputEvent.DEVICE_ID_EMULATION \
			or _touch_index != -1:
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
		points.append(ORIGIN + Vector2.from_angle(a) * style.range)
	return points


func _draw() -> void:
	if not aiming or aim_direction() == "":
		return
	var points := cone_points()
	draw_colored_polygon(points, style.fill_color)
	var outline := points.duplicate()
	outline.append(ORIGIN)
	draw_polyline(outline, style.outline_color, style.outline_width + style.rim_width)
	draw_polyline(points.slice(1), style.rim_color, style.rim_width)
