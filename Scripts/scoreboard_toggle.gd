class_name ScoreboardToggle
extends Button
## Opens the scoreboard beside the score counter (#509).

const HIT := 20.0
const GAP := 2.0


func _ready() -> void:
	name = "ScoreboardToggle"
	text = "\u2261"
	tooltip_text = "Scores"
	focus_mode = FOCUS_NONE
	texture_filter = TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(HIT, HIT)
	theme = load("res://art/ui/main_menu_theme.tres")
	pressed.connect(_on_pressed)
	get_viewport().size_changed.connect(_relayout)


func _process(_delta: float) -> void:
	_relayout()


func _relayout() -> void:
	var score := get_node_or_null("../ScoreHud") as Control
	if score == null:
		return
	scale = score.scale
	position = score.position + Vector2(score.size.x * score.scale.x + GAP * score.scale.x,
			(score.size.y * score.scale.y - HIT * score.scale.y) * 0.5)


func _on_pressed() -> void:
	if HudLayoutVisual.blocks_hud_actions():
		set_pressed_no_signal(false)
		return
	var panel := get_node_or_null("../ScoreboardPanel") as ScoreboardPanel
	if panel != null:
		panel.toggle()