class_name RoundHudStyle
extends RefCounted
## Shared circle for the top-right HUD buttons (#450, #480).
## The menu theme's colours, drawn as a disc so Buildings, Map, Mode,
## the build tools and Run match.

const SIZE := 18.0  ## drawn disc
const HIT := 24.0  ## invisible tap target, larger than the disc
const RUN_SIZE := 14.0  ## Run's disc, smaller than the 40px attack button
const RUN_HIT := 20.0
## The HUD icons are 32px files with about 18px of art. This width keeps that
## art inside the disc and leaves the ring visible. Buttons draw it nearest.
const ICON := 24
const INK := Color(0.078, 0.106, 0.106, 1)
const FACE := Color(0.373, 0.443, 0.376, 1)
const FACE_HOVER := Color(0.553, 0.592, 0.498, 1)
const FACE_ON := Color(0.82, 0.9, 0.68, 1)
const RING := Color(1.0, 0.86, 0.28, 1)
const FACE_OFF := Color(0.306, 0.282, 0.29, 1)


static func apply(button: Button, hit: float = HIT, disc: float = SIZE) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.expand_icon = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_constant_override("icon_max_width", ICON)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _circle(state, hit, disc))
	# Style first: assigning size before the circle is in place is clamped to
	# the theme button's text minimum, and that larger size never shrinks.
	button.custom_minimum_size = Vector2(hit, hit)
	button.reset_size()


static func _face(state: String) -> Color:
	if state == "hover":
		return FACE_HOVER
	if state == "pressed" or state == "hover_pressed":
		return FACE_ON
	if state == "disabled":
		return FACE_OFF
	return FACE


static func _circle(state: String, hit: float, disc: float) -> StyleBoxFlat:
	## The control is the tap target. A negative expand margin draws the disc
	## in the middle and leaves the rest of the control invisible.
	var selected := state == "pressed" or state == "hover_pressed"
	var box := StyleBoxFlat.new()
	box.bg_color = _face(state)
	box.border_color = RING if selected else INK
	box.set_border_width_all(3 if selected else 1)
	var inset := (hit - disc) * 0.5
	box.set_expand_margin_all(-inset)
	box.set_corner_radius_all(int(disc))
	box.set_content_margin_all(0)
	box.anti_aliasing = false
	return box
