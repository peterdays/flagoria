class_name ParchmentMap
extends Control
## The full explored map on old parchment. The world keeps running underneath.
## While this is open the local hero cannot move or attack, wheel and pinch
## zoom are used up, a drag pans the sheet, and a hit on the hero closes it.
## Close, or Esc, returns to the wood panel as it was.

const GROUP := "fullscreen_map"
const INSET := 8
const CELL_PX := 2
## Aged paper, in the same ink and wood family as the panel frame.
const PAPER := Color("e7d7b1")
const PAPER_SHADE := Color("cbb98a")
const PAPER_EDGE := Color("8a5a32")
const PAPER_HI := Color("f3e6c4")
const INK := Color("2a2238")

var panel: MinimapPanel
var pan := Vector2.ZERO  ## pixels added to the hero-centred origin
var _health: PlayerHealth
var _press_pos := Vector2.ZERO
var _press_pan := Vector2.ZERO
var _view: Control
var _fog: ImageTexture
var _close: MapWoodButton
var _recentre: MapWoodButton


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
	_bind_health()
	show()
	_fit()
	_view.queue_redraw()


func hide_map() -> void:
	hide()
	_unbind_health()


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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
			_press_pan = pan
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		# The sheet follows the finger.
		pan = _press_pan - (event.position - _press_pos)
		_view.queue_redraw()
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press_pos = event.position
			_press_pan = pan
		accept_event()
	elif event is InputEventScreenDrag:
		pan = _press_pan - (event.position - _press_pos)
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
	var fog_size := Vector2(_fog.get_width(), _fog.get_height())
	var y := 0.0
	while y < window.y:
		var x := 0.0
		while x < window.x:
			_view.draw_texture(_fog, Vector2(x, y))
			x += fog_size.x
		y += fog_size.y
	if panel == null:
		return
	var origin := _origin()
	var top_left := Vector2i(floori(origin.x / CELL_PX), floori(origin.y / CELL_PX))
	var extent := Vector2i(ceili(window.x / CELL_PX), ceili(window.y / CELL_PX))
	var first := ExploredMap.chunk_of(top_left)
	var last := ExploredMap.chunk_of(top_left + extent)
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var tex: ImageTexture = panel.chunk_texture(Vector2i(cx, cy))
			if tex:
				var at := Vector2(Vector2i(cx, cy) * ExploredMap.CHUNK * CELL_PX) - origin
				_view.draw_texture(tex, at)
	var marker: Texture2D = MinimapPanel.HERO.get(panel.facing, MinimapPanel.HERO["Down"])
	var hero_at := Vector2(panel.hero_cell * CELL_PX) - origin + Vector2.ONE - Vector2(MinimapPanel.HERO_ANCHOR)
	_view.draw_texture(marker, hero_at)
	panel.paint_city_walls(_view, top_left, Vector2i(window))


func _origin() -> Vector2:
	return Vector2(panel.hero_cell * CELL_PX) - _view.size * 0.5 + pan


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
