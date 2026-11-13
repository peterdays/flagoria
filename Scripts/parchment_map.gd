class_name ParchmentMap
extends Control
## The full explored map on old parchment. The world keeps running underneath.
## While this is open the local hero cannot move or attack, wheel and pinch
## zoom are used up, a drag pans the sheet, and a hit on the hero closes it.
## Close, or Esc, returns to the wood panel as it was.

const GROUP := "fullscreen_map"
const INSET := 8
const CELL_PX := 2
const DEFAULT_CELL_PX := 2  ## opening zoom; one world cell per two art pixels
const MAX_CELL_PX := 16  ## cells are easy to read
const FOG_TILE_CELLS := 16  ## fog pattern repeats every this many cells at default zoom
## Aged paper, in the same ink and wood family as the panel frame.
const PAPER := Color("e7d7b1")
const PAPER_SHADE := Color("cbb98a")
const PAPER_EDGE := Color("8a5a32")
const PAPER_HI := Color("f3e6c4")
const INK := Color("2a2238")

var panel: MinimapPanel
var pan := Vector2.ZERO  ## pixels added to the hero-centred origin
var cell_px := DEFAULT_CELL_PX  ## art pixels per world cell; nearest-filter steps
var _health: PlayerHealth
var _press_pos := Vector2.ZERO
var _press_pan := Vector2.ZERO
var _view: Control
var _fog: ImageTexture
var _close: MapWoodButton
var _recentre: MapWoodButton
var _touches := {}  ## touch index -> screen position
var _pinch_span := 0.0
var _pinch_cell_px := DEFAULT_CELL_PX


func _ready() -> void:
	name = "ParchmentMap"
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	texture_filter = TEXTURE_FILTER_NEAREST
	z_index = 20
	add_to_group(GROUP)
	_fog = ImageTexture.create_from_image(_fog_image())
	_view = Control.new()
	_view.name = "MapView"
	_view.clip_contents = true
	_view.mouse_filter = MOUSE_FILTER_IGNORE
	_view.texture_filter = TEXTURE_FILTER_NEAREST
	_view.draw.connect(_draw_map)
	add_child(_view)
	_close = _button("CloseButton", MapWoodButton.Glyph.X, _on_close)
	_recentre = _button("RecentreButton", MapWoodButton.Glyph.CROSS, _on_recentre)
	resized.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit()


func is_open() -> bool:
	return visible


func show_map() -> void:
	pan = Vector2.ZERO
	cell_px = DEFAULT_CELL_PX
	_bind_health()
	show()
	_fit()
	_view.queue_redraw()


func hide_map() -> void:
	hide()
	_unbind_health()
	_touches.clear()
	_pinch_span = 0.0


func min_cell_px() -> int:
	## The smallest integer step that still fits the explored chart in the viewport.
	if panel == null:
		return DEFAULT_CELL_PX
	var rect := panel.explored.explored_rect()
	if rect.size == Vector2i.ZERO:
		return DEFAULT_CELL_PX
	var window := _view.size
	if window.x <= 1.0 or window.y <= 1.0:
		return DEFAULT_CELL_PX
	var cells := rect.size + Vector2i.ONE
	var fit := mini(floori(window.x / float(cells.x)), floori(window.y / float(cells.y)))
	return clampi(maxi(1, fit), 1, MAX_CELL_PX)


func map_pixel_at_view(focus: Vector2) -> Vector2:
	## World map pixel under a point in MapView local coordinates.
	return _origin() + focus


func _button(node_name: String, glyph: int, handler: Callable) -> MapWoodButton:
	var button := MapWoodButton.new()
	button.name = node_name
	button.glyph = glyph
	button.size = Vector2(22, 18)
	button.activated.connect(handler)
	add_child(button)
	return button


