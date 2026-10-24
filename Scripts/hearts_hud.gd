class_name HeartsHud
extends Control
## A small row of hearts for the local player's health, drawn in a screen
## corner at the game's pixel size so it covers little of the view.
##
## The icons below are the only place the HUD art is referenced: to restyle
## the hearts, replace the PNGs (same names) or these paths.

const ICON_FULL: Texture2D = preload("res://art/ui/hearts/ui_heart_full.png")
const ICON_HALF: Texture2D = preload("res://art/ui/hearts/ui_heart_half.png")
const ICON_EMPTY: Texture2D = preload("res://art/ui/hearts/ui_heart_empty.png")
## Shown on a heart that just lost health: FLASH_0, then FLASH_1, then the new state.
const ICON_FLASH_0: Texture2D = preload("res://art/ui/hearts/ui_heart_flash_0.png")
const ICON_FLASH_1: Texture2D = preload("res://art/ui/hearts/ui_heart_flash_1.png")
const SPACING := 1  ## px between hearts at 1x (10 px pitch for 9x9 icons)
const MARGIN := 4  ## px from the screen corner at 1x
const FLASH_FRAME := 0.06  ## seconds each flash icon is shown

var current := 0
var maximum := 0
var _flash_slots: Array[int] = []
var _flash_time := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_viewport().size_changed.connect(_fit_pixel_scale)
	_fit_pixel_scale()


func bind(health: PlayerHealth) -> void:
	## Follow one player's health and show the row.
	health.health_changed.connect(set_health)
	# A late copy's state reply is not a loss happening now: no flash.
	health.state_received.connect(set_health.bind(false))
	set_health(health.health, health.max_health)
	show()


func set_health(value: int, max_value: int, flash := true) -> void:
	## `flash` false shows the new value with no loss flash.
	if flash and max_value == maximum and value < current:
		_flash_slots.clear()
		for i in ceili(maximum / 2.0):
			if icon_for(i, value) != icon_for(i, current):
				_flash_slots.append(i)
		_flash_time = 0.0
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


func shown_icon(slot: int) -> Texture2D:
	## The icon drawn in `slot` right now, including a loss flash.
	if _flash_time >= 0.0 and slot in _flash_slots:
		return ICON_FLASH_0 if _flash_time < FLASH_FRAME else ICON_FLASH_1
	return icon_for(slot, current)


func advance(delta: float) -> void:
	## Step the loss flash; it ends after two FLASH_FRAMEs.
	if _flash_time < 0.0:
		return
	_flash_time += delta
	if _flash_time >= FLASH_FRAME * 2.0:
		_flash_time = -1.0
		_flash_slots.clear()
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


func _fit_pixel_scale() -> void:
	## Keep the hearts at a whole number of screen pixels per art pixel (the
	## window stretch can be fractional), MARGIN art pixels from the corner.
	var stretch := get_viewport().get_final_transform().get_scale().x
	if stretch <= 0.0:
		return
	var k := maxf(roundf(stretch), 1.0) / stretch
	scale = Vector2(k, k)
	position = Vector2(MARGIN, MARGIN) * k


func _draw() -> void:
	var step := ICON_FULL.get_width() + SPACING
	for i in ceili(maximum / 2.0):
		draw_texture(shown_icon(i), Vector2(i * step, 0))
