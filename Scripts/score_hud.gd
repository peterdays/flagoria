class_name ScoreHud
extends Control
## The local player's point total and a toggle for the scoreboard. Under the
## hearts at the hearts' pixel scale so both stay crisp on any screen.

const GAP := 2  ## art px between the hearts and the counter
const TOGGLE_HIT := 20.0  ## tap target at 1x art

var _counter: Label
var _toggle: Button
var _points: Points
var _peer_id := 0


func _init() -> void:
	_counter = Label.new()
	_counter.name = "Counter"
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle = Button.new()
	_toggle.name = "Toggle"
	_toggle.text = "\u2261"
	_toggle.tooltip_text = "Scores"
	_toggle.focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_counter.theme = theme
	add_child(_counter)
	add_child(_toggle)
	_fit_toggle()
	_toggle.pressed.connect(_on_toggle_pressed)
	get_viewport().size_changed.connect(_relayout)


func _process(_delta: float) -> void:
	follow_hearts()


var text: String:
	get:
		return _counter.text
	set(value):
		_counter.text = value


func follow_hearts() -> void:
	var hearts := get_node_or_null("../HeartsHud") as Control
	if hearts == null:
		return
	scale = hearts.scale
	position = hearts.position + Vector2(0, (hearts.size.y + GAP) * hearts.scale.y)
	_relayout()


func bind(points: Points, peer_id: int) -> void:
	## Follow `peer_id`'s total in `points` and wire the scoreboard.
	_points = points
	_peer_id = peer_id
	if not points.total_changed.is_connected(_on_total_changed):
		points.total_changed.connect(_on_total_changed)
		points.totals_received.connect(_refresh)
	_refresh()
	follow_hearts()
	var panel := get_node_or_null("../ScoreboardPanel") as ScoreboardPanel
	if panel != null:
		panel.bind(points, peer_id)
	show()


func toggle_path() -> NodePath:
	return NodePath(str(get_path_to(_toggle)))


func _on_total_changed(changed_id: int, _total: int, _amount: int, _reason: String) -> void:
	if changed_id == _peer_id:
		_refresh()


func _refresh() -> void:
	text = "%d pts" % (_points.total_of(_peer_id) if _points else 0)


func _on_toggle_pressed() -> void:
	if HudLayoutVisual.blocks_hud_actions():
		_toggle.set_pressed_no_signal(false)
		return
	var panel := get_node_or_null("../ScoreboardPanel") as ScoreboardPanel
	if panel != null:
		panel.toggle()


func _fit_toggle() -> void:
	var theme_res: Theme = load("res://art/ui/main_menu_theme.tres")
	if theme_res:
		_toggle.theme = theme_res
	_counter.theme = theme if theme != null else theme_res
	_toggle.custom_minimum_size = Vector2(TOGGLE_HIT, TOGGLE_HIT)
	_relayout()


func _relayout() -> void:
	_counter.reset_size()
	var gap := 2.0
	var w := _counter.size.x + gap + TOGGLE_HIT
	var h := maxf(_counter.size.y, TOGGLE_HIT)
	custom_minimum_size = Vector2(w, h)
	size = custom_minimum_size
	_counter.position = Vector2.ZERO
	_toggle.position = Vector2(_counter.size.x + gap, (h - TOGGLE_HIT) * 0.5)
	_toggle.size = Vector2(TOGGLE_HIT, TOGGLE_HIT)