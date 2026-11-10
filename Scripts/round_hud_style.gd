class_name RoundHudStyle
extends RefCounted
## Shared circle for the HUD row under the wood counter (#450).
## The menu theme's colours, drawn as a disc so Run, the build tools, the
## minimap and the mode button match.

const SIZE := 18.0  ## drawn disc
const HIT := 24.0  ## invisible tap target, larger than the disc
const ICON := 12  ## leaves a ring of the disc visible around the picture
const INK := Color(0.078, 0.106, 0.106, 1)
const FACE := Color(0.373, 0.443, 0.376, 1)
const FACE_HOVER := Color(0.553, 0.592, 0.498, 1)
const FACE_ON := Color(0.82, 0.9, 0.68, 1)
const RING := Color(1.0, 0.86, 0.28, 1)
const FACE_OFF := Color(0.306, 0.282, 0.29, 1)

static var _map_icon: Texture2D


static func apply(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_constant_override("icon_max_width", ICON)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _circle(state))
	# Style first: assigning size before the circle is in place is clamped to
	# the theme button's text minimum, and that larger size never shrinks.
	button.custom_minimum_size = Vector2(HIT, HIT)
	button.reset_size()


static func map_icon() -> Texture2D:
	## A tiny chart, the same colours as the wood panel, for the minimap button.
	if _map_icon != null:
		return _map_icon
	## No ink frame: a dark square around the chart read as a pressed ring
	## even while the wood panel was closed.
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	var water := Color("7cc8f2")
	var sand := Color("e8c968")
	var grass := Color("6fbf3a")
	var mark := Color("24604a")
	img.fill(Color(0, 0, 0, 0))
	for y in range(2, 12):
		for x in range(2, 12):
			var colour := grass
			if y < 6:
				colour = water
			elif y < 8:
				colour = sand
			img.set_pixel(x, y, colour)
	img.set_pixel(6, 8, mark)
	img.set_pixel(7, 8, mark)
	_map_icon = ImageTexture.create_from_image(img)
	return _map_icon


static func _face(state: String) -> Color:
	if state == "hover":
		return FACE_HOVER
	if state == "pressed" or state == "hover_pressed":
		return FACE_ON
	if state == "disabled":
		return FACE_OFF
	return FACE


static func _circle(state: String) -> StyleBoxFlat:
	## The control is the tap target. A negative expand margin draws the 18px
	## disc in the middle and leaves the rest of the control invisible.
	var selected := state == "pressed" or state == "hover_pressed"
	var box := StyleBoxFlat.new()
	box.bg_color = _face(state)
	box.border_color = RING if selected else INK
	box.set_border_width_all(3 if selected else 1)
	var inset := (HIT - SIZE) * 0.5
	box.set_expand_margin_all(-inset)
	box.set_corner_radius_all(int(SIZE))
	box.set_content_margin_all(0)
	box.anti_aliasing = false
	return box
