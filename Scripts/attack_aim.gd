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
## tracked by its touch index, so the move stick can be held meanwhile. A tap
## swings only when an aim could (can_aim). Losing focus or pausing the app
## drops the finger and any aim: the lift may never arrive. A second finger
## that lands off the move stick while the first aims cancels: the first
## finger is let go, so neither its drags nor its lift swing.

## The button is found by group: any CanvasItem in ATTACK_BUTTON_GROUP with
## `hits(screen_pos) -> bool` and `aim_center() -> Vector2` works, so its look
## (texture, scene) can change without touching this script; one that also
## has `show_touch_state(state)` is told the TOUCH_* state to show. The cone's
## look is `style` (AimConeStyle), its lines one screen pixel at any zoom. The
## cone and the swing follow the exact aim angle; the hero's sprite faces the
## nearest of the four directions, and the swing plays that direction's
## animation turned to the angle. The aim is local only; the attack goes out
## through the player's attack_animation RPC with its direction and angle.
## Clicks that start on a HUD control, mouse events the engine
## makes from touches, interact mode, an open in-game menu and a dead player
## never aim, and opening the menu mid-aim cancels the aim. Space still
## attacks at once in the facing direction.

const DIRECTIONS := ["Up", "Down", "Left", "Right"]
const ARC := PI * 0.75  ## the swing's sweep, centred on the aim direction
const ORIGIN := Vector2(0, -3)  ## where the cone starts, in the player's space
## Physics layer of TileSet terrain (walls, water, forest plants that block walking).
const TERRAIN_MASK := 1


static func clear_shot(
	space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, exclude: Array = []
) -> bool:
	## True when nothing solid on the terrain layer lies on the segment from
	## `from` to `to`. Used so a sword swing only hurts a mob it can see.
	## `exclude` is a list of RIDs (the attacker) so the ray ignores them.
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = TERRAIN_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = exclude
	return space.intersect_ray(query).is_empty()


const ARC_POINTS := 16
const MAX_TURN := PI / 4.0  ## the farthest an aim angle is from its four-way direction
const TOUCH_DEAD_ZONE := 8.0  ## screen px from the button's centre: inside is a tap, or a cancel
const TOUCH_IDLE := 0  ## no finger on the button
const TOUCH_DOWN := 1  ## a finger on it, inside the dead zone
const TOUCH_AIM := 2  ## that finger past the dead zone, aiming
const ATTACK_BUTTON_GROUP := "attack_button"
const INTERACTION_PATH := "/root/Flagoria/World/Interaction"
const MENU_PATH := "/root/Flagoria/CanvasLayer1/InGameMenu"
const MOVE_STICK_PATH := "/root/Flagoria/CanvasLayer1/player_joystick"
const MapZoomScript := preload("res://Scripts/map_zoom.gd")

var player: Node2D  ## the local player; this node is its child
var aiming := false
var _pointer := Vector2.ZERO  ## viewport position of the cursor while aiming
var style: AimConeStyle = AimConeStyle.new()
var _touch_index := -1  ## the finger on the attack button, or -1
var _touch_offset := Vector2.ZERO  ## that finger's position from the button's centre
var _touch_aimed := false  ## the finger has left the dead zone since it landed
var _aim_started_ms := 0  ## when the cone last appeared: its pulse starts there


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


static func turn_to(direction: String, angle: float) -> float:
	## How far a swing toward `direction` turns to reach `angle` (radians);
	## NAN when `angle` is more than MAX_TURN from it (or is not finite: the
	## difference is then NAN and fails the bound too).
	var base := direction_vector(direction)
	if base == Vector2.ZERO:
		return NAN
	var turn := angle_difference(base.angle(), angle)
	return turn if absf(turn) <= MAX_TURN + 0.001 else NAN


func aim_vector() -> Vector2:
	## Where the attack goes if the button is released now, from the cone's
	## apex; zero when nothing is aimed (a touch still inside the dead zone).
	if _touch_index != -1:
		if _touch_offset.length() <= TOUCH_DEAD_ZONE:
			return Vector2.ZERO
		return _touch_offset
	var target := get_canvas_transform().affine_inverse() * _pointer
	return target - to_global(ORIGIN)


func aim_direction() -> String:
	## The four-way direction of the aim (the sprite's facing); "" for none.
	return direction_name(aim_vector())


func aim_angle() -> float:
	## The exact aim angle in radians; NAN when nothing is aimed.
	var v := aim_vector()
	return NAN if v == Vector2.ZERO else v.angle()


func can_aim() -> bool:
	if player == null or player.health.is_dead():
		return false
	if _parchment_open():
		return false
	var menu := get_node_or_null(MENU_PATH)
	if menu != null and menu.is_open():
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
	_show_touch_state()


func touch_state() -> int:
	if _touch_index == -1:
		return TOUCH_IDLE
	return TOUCH_AIM if aiming else TOUCH_DOWN


