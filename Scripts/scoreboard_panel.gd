class_name ScoreboardPanel
extends Control
## Every connected player's point total, highest first, using the host-owned
## Points totals (#509). Opened from the score HUD; stays touch-sized at 480x270.

const MAX_ROWS := 8
const MARGIN := 4.0  ## art px from the score row
const PANEL_W := 108.0
const ROW_H := 12.0
const TITLE_H := 14.0

var _points: Points
var _self_id := 0
var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 5
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.theme = load("res://art/ui/main_menu_theme.tres")
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)
	_title = Label.new()
	_title.text = "Scores"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_list)
	get_viewport().size_changed.connect(_follow_score_row)


func bind(points: Points, self_id: int) -> void:
	_points = points
	_self_id = self_id
	if not points.total_changed.is_connected(_on_points_changed):
		points.total_changed.connect(_on_points_changed)
		points.totals_received.connect(_refresh)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_refresh()
	_follow_score_row()


func is_open() -> bool:
	return visible


func open() -> void:
	if HudLayoutVisual.blocks_hud_actions():
		return
	visible = true
	_refresh()
	_follow_score_row()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## For tests: [[peer_id, total], ...] highest total first, then lower peer id.
func sorted_rows() -> Array:
	var rows: Array = []
	if _points == null:
		return rows
	for peer_id in _connected_peer_ids():
		rows.append([peer_id, _points.total_of(peer_id)])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[0] < b[0])
	return rows


func _on_points_changed(_peer_id: int, _total: int, _amount: int, _reason: String) -> void:
	_refresh()


func _on_peer_connected(_peer_id: int) -> void:
	_refresh()


func _on_peer_disconnected(_peer_id: int) -> void:
	_refresh()


func _refresh() -> void:
	if _points == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var rows := sorted_rows()
	var rank := 0
	for row in rows:
		rank += 1
		var peer_id: int = row[0]
		var total: int = row[1]
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name := "You" if peer_id == _self_id else "P%d" % rank
		label.text = "%s  %d" % [name, total]
		_list.add_child(label)
	var row_count := maxi(rows.size(), 1)
	custom_minimum_size = Vector2(PANEL_W, TITLE_H + row_count * ROW_H + 12.0)
	_follow_score_row()


func _connected_peer_ids() -> Array:
	var ids: Array = []
	if multiplayer.multiplayer_peer == null:
		ids.append(1)
		return ids
	var self_id: int = multiplayer.get_unique_id()
	ids.append(self_id)
	for peer_id in multiplayer.get_peers():
		if peer_id not in ids:
			ids.append(peer_id)
	return ids


func _follow_score_row() -> void:
	var score := get_node_or_null("../ScoreHud") as Control
	if score == null:
		return
	var hearts := get_node_or_null("../HeartsHud") as Control
	var k := hearts.scale.x if hearts != null else 1.0
	scale = Vector2(k, k)
	position = score.position + Vector2(0.0, score.size.y * score.scale.y + MARGIN * k)
	size = custom_minimum_size