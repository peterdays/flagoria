class_name HeartsHud
extends Control
## A small row of hearts for the local player's health, drawn in a screen
## corner at the game's native pixel size so it covers little of the view.
##
## The three icons below are the only place the HUD art is referenced: to
## restyle the hearts, replace the PNGs (same names) or these paths.

const ICON_FULL: Texture2D = preload("res://art/ui/hearts/heart_full.png")
const ICON_HALF: Texture2D = preload("res://art/ui/hearts/heart_half.png")
const ICON_EMPTY: Texture2D = preload("res://art/ui/hearts/heart_empty.png")
const SPACING := 1

var current := 0
var maximum := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func bind(health: PlayerHealth) -> void:
	## Follow one player's health and show the row.
	health.health_changed.connect(set_health)
	set_health(health.health, health.max_health)
	show()


func set_health(value: int, max_value: int) -> void:
	current = value
	maximum = max_value
	var n := ceili(maximum / 2.0)
	custom_minimum_size = Vector2(maxi(n * (ICON_FULL.get_width() + SPACING) - SPACING, 0), ICON_FULL.get_height())
	size = custom_minimum_size
	queue_redraw()


static func icon_for(slot: int, value: int) -> Texture2D:
	## Heart `slot` (0 = leftmost) when health is `value` half-hearts.
	var left := value - slot * 2
	if left >= 2:
		return ICON_FULL
	if left == 1:
		return ICON_HALF
	return ICON_EMPTY


func _draw() -> void:
	var step := ICON_FULL.get_width() + SPACING
	for i in ceili(maximum / 2.0):
		draw_texture(icon_for(i, current), Vector2(i * step, 0))
