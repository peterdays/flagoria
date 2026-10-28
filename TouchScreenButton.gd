extends TouchScreenButton
## The on-screen attack button: only how it looks and where it is. The touch
## handling (tap to swing, drag to aim) lives in AttackAim (#231), which finds
## this node by its "attack_button" group and asks it two things below. A new
## look - another texture, or a whole new scene - only has to join that group
## and answer these. `show_touch_state` is optional: AttackAim calls it, when
## present, so the art can follow the finger.

@export var texture_idle: Texture2D  ## not touched
@export var texture_down: Texture2D  ## a finger on it, still inside the dead zone
@export var texture_aim: Texture2D  ## a finger dragged past the dead zone: aiming


func _ready() -> void:
	show_touch_state(AttackAim.TOUCH_IDLE)


func show_touch_state(state: int) -> void:
	## Shows the art for an AttackAim TOUCH_* state; a missing texture keeps
	## the current one.
	var art: Texture2D = [texture_idle, texture_down, texture_aim][state]
	if art != null:
		texture_normal = art


func hits(screen_pos: Vector2) -> bool:
	## True when a touch at this viewport position presses the button.
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	if shape is CircleShape2D:
		return local.distance_to(_shape_center()) <= (shape as CircleShape2D).radius
	var size := texture_normal.get_size() if texture_normal else Vector2.ZERO
	return Rect2(Vector2.ZERO, size).has_point(local)


func aim_center() -> Vector2:
	## The viewport position a drag is measured from.
	return get_global_transform_with_canvas() * _shape_center()


func _shape_center() -> Vector2:
	var size := texture_normal.get_size() if texture_normal else Vector2.ZERO
	return size / 2.0 if shape_centered else Vector2.ZERO
