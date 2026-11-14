extends Control
## Customize HUD: drag and resize the touch controls over the live HUD.
## Solo play pauses the tree; in multiplayer only this peer's view changes.

const LAYER_PATH := "/root/Flagoria/CanvasLayer1"
const SCALE_MIN := 1.0
const SCALE_MAX := 1.75
const CONTROL_IDS := ["joystick", "attack", "run", "buildings", "map", "mode", "scores"]
const BAR_EDGE_INSET := 6.0
const BAR_PAD := 2.0

@onready var _top_bar: PanelContainer = $TopBar
@onready var _save: Button = $TopBar/Margin/Row/Save
@onready var _reset: Button = $TopBar/Margin/Row/Reset
@onready var _done: Button = $TopBar/Margin/Row/Done
@onready var _size_slider: HSlider = $TopBar/Margin/Row/SizeSlider
@onready var _size_label: Label = $TopBar/Margin/Row/SizeLabel
@onready var _selected_label: Label = $TopBar/Margin/Row/Selected

var _selected := ""
var _drag_id := ""
var _drag_offset := Vector2.ZERO
var _paused := false
var _touches: Dictionary = {}
var _pinch_distance := 0.0
var _pinch_base_scale := 1.0
var _relayout_bar_queued := false


func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	for btn in [_save, _reset, _done, _size_slider]:
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_save.pressed.connect(_on_save)
	_reset.pressed.connect(_on_reset)
	_done.pressed.connect(_on_done)
	_size_slider.min_value = SCALE_MIN
	_size_slider.max_value = SCALE_MAX
	_size_slider.step = 0.05
	_size_slider.value_changed.connect(_on_slider)
	_size_slider.editable = false


func _hl() -> Node:
	return get_node("/root/HudLayout")


func open() -> void:
	var layer := _layer()
	if layer == null:
		return
	show()
	_selected = ""
	_size_slider.editable = false
	_selected_label.text = "Tap a HUD control · drag · pinch"
	_hl().edit_begin(layer)
	_hl().apply(layer)
	_set_pause(_should_pause_game())
	var menu := get_parent()
	menu.get_node("Pause").hide()
	menu.menu_button.hide()
	await _relayout_edit_bar(layer)


func relayout_bar() -> void:
	var layer := _layer()
	if layer != null:
		await _relayout_edit_bar(layer)


func close_editor() -> void:
	_hl().edit_end()
	_set_pause(false)
	hide()
	var menu := get_parent()
	menu.menu_button.show()


func _set_pause(on: bool) -> void:
	if on == _paused:
		return
	_paused = on
	get_tree().paused = on


func _should_pause_game() -> bool:
	## Solo play pauses live matches, not headless CI, verify, or feature drives.
	if DisplayServer.get_name() == "headless":
		return false
	if OS.get_environment("FLAGORIA_VERIFY_RUN") != "":
		return false
	if OS.get_environment("VERIFY_EVIDENCE_DIR") != "":
		return false
	return _solo_match()


func _solo_match() -> bool:
	var mp := get_tree().get_multiplayer()
	if mp.multiplayer_peer is OfflineMultiplayerPeer:
		return true
	return mp.is_server() and mp.get_peers().is_empty()


func _layer() -> CanvasLayer:
	return get_node_or_null(LAYER_PATH) as CanvasLayer


