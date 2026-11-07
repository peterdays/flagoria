class_name MapWoodButton
extends Control
## A header control in the wood panel's own colours: ink on a light wood face.
## Collapse, maximize, reopen, close and recentre. Not a theme button.

signal activated

enum Glyph { MINUS, SQUARE, PANEL, CROSS, X }

const INK := Color("2a2238")
const FACE := Color("e0a96b")
const EDGE := Color("74452a")
const HI := Color("ffe680")
const WOOD := Color("b06f3c")

var glyph := Glyph.MINUS


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	texture_filter = TEXTURE_FILTER_NEAREST
	focus_mode = FOCUS_NONE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), EDGE)
	draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), FACE)
	draw_rect(Rect2(1, 1, size.x - 2, 1), HI)
	var mid := size * 0.5
	match glyph:
		Glyph.MINUS:
			draw_rect(Rect2(mid.x - 5, mid.y - 1, 10, 2), INK)
		Glyph.SQUARE:
			draw_rect(Rect2(mid.x - 4, mid.y - 4, 8, 8), INK)
			draw_rect(Rect2(mid.x - 2, mid.y - 2, 4, 4), FACE)
		Glyph.PANEL:
			# A small map, and a chevron on the right: tap to open the panel again.
			draw_rect(Rect2(3, 4, 22, size.y - 8), WOOD)
			draw_rect(Rect2(3, 4, 22, 3), EDGE)
			draw_rect(Rect2(5, 8, 18, size.y - 13), INK)
			draw_rect(Rect2(7, 10, 14, size.y - 17), FACE)
			_chevron(Vector2(size.x - 14, mid.y), true)
		Glyph.CROSS:
			draw_rect(Rect2(mid.x - 1, mid.y - 4, 2, 8), INK)
			draw_rect(Rect2(mid.x - 4, mid.y - 1, 8, 2), INK)
		Glyph.X:
			for i in 7:
				draw_rect(Rect2(mid.x - 4 + i, mid.y - 4 + i, 2, 2), INK)
				draw_rect(Rect2(mid.x + 2 - i, mid.y - 4 + i, 2, 2), INK)


func _chevron(at: Vector2, up: bool) -> void:
	# The point is the top of an opening chevron, or the bottom of a closing one.
	var tip := -3 if up else 3
	for i in 4:
		var y := at.y + tip + (i if up else -i)
		draw_rect(Rect2(at.x - i, y, 2, 2), INK)
		draw_rect(Rect2(at.x + i - 1, y, 2, 2), INK)


func _gui_input(event: InputEvent) -> void:
	var down := false
	var hit := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		hit = true
		down = event.pressed
	elif event is InputEventScreenTouch:
		hit = true
		down = event.pressed
	if not hit:
		return
	if down:
		activated.emit()
	accept_event()
