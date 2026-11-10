class_name RoundHudStyle
extends RefCounted
## Shared circle for the HUD row under the wood counter (#450).
## The menu theme's colours, drawn as a disc so Run, the build tools, the
## minimap and the mode button match.

const SIZE := 18.0
const INK := Color(0.078, 0.106, 0.106, 1)
const FACE := Color(0.373, 0.443, 0.376, 1)
const FACE_HOVER := Color(0.553, 0.592, 0.498, 1)
const FACE_DOWN := Color(0.204, 0.353, 0.322, 1)
const FACE_OFF := Color(0.306, 0.282, 0.29, 1)

static var _map_icon: Texture2D


static func apply(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _circle(_face(state)))
	# Style first: assigning size before the circle is in place is clamped to
	# the theme button's text minimum, and that larger size never shrinks.
	button.custom_minimum_size = Vector2(SIZE, SIZE)
	button.reset_size()


static func map_icon() -> Texture2D:
	## A tiny chart, the same colours as the wood panel, for the minimap button.
	if _map_icon != null:
		return _map_icon
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	var ink := Color("2a2238")
	var water := Color("7cc8f2")
	var sand := Color("e8c968")
	var grass := Color("6fbf3a")
	for y in 14:
		for x in 14:
			var colour := Color(0, 0, 0, 0)
			if x == 0 or y == 0 or x == 13 or y == 13:
				colour = Color(0, 0, 0, 0)
			elif x == 1 or y == 1 or x == 12 or y == 12:
				colour = ink
			elif y < 6:
				colour = water
			elif y < 8:
				colour = sand
			else:
				colour = grass
			img.set_pixel(x, y, colour)
	img.set_pixel(7, 9, ink)
	img.set_pixel(8, 9, ink)
	_map_icon = ImageTexture.create_from_image(img)
	return _map_icon


static func _face(state: String) -> Color:
	if state == "hover":
		return FACE_HOVER
	if state == "pressed" or state == "hover_pressed":
		return FACE_DOWN
	if state == "disabled":
		return FACE_OFF
	return FACE


static func _circle(face: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = face
	box.border_color = INK
	box.set_border_width_all(1)
	box.set_corner_radius_all(int(SIZE))
	box.set_content_margin_all(0)
	box.anti_aliasing = false
	return box
