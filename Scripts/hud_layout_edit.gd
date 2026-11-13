extends Control
## Customize HUD: drag and resize the touch controls over the live HUD.
## Solo play pauses the tree; in multiplayer only this peer's view changes.

const LAYER_PATH := "/root/Flagoria/CanvasLayer1"

@onready var _save: Button = $Panel/Margin/VBox/Save
@onready var _reset: Button = $Panel/Margin/VBox/Reset
@onready var _done: Button = $Panel/Margin/VBox/Done
@onready var _size_row: HBoxContainer = $Panel/Margin/VBox/SizeRow
@onready var _size_slider: HSlider = $Panel/Margin/VBox/SizeRow/SizeSlider
@onready var _hint: Label = $Panel/Margin/VBox/Hint

var _selected := ""
var _drag_id := ""
var _drag_offset := Vector2.ZERO
var _paused := false
var _touches: Dictionary = {}
var _pinch_distance := 0.0
var _pinch_base_scale := 1.0


func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save.pressed.connect(_on_save)
	_reset.pressed.connect(_on_reset)
	_done.pressed.connect(_on_done)
	_size_slider.min_value = HudLayout.SCALE_MIN
	_size_slider.max_value = HudLayout.SCALE_MAX
	_size_slider.step = 0.05
	_size_slider.value_changed.connect(_on_slider)


func open() -> void:
	var layer := _layer()
	if layer == null:
		return
	show()
	_selected = ""
	_size_row.hide()
	HudLayout.edit_begin(layer)
	HudLayout.apply(layer)
	_set_pause(_solo_match())
	var menu := get_parent()
	menu.get_node("Pause").hide()
	menu.menu_button.hide()
	_hint.text = "Drag a control. Pinch or use the slider to resize."


func close_editor() -> void:
	HudLayout.edit_end()
	_set_pause(false)
	hide()
	var menu := get_parent()
	menu.menu_button.show()


func _set_pause(on: bool) -> void:
	if on == _paused:
		return
	_paused = on
	get_tree().paused = on


func _solo_match() -> bool:
	var mp := get_tree().get_multiplayer()
	if mp.multiplayer_peer is OfflineMultiplayerPeer:
		return true
	return mp.is_server() and mp.get_peers().is_empty()


func _layer() -> CanvasLayer:
	return get_node_or_null(LAYER_PATH) as CanvasLayer


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var layer := _layer()
	if layer == null:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
			if _touches.size() == 1 and _drag_id == "":
				_begin_drag(touch.position, layer)
		else:
			_touches.erase(touch.index)
			if touch.index == 0 or _touches.is_empty():
				_drag_id = ""
			_pinch_distance = 0.0
		if _touches.size() == 2 and _selected != "":
			var pts: Array = _touches.values()
			_pinch_distance = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			var entry := HudLayout.get_entry(_selected)
			_pinch_base_scale = float(entry.get("s", 1.0)) if not entry.is_empty() else HudLayout.scale_of(_selected, layer)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touches.has(drag.index):
			_touches[drag.index] = drag.position
		if _drag_id != "" and _touches.size() < 2:
			_move_drag(drag.position, layer)
		elif _touches.size() == 2 and _selected != "" and _pinch_distance > 0.0:
			var pts: Array = _touches.values()
			var dist := (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			var s := clampf(_pinch_base_scale * dist / _pinch_distance, HudLayout.SCALE_MIN, HudLayout.SCALE_MAX)
			_size_slider.set_value_no_signal(s)
			_apply_scale(_selected, s, layer)


func _begin_drag(pos: Vector2, layer: CanvasLayer) -> void:
	var id := _pick_control(pos, layer)
	if id == "":
		return
	_selected = id
	_drag_id = id
	var rect := HudLayout.control_hit_rect(id, layer)
	_drag_offset = pos - rect.position
	var entry := HudLayout.get_entry(id)
	var s: float = float(entry.get("s", 1.0)) if not entry.is_empty() else HudLayout.scale_of(id, layer)
	_size_slider.set_value_no_signal(s)
	_size_row.show()


func _move_drag(pos: Vector2, layer: CanvasLayer) -> void:
	var view := layer.get_viewport().get_visible_rect().size
	var entry := HudLayout.get_entry(_drag_id)
	var s: float = float(entry.get("s", 1.0))
	var top := (pos - _drag_offset) / view
	HudLayout.try_place(_drag_id, top.x, top.y, s, layer)


func _on_slider(value: float) -> void:
	var layer := _layer()
	if layer == null or _selected == "":
		return
	_apply_scale(_selected, value, layer)


func _apply_scale(id: String, s: float, layer: CanvasLayer) -> void:
	var entry := HudLayout.get_entry(id)
	var x: float = float(entry.get("x", 0.0))
	var y: float = float(entry.get("y", 0.0))
	if entry.is_empty():
		var rect := HudLayout.control_hit_rect(id, layer)
		var view := layer.get_viewport().get_visible_rect().size
		x = rect.position.x / view.x
		y = rect.position.y / view.y
	HudLayout.try_place(id, x, y, s, layer)


func _on_save() -> void:
	HudLayout.save_to_disk()
	_hint.text = "Layout saved on this device."


func _on_reset() -> void:
	HudLayout.reset_to_defaults()
	var layer := _layer()
	if layer == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	HudLayout.capture_into_draft(layer)
	HudLayout.apply(layer)
	_hint.text = "Default layout restored."


func _on_done() -> void:
	close_editor()
	get_parent().close()


func _pick_control(pos: Vector2, layer: CanvasLayer) -> String:
	var best := ""
	var best_area := INF
	for id in HudLayout.IDS:
		var rect := HudLayout.control_hit_rect(id, layer)
		if rect.size == Vector2.ZERO:
			continue
		if not rect.has_point(pos):
			continue
		var area := rect.size.x * rect.size.y
		if area < best_area:
			best_area = area
			best = id
	return best