func _show_touch_state() -> void:
	var button = attack_button()
	if button != null and button.has_method("show_touch_state"):
		button.show_touch_state(touch_state())


func _start_aim() -> void:
	if not aiming:
		_aim_started_ms = Time.get_ticks_msec()
	aiming = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_drop_touch()  # the finger's lift may never arrive


func _drop_touch() -> void:
	## Forgets the finger on the button and drops any aim.
	_touch_index = -1
	_touch_aimed = false
	_touch_offset = Vector2.ZERO
	aiming = false
	queue_redraw()
	if is_inside_tree():
		_show_touch_state()


func _on_move_stick(pos: Vector2) -> bool:
	## True when a touch here is the move stick's, with the HUD's slack.
	var stick := get_node_or_null(MOVE_STICK_PATH)
	return stick != null and stick.has_method("start_reach") \
			and pos.distance_to(stick.global_position) <= stick.start_reach() + MapZoomScript.HUD_MARGIN_PX


func attack_button():
	## The on-screen attack button (untyped: any node with hits/aim_center).
	return get_tree().get_first_node_in_group(ATTACK_BUTTON_GROUP)


func _offset_from_button(pos: Vector2) -> Vector2:
	var button = attack_button()
	return pos - button.aim_center() if button != null else Vector2.ZERO


func _parchment_open() -> bool:
	var node := get_tree().get_first_node_in_group(ParchmentMap.GROUP)
	return node != null and node.is_open()


func _input(event: InputEvent) -> void:
	# Touches go here, not to _unhandled_input: the move stick and the map
	# zoom read touches in _input too, and a finger on the button must be seen
	# whatever they do with the other fingers.
	if _parchment_open():
		if _touch_index != -1:
			_drop_touch()
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_touch_offset = _offset_from_button(event.position)
		if _touch_offset.length() > TOUCH_DEAD_ZONE and can_aim():
			_touch_aimed = true
			_start_aim()
		elif aiming:
			aiming = false  # back in the dead zone: cancelled until it leaves again
		queue_redraw()
		_show_touch_state()


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if aiming and _touch_index != -1 and event.index != _touch_index \
				and not _on_move_stick(event.position):
			_drop_touch()  # a second touch cancels the aim
			return
		var button = attack_button()
		if _touch_index == -1 and can_aim() and button != null and button.is_visible_in_tree() \
				and button.hits(event.position):
			_touch_index = event.index
			_touch_offset = event.position - button.aim_center()
			_touch_aimed = false
			_show_touch_state()
		return
	if event.index != _touch_index:
		return
	_touch_offset = _offset_from_button(event.position)
	var direction := aim_direction() if aiming else ""
	var angle := aim_angle() if aiming else NAN
	var tap := not _touch_aimed
	_touch_index = -1
	_touch_aimed = false
	aiming = false
	queue_redraw()
	_show_touch_state()
	if not can_aim():
		return
	if direction != "":
		player.attack_toward(direction, angle)
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
			_start_aim()
			_pointer = button.position
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not button.pressed and aiming:
			_pointer = button.position
			var direction := aim_direction()
			var angle := aim_angle()
			cancel()
			if can_aim():
				player.attack_toward(direction, angle)
			get_viewport().set_input_as_handled()


func _on_hud(pos: Vector2) -> bool:
	var zoom := player.get_node_or_null("Camera2D/MapZoom")
	return zoom != null and zoom.starts_on_hud(pos)


func cone_points(origin := ORIGIN, reach := -1.0) -> PackedVector2Array:
	## The cone for the current aim, in this node's space: apex, then the arc.
	if reach < 0.0:
		reach = style.range
	var points := PackedVector2Array([origin])
	var angle := aim_angle()
	for i in ARC_POINTS + 1:
		var a := angle - ARC / 2.0 + ARC * i / ARC_POINTS
		points.append(origin + Vector2.from_angle(a) * reach)
	return points


func screen_px() -> float:
	## One screen (viewport) pixel in this node's units, at any camera zoom.
	var zoom := get_global_transform_with_canvas().get_scale().x
	return 1.0 / zoom if zoom > 0.0 else 1.0


func _draw() -> void:
	if not aiming or aim_direction() == "":
		return
	var px := screen_px()
	var t := (Time.get_ticks_msec() - _aim_started_ms) / 1000.0
	var outer := cone_points()
	draw_colored_polygon(outer, style.fill_at(t))
	# The rim runs just inside the outline: the same cone moved inward by half
	# of both lines; the apex moves along the aim by that over sin(ARC / 2).
	var inset := px * (style.outline_width + style.rim_width) / 2.0
	var inner := cone_points(ORIGIN + Vector2.from_angle(aim_angle()) * inset / sin(ARC / 2.0),
			style.range - inset)
	inner.append(inner[0])
	draw_polyline(inner, style.rim_color, style.rim_width * px)
	outer.append(outer[0])
	draw_polyline(outer, style.outline_color, style.outline_width * px)
