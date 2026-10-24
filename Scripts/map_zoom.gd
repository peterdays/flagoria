extends Node
## Map zoom for the local player's camera: two-finger pinch on touch screens,
## mouse wheel or Ctrl +/- on desktop. Double-tap on the open map (or Ctrl 0)
## returns to the default zoom. Zoom is local and is never synced.
##
## Only touches that start on the open map count toward a pinch. A touch that
## starts on a HUD control (joystick, attack button, any visible Control) is
## left to that control. Drag events of a pinching finger are consumed, so a
## pinch that slides over the joystick neither moves the player nor attacks.

const MIN_FACTOR := 0.75  ## widest view, as a factor of the default zoom
const MAX_FACTOR := 2.0  ## closest view, as a factor of the default zoom
const STEP := 1.1  ## zoom factor per wheel notch or Ctrl +/- press
const HUD_MARGIN_PX := 8.0  ## slack around HUD controls, in screen pixels
const HUD_PATH := "/root/Flagoria/CanvasLayer1"

var camera: Camera2D
var default_zoom := Vector2.ONE
var factor := 1.0  ## current zoom divided by default_zoom

var _map_touches := {}  ## touch index -> position, for touches that began on the map
var _pinching := {}  ## touch indices that are part of the current pinch
var _pinch_distance := 0.0


func _ready() -> void:
	camera = get_parent() as Camera2D
	default_zoom = camera.zoom


func _input(event: InputEvent) -> void:
	if handle(event):
		get_viewport().set_input_as_handled()


func handle(event: InputEvent) -> bool:
	## Applies one input event; true when the event was used for zooming.
	if event is InputEventScreenTouch:
		return _on_touch(event)
	if event is InputEventScreenDrag:
		return _on_drag(event)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_factor(factor * STEP)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_factor(factor / STEP)
			return true
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		match event.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				set_factor(factor * STEP)
				return true
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_factor(factor / STEP)
				return true
			KEY_0, KEY_KP_0:
				reset()
				return true
	return false


func set_factor(value: float) -> void:
	factor = clampf(value, MIN_FACTOR, MAX_FACTOR)
	camera.zoom = default_zoom * factor


func reset() -> void:
	set_factor(1.0)


func is_default() -> bool:
	return is_equal_approx(factor, 1.0)


func _on_touch(event: InputEventScreenTouch) -> bool:
	if not event.pressed:
		_map_touches.erase(event.index)
		var was_pinching := _pinching.has(event.index)
		_pinching.erase(event.index)
		if _map_touches.size() < 2:
			_pinch_distance = 0.0
		return was_pinching
	if starts_on_hud(event.position):
		return false
	if event.double_tap and _map_touches.is_empty():
		reset()
		return true
	if _map_touches.size() >= 2:
		return false  # a third finger does not join the pinch
	_map_touches[event.index] = event.position
	if _map_touches.size() == 2:
		for index in _map_touches:
			_pinching[index] = true
		_pinch_distance = _touch_distance()
	return false


func _on_drag(event: InputEventScreenDrag) -> bool:
	if not _map_touches.has(event.index):
		return false
	_map_touches[event.index] = event.position
	if _map_touches.size() == 2 and _pinch_distance > 0.0:
		var distance := _touch_distance()
		if distance > 0.0:
			set_factor(factor * distance / _pinch_distance)
			_pinch_distance = distance
	return _pinching.has(event.index)


func _touch_distance() -> float:
	var points: Array = _map_touches.values()
	return (points[0] as Vector2).distance_to(points[1])


func starts_on_hud(pos: Vector2) -> bool:
	## True when a touch at this screen position belongs to a HUD control.
	var hud := get_node_or_null(HUD_PATH)
	return hud != null and _hits(hud, pos)


func _hits(node: Node, pos: Vector2) -> bool:
	for child in node.get_children():
		if child.has_signal("analogic_change"):
			# Virtual joystick: the circle it claims touches in. It reads touches
			# even while hidden, so this check ignores visibility.
			var reach: float = child.boundary * child.global_scale.x + HUD_MARGIN_PX
			if pos.distance_to(child.global_position) <= reach:
				return true
			continue
		if child is CanvasItem and not child.is_visible_in_tree():
			continue
		if child is TouchScreenButton and _hits_button(child, pos):
			return true
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and child.get_global_rect().grow(HUD_MARGIN_PX).has_point(pos):
			return true
		if _hits(child, pos):
			return true
	return false


func _hits_button(button: TouchScreenButton, pos: Vector2) -> bool:
	var local := button.get_global_transform().affine_inverse() * pos
	var margin := HUD_MARGIN_PX / maxf(button.global_scale.x, 0.001)
	var size := button.texture_normal.get_size() if button.texture_normal else Vector2.ZERO
	if Rect2(Vector2.ZERO, size).grow(margin).has_point(local):
		return true
	if button.shape is CircleShape2D:
		var center := size / 2.0 if button.shape_centered else Vector2.ZERO
		return local.distance_to(center) <= (button.shape as CircleShape2D).radius + margin
	return false