func _fit() -> void:
	var rect := get_viewport_rect()
	position = Vector2.ZERO
	size = rect.size
	_view.position = Vector2(INSET, INSET)
	_view.size = Vector2(maxi(size.x - INSET * 2, 1), maxi(size.y - INSET * 2, 1))
	# Top-left, under the hearts, so closing does not land on the menu button.
	_recentre.position = Vector2(8, 36)
	_close.position = Vector2(32, 36)
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		_view.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Mouse events made from a finger are ignored: the touch event pans once.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed:
			if button.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(_view_focus(button.position), cell_px + 1)
				accept_event()
				return
			if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(_view_focus(button.position), cell_px - 1)
				accept_event()
				return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_press_pos = button.position
				_press_pan = pan
			accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		# The sheet follows the finger.
		pan = _press_pan - (event.position - _press_pos)
		_view.queue_redraw()
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touches.size() >= 2:
				accept_event()
				return
			_touches[touch.index] = touch.position
			if _touches.size() == 1:
				_press_pos = touch.position
				_press_pan = pan
			if _touches.size() == 2:
				_pinch_span = _touch_span()
				_pinch_cell_px = cell_px
		else:
			_touches.erase(touch.index)
			_pinch_span = 0.0
		accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touches.has(drag.index):
			_touches[drag.index] = drag.position
		if _touches.size() == 2 and _pinch_span > 0.0:
			var span := _touch_span()
			if span > 0.0:
				var stepped := clampi(roundi(_pinch_cell_px * span / _pinch_span), min_cell_px(), MAX_CELL_PX)
				_zoom_at(_view_focus(_pinch_mid()), stepped)
				_pinch_span = span
				_pinch_cell_px = cell_px
		elif _touches.size() == 1:
			pan = _press_pan - (drag.position - _press_pos)
			_view.queue_redraw()
		accept_event()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_close()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER_EDGE)
	draw_rect(Rect2(3, 3, size.x - 6, size.y - 6), PAPER)
	draw_rect(Rect2(3, 3, size.x - 6, 1), PAPER_HI)
	var frame := Rect2(INSET - 1, INSET - 1, _view.size.x + 2, _view.size.y + 2)
	draw_rect(frame, INK, false, 1.0)


func _draw_map() -> void:
	var window := _view.size
	var fog_step := FOG_TILE_CELLS * cell_px
	var fog_size := Vector2(_fog.get_width(), _fog.get_height())
	var y := 0.0
	while y < window.y:
		var x := 0.0
		while x < window.x:
			_view.draw_texture_rect(_fog, Rect2(Vector2(x, y), Vector2(fog_step, fog_step)), false)
			x += fog_step
		y += fog_step
	if panel == null:
		return
	var origin := _origin()
	var top_left := Vector2i(floori(origin.x / cell_px), floori(origin.y / cell_px))
	var extent := Vector2i(ceili(window.x / cell_px), ceili(window.y / cell_px))
	var first := ExploredMap.chunk_of(top_left)
	var last := ExploredMap.chunk_of(top_left + extent)
	var chunk_px := ExploredMap.CHUNK * cell_px
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var tex: ImageTexture = panel.chunk_texture(Vector2i(cx, cy))
			if tex:
				var at := Vector2(Vector2i(cx, cy) * ExploredMap.CHUNK * cell_px) - origin
				_view.draw_texture_rect(tex, Rect2(at, Vector2(chunk_px, chunk_px)), false)
	var marker: Texture2D = MinimapPanel.HERO.get(panel.facing, MinimapPanel.HERO["Down"])
	var marker_scale := float(cell_px) / float(MinimapPanel.CELL_PX)
	var marker_size := marker.get_size() * marker_scale
	var hero_at := Vector2(panel.hero_cell * cell_px) - origin \
			+ Vector2.ONE * marker_scale - Vector2(MinimapPanel.HERO_ANCHOR) * marker_scale
	_view.draw_texture_rect(marker, Rect2(hero_at, marker_size), false)
	panel.paint_city_walls(_view, top_left, Vector2i(window), cell_px)


func _origin() -> Vector2:
	return Vector2(panel.hero_cell * cell_px) - _view.size * 0.5 + pan


func _zoom_at(focus: Vector2, stepped: int) -> void:
	var clamped := clampi(stepped, min_cell_px(), MAX_CELL_PX)
	if clamped == cell_px:
		return
	var anchor := map_pixel_at_view(focus)
	cell_px = clamped
	var new_origin := anchor - focus
	pan = new_origin - Vector2(panel.hero_cell * cell_px) + _view.size * 0.5
	_view.queue_redraw()


func _view_focus(screen_pos: Vector2) -> Vector2:
	return screen_pos - _view.position


func _touch_span() -> float:
	var pts: Array = _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1])


func _pinch_mid() -> Vector2:
	var pts: Array = _touches.values()
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func _on_close() -> void:
	hide_map()
	if panel:
		panel.apply_chrome()


func _on_recentre() -> void:
	pan = Vector2.ZERO
	_view.queue_redraw()


func _on_damaged(_amount: int) -> void:
	if visible:
		_on_close()


func _bind_health() -> void:
	_unbind_health()
	var player := panel.local_player() if panel else null
	if player == null:
		return
	_health = player.get_node_or_null("Health") as PlayerHealth
	if _health and not _health.damaged.is_connected(_on_damaged):
		_health.damaged.connect(_on_damaged)


func _unbind_health() -> void:
	if _health and _health.damaged.is_connected(_on_damaged):
		_health.damaged.disconnect(_on_damaged)
	_health = null


func _fog_image() -> Image:
	## Paper fog: a dither of the sheet, not the panel's blue mist.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var grain := (x + 2 * y) % 4 == 0
			var speck := (x * 5 + y * 3) % 37 == 0
			img.set_pixel(x, y, PAPER_EDGE if speck else (PAPER_SHADE if grain else PAPER))
	return img