func _relayout_edit_bar(layer: CanvasLayer) -> void:
	_top_bar.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	_top_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_top_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_top_bar.custom_minimum_size = Vector2.ZERO
	_size_label.visible = true
	_size_slider.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var sz := _top_bar.get_combined_minimum_size()
	if _top_bar.size.y > 0.0:
		sz.y = maxf(sz.y, _top_bar.size.y)
	if _top_bar.size.x > 0.0:
		sz.x = maxf(sz.x, _top_bar.size.x)
	_top_bar.size = sz
	var view := get_viewport().get_visible_rect().size
	var floor_y := view.y * 0.55
	var joy: Rect2 = _hl().control_visual_rect("joystick", layer)
	var atk: Rect2 = _hl().control_visual_rect("attack", layer)
	var slot_left: float = joy.end.x + BAR_EDGE_INSET if joy.size != Vector2.ZERO else BAR_EDGE_INSET
	var slot_right: float = atk.position.x - BAR_EDGE_INSET if atk.size != Vector2.ZERO else view.x - BAR_EDGE_INSET
	var slot_w := maxf(0.0, slot_right - slot_left)
	var bar_w := sz.x
	if slot_w > 0.0 and slot_w < bar_w:
		bar_w = maxf(slot_w, 140.0)
		if bar_w < sz.x:
			_top_bar.custom_minimum_size = Vector2(bar_w, 0.0)
			if bar_w < 200.0:
				_size_label.visible = false
				_size_slider.visible = false
			await get_tree().process_frame
			sz = _top_bar.get_combined_minimum_size()
			sz.x = bar_w
			_top_bar.size = sz
	var bottom_y := view.y - sz.y - BAR_EDGE_INSET
	var candidates: Array[Vector2] = []
	if slot_w >= bar_w * 0.85:
		candidates.append(Vector2(slot_left + (slot_w - bar_w) * 0.5, bottom_y))
	candidates.append_array([
		Vector2((view.x - bar_w) * 0.5, bottom_y),
		Vector2(view.x - bar_w - BAR_EDGE_INSET, bottom_y),
		Vector2(BAR_EDGE_INSET, maxf(floor_y, bottom_y)),
		Vector2(BAR_EDGE_INSET, BAR_EDGE_INSET),
	])
	var best_pos := candidates[0]
	var best_score := INF
	var zero_pos: Variant = null
	for pos in candidates:
		_top_bar.global_position = pos
		await get_tree().process_frame
		var score := _bar_overlap_score(layer)
		if score == 0.0:
			zero_pos = pos
			break
		if score < best_score:
			best_score = score
			best_pos = pos
	if zero_pos != null:
		best_pos = zero_pos
	_top_bar.global_position = best_pos
	await get_tree().process_frame
	_hl().set_edit_exclusion(_top_bar.get_global_rect().grow(BAR_PAD))


