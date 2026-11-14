class_name BuildPlacementRotate
extends RefCounted
## Round rotate control for footprint placement previews (#493).

const ROTATE_ICON := preload("res://art/ui/ui_tool_rotate.png")

var quarter_turns := 0
var _button: Button


func reset() -> void:
	quarter_turns = 0


func step_cw() -> void:
	quarter_turns = posmod(quarter_turns + 1, 4)


func ensure(hud: CanvasLayer, theme: Theme) -> Button:
	if _button != null:
		return _button
	_button = hud.get_node_or_null("FootprintRotateButton") as Button
	if _button == null:
		_button = Button.new()
		_button.name = "FootprintRotateButton"
		_button.theme = theme
		_button.icon = ROTATE_ICON
		_button.tooltip_text = "Rotate"
		RoundHudStyle.apply(_button)
		_button.mouse_filter = Control.MOUSE_FILTER_STOP
		hud.add_child(_button)
	_button.visible = false
	return _button


func connect_pressed(callable: Callable) -> void:
	if _button != null and not _button.pressed.is_connected(callable):
		_button.pressed.connect(callable)


func set_visible(show: bool) -> void:
	if _button != null:
		_button.visible = show


func position_at(viewport_pos: Vector2) -> void:
	if _button == null or not _button.visible:
		return
	var offset := Vector2(-RoundHudStyle.HIT - 6.0, -RoundHudStyle.HIT * 0.5)
	_button.position = viewport_pos + offset