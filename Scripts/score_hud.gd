class_name ScoreHud
extends Label
## The local player's point total, under the hearts. Only your own total is
## shown; there is no scoreboard of other players. It sits GAP art pixels
## under the sibling HeartsHud at the hearts' own pixel scale, so both stay
## crisp and lined up on any screen.

const GAP := 2  ## art px between the hearts and the counter

var _points: Points
var _peer_id := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	follow_hearts()


func follow_hearts() -> void:
	var hearts := get_node_or_null("../HeartsHud") as Control
	if hearts == null:
		return
	scale = hearts.scale
	position = hearts.position + Vector2(0, (hearts.size.y + GAP) * hearts.scale.y)


func bind(points: Points, peer_id: int) -> void:
	## Follow `peer_id`'s total in `points` and show the counter.
	_points = points
	_peer_id = peer_id
	if not points.total_changed.is_connected(_on_total_changed):
		points.total_changed.connect(_on_total_changed)
		points.totals_received.connect(_refresh)
	_refresh()
	follow_hearts()
	show()


func _on_total_changed(peer_id: int, _total: int, _amount: int, _reason: String) -> void:
	if peer_id == _peer_id:
		_refresh()


func _refresh() -> void:
	text = "%d pts" % (_points.total_of(_peer_id) if _points else 0)
