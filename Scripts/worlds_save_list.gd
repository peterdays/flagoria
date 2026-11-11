extends ItemList
## Saved-world rows inside a ScrollContainer. Forwards drags to the scroll box
## so touch scroll works; short taps still select a row.


var _scroll: ScrollContainer
var _touch_y := 0.0
var _dragging := false


func _ready() -> void:
	_scroll = get_parent() as ScrollContainer


func _gui_input(event: InputEvent) -> void:
	if _scroll == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_y = event.position.y
			_dragging = false
		elif _dragging:
			accept_event()
			_touch_y = 0.0
			_dragging = false
	elif event is InputEventScreenDrag:
		if not _dragging and abs(event.position.y - _touch_y) > _scroll.scroll_deadzone:
			_dragging = true
		if _dragging:
			var max_v := int(_scroll.get_v_scroll_bar().max_value)
			_scroll.scroll_vertical = clampi(_scroll.scroll_vertical - int(event.relative.y), 0, max_v)
			accept_event()
	elif event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MASK_LEFT:
		var max_v := int(_scroll.get_v_scroll_bar().max_value)
		_scroll.scroll_vertical = clampi(_scroll.scroll_vertical - int(event.relative.y), 0, max_v)
		accept_event()
