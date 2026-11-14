class_name ScoreboardPanel
extends Control
## Every connected player's point total, highest first, using the host-owned
## Points totals (#509). Opened from the score HUD; stays touch-sized at 480x270.

const MAX_ROWS := 8
const MARGIN := 4.0  ## art px below the hearts / points row
const PANEL_W := 118.0
const ROW_H := 10.0
const TITLE_H := 12.0
const SWATCH := Vector2(6, 8)

## Castle flag colours on the minimap / capture bar (host + other peers).
const FLAG_HOST := Color(0.23, 0.44, 0.88)
const FLAG_OTHERS := [
	Color(0.88, 0.29, 0.29),
	Color(0.55, 0.75, 0.35),
	Color(0.85, 0.65, 0.2),
	Color(0.61, 0.33, 0.77),
]

var _points: Points
var _self_id := 0
var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	z_index = 5
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.theme = load("res://art/ui/main_menu_theme.tres")
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
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
	_list.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(_list)
	get_viewport().size_changed.connect(follow_hud_row)


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
	follow_hud_row()


func is_open() -> bool:
	return visible


func open() -> void:
	if HudLayoutVisual.blocks_hud_actions():
		return
	mouse_filter = MOUSE_FILTER_STOP
	visible = true
	_refresh()
	follow_hud_row()


func close() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE


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


## Readable lines as drawn (name, optional swatch, total) for tests and drives.
func display_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for peer_id in _join_order():
		lines.append(_row_text(peer_id, _points.total_of(peer_id)))
	return lines


func panel_height() -> float:
	return custom_minimum_size.y * scale.y


func follow_hud_row() -> void:
	var hearts := get_node_or_null("../HeartsHud") as Control
	var score := get_node_or_null("../ScoreHud") as Control
	var toggle := get_node_or_null("../ScoreboardToggle") as Control
	if score == null:
		return
	var k := hearts.scale.x if hearts != null else 1.0
	scale = Vector2(k, k)
	var left := hearts.position.x if hearts != null else score.position.x
	var bottom := score.position.y + score.size.y * k
	if toggle != null and toggle.is_visible_in_tree():
		bottom = maxf(bottom, toggle.position.y + toggle.size.y * toggle.scale.y)
	position = Vector2(left, bottom + MARGIN * k)
	size = custom_minimum_size


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
	for row in sorted_rows():
		var peer_id: int = row[0]
		var total: int = row[1]
		_list.add_child(_make_row(peer_id, total))
	var row_count := maxi(sorted_rows().size(), 1)
	custom_minimum_size = Vector2(PANEL_W, TITLE_H + row_count * ROW_H + 6.0)
	follow_hud_row()


func _make_row(peer_id: int, total: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = SWATCH
	swatch.color = _flag_color(peer_id)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)
	var label := Label.new()
	label.text = _row_text(peer_id, total)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


func _row_text(peer_id: int, total: int) -> String:
	return "%s  %d" % [_player_name(peer_id), total]


func _player_name(peer_id: int) -> String:
	if peer_id == _self_id:
		return "You"
	var custom := _display_name_of(peer_id)
	if custom != "":
		return custom
	return "Player %d" % _join_index(peer_id)


func _display_name_of(peer_id: int) -> String:
	var world := get_node_or_null("/root/Flagoria/World")
	if world == null:
		return ""
	var body := world.get_node_or_null(str(peer_id))
	if body == null:
		return ""
	if body.has_method("get_display_name"):
		var name_text: String = body.get_display_name()
		return name_text.strip_edges()
	return ""


func _join_order() -> Array:
	var ids := _connected_peer_ids()
	ids.sort()
	return ids


func _join_index(peer_id: int) -> int:
	return _join_order().find(peer_id) + 1


func _flag_color(peer_id: int) -> Color:
	if peer_id == Points.SERVER_ID:
		return FLAG_HOST
	var idx := _join_index(peer_id) - 2
	if idx < 0:
		idx = 0
	return FLAG_OTHERS[idx % FLAG_OTHERS.size()]


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