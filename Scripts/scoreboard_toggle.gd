class_name ScoreboardToggle
extends Button
## Round scoreboard toggle beside the points label (#509, #492).

const ICON := preload("res://assets/ui/hud/icon_scores.png")
const GAP := 2.0  ## art px past the points label


func _ready() -> void:
	tooltip_text = "Scores"
	text = ""
	icon = ICON
	focus_mode = FOCUS_NONE
	texture_filter = TEXTURE_FILTER_NEAREST
	RoundHudStyle.apply(self)
	pressed.connect(_on_pressed)
	get_viewport().size_changed.connect(_follow_score)


func _process(_delta: float) -> void:
	if _hud_layout_active():
		return
	_follow_score()


func _hud_layout_active() -> bool:
	var hl := get_node_or_null("/root/HudLayout")
	return hl != null and hl.layout_active()


func _follow_score() -> void:
	var score := get_node_or_null("../ScoreHud") as Control
	var hearts := get_node_or_null("../HeartsHud") as Control
	if score == null:
		return
	var k := hearts.scale.x if hearts != null else 1.0
	scale = Vector2(k, k)
	var hit := RoundHudStyle.HIT * k
	var score_w := score.size.x * k
	var y := score.position.y + (score.size.y * k - hit) * 0.5
	position = Vector2(score.position.x + score_w + GAP * k, y)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	var panel := get_node_or_null("../ScoreboardPanel") as ScoreboardPanel
	if panel != null:
		panel.follow_hud_row()


func _on_pressed() -> void:
	if HudLayoutVisual.blocks_hud_actions():
		set_pressed_no_signal(false)
		return
	var panel := get_node_or_null("../ScoreboardPanel") as ScoreboardPanel
	if panel != null:
		panel.toggle()


## Hit rect for Customize HUD capture when the toggle has not laid out yet.
static func layout_hit_rect(layer: CanvasLayer) -> Rect2:
	var toggle := layer.get_node_or_null("ScoreboardToggle") as Control
	if toggle != null and toggle.is_visible_in_tree():
		var ready := toggle.get_global_rect()
		if ready.size.x > 0.0:
			return ready
	var hearts := layer.get_node_or_null("HeartsHud") as Control
	if hearts == null:
		return Rect2()
	var score := layer.get_node_or_null("ScoreHud") as Control
	var k := maxf(hearts.scale.x, 0.001)
	var hit := RoundHudStyle.HIT * k
	var score_w := 36.0 * k
	var score_h := 12.0 * k
	var score_y := hearts.position.y + (hearts.size.y + ScoreHud.GAP) * k
	if score != null:
		if score.size.x > 0.0:
			score_w = score.size.x * k
		if score.size.y > 0.0:
			score_h = score.size.y * k
		if score.position.y > 0.0:
			score_y = score.position.y
	var y := score_y + (score_h - hit) * 0.5
	var local := Vector2(hearts.position.x + score_w + GAP * k, y)
	var origin: Vector2 = layer.global_position + local
	return Rect2(origin, Vector2(hit, hit))