func _bar_overlap_score(layer: CanvasLayer) -> float:
	var bar := _top_bar.get_global_rect().grow(BAR_PAD)
	var area := 0.0
	for id in CONTROL_IDS:
		var rect: Rect2 = _hl().control_visual_rect(id, layer)
		if rect.size == Vector2.ZERO:
			continue
		var hit: Rect2 = bar.intersection(rect)
		if hit.size != Vector2.ZERO:
			area += hit.size.x * hit.size.y
	if _selected != "":
		var sel: Rect2 = _hl().control_visual_rect(_selected, layer)
		if sel.size != Vector2.ZERO and bar.intersects(sel):
			area += 1000000.0
	return area


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
			if _touches.size() == 1 and _drag_id == "" and not _top_bar.get_global_rect().has_point(touch.position):
				_begin_drag(touch.position, layer)
				if _drag_id != "":
					get_viewport().set_input_as_handled()
		else:
			_touches.erase(touch.index)
			if touch.index == 0 or _touches.is_empty():
				_drag_id = ""
			_pinch_distance = 0.0
		if _touches.size() == 2 and _selected != "":
			var pts: Array = _touches.values()
			_pinch_distance = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			var entry: Dictionary = _hl().get_entry(_selected)
			_pinch_base_scale = float(entry.get("s", 1.0)) if not entry.is_empty() else _hl().scale_of(_selected, layer)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touches.has(drag.index):
			_touches[drag.index] = drag.position
		if _drag_id != "" and _touches.size() < 2:
			_move_drag(drag.position, layer)
		elif _touches.size() == 2 and _selected != "" and _pinch_distance > 0.0:
			var pts: Array = _touches.values()
			var dist := (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			var s := clampf(_pinch_base_scale * dist / _pinch_distance, SCALE_MIN, SCALE_MAX)
			_size_slider.set_value_no_signal(s)
			_apply_scale(_selected, s, layer)


func _begin_drag(pos: Vector2, layer: CanvasLayer) -> void:
	var id := _pick_control(pos, layer)
	if id == "":
		return
	_selected = id
	_drag_id = id
	var rect: Rect2 = _hl().control_hit_rect(id, layer)
	_drag_offset = pos - rect.position
	var entry: Dictionary = _hl().get_entry(id)
	var s: float = float(entry.get("s", 1.0)) if not entry.is_empty() else _hl().scale_of(id, layer)
	_size_slider.set_value_no_signal(s)
	_size_slider.editable = true
	_selected_label.text = "Selected: %s · drag · pinch" % id
	queue_redraw()


func _queue_bar_relayout() -> void:
	_relayout_bar_queued = true


func _move_drag(pos: Vector2, layer: CanvasLayer) -> void:
	var view := layer.get_viewport().get_visible_rect().size
	var entry: Dictionary = _hl().get_entry(_drag_id)
	var s: float = float(entry.get("s", 1.0))
	var top := (pos - _drag_offset) / view
	_hl().try_place(_drag_id, top.x, top.y, s, layer)
	_queue_bar_relayout()
	queue_redraw()


func _on_slider(value: float) -> void:
	var layer := _layer()
	if layer == null or _selected == "":
		return
	_apply_scale(_selected, value, layer)


func _apply_scale(id: String, s: float, layer: CanvasLayer) -> void:
	var entry: Dictionary = _hl().get_entry(id)
	var x: float = float(entry.get("x", 0.0))
	var y: float = float(entry.get("y", 0.0))
	if entry.is_empty():
		var rect: Rect2 = _hl().control_hit_rect(id, layer)
		var view := layer.get_viewport().get_visible_rect().size
		x = rect.position.x / view.x
		y = rect.position.y / view.y
	_hl().try_place(id, x, y, s, layer)
	_queue_bar_relayout()
	queue_redraw()


func _on_save() -> void:
	_hl().save_to_disk()
	_selected_label.text = "Layout saved on this device."


func _on_reset() -> void:
	var layer := _layer()
	if layer == null:
		return
	_hl().reset_to_defaults()
	var row := layer.get_node_or_null("HudToolRow") as HudToolRow
	if row != null:
		row._layout()
	_hl().edit_begin(layer)
	_set_pause(_should_pause_game())
	_selected = ""
	_drag_id = ""
	_size_slider.editable = false
	_selected_label.text = "Default layout restored · tap a control"
	_relayout_edit_bar(layer)


func _on_done() -> void:
	close_editor()
	get_parent().close()


func _pick_control(pos: Vector2, layer: CanvasLayer) -> String:
	var best := ""
	var best_area := INF
	for id in CONTROL_IDS:
		var rect: Rect2 = _hl().control_hit_rect(id, layer)
		if rect.size == Vector2.ZERO:
			continue
		if not rect.has_point(pos):
			continue
		var area := rect.size.x * rect.size.y
		if area < best_area:
			best_area = area
			best = id
	return best


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
	if _relayout_bar_queued and visible:
		_relayout_bar_queued = false
		var layer := _layer()
		if layer != null:
			_relayout_edit_bar(layer)


func _draw() -> void:
	if not visible:
		return
	var layer := _layer()
	if layer == null:
		return
	var inv := get_global_transform_with_canvas().affine_inverse()
	for id in CONTROL_IDS:
		var grect: Rect2 = _hl().control_hit_rect(id, layer)
		if grect.size == Vector2.ZERO:
			continue
		var p: Vector2 = inv * grect.position
		var q: Vector2 = inv * grect.end
		var local := Rect2(p, q - p)
		if id == _selected:
			draw_rect(local.grow(2.0), Color(1.0, 0.86, 0.28, 0.95), false, 2.0)
		elif _selected == "":
			draw_rect(local, Color(1.0, 1.0, 1.0, 0.2), false, 1.0)
