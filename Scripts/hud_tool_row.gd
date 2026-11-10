class_name HudToolRow
extends Node
## Places the round HUD controls in one row under the wood counter (#450).
##
## The row stays clear of the wood panel, so opening the minimap does not
## cover Plank, Tower, Wall, the map button or attack/interact.

const GAP := 2.0
const SIDE := 4.0


func _process(_delta: float) -> void:
	_layout()


func _layout() -> void:
	var layer := get_parent()
	if layer == null:
		return
	var controls: Array[Control] = []
	for node_name in ["RunButton", "BuildPicker", "MinimapButton", "ModeButton"]:
		var control := layer.get_node_or_null(node_name) as Control
		if control != null and control.visible:
			controls.append(control)
	if controls.is_empty():
		return
	var width := 0.0
	var height := 0.0
	var widths: Array[float] = []
	for control in controls:
		var need := control.get_combined_minimum_size()
		var w := maxf(control.size.x, need.x)
		var h := maxf(control.size.y, need.y)
		widths.append(w)
		width += w
		height = maxf(height, h)
	width += GAP * float(controls.size() - 1)
	var view := get_viewport().get_visible_rect().size
	var y := _under_wood(layer)
	var x := clampf((view.x - width) * 0.5, SIDE, maxf(SIDE, view.x - SIDE - width))
	var row := Rect2(x, y, width, height)
	row = _shift_clear(row, _menu_rect(layer))
	row = _shift_clear(row, _panel_rect(layer))
	x = row.position.x
	y = row.position.y
	for i in controls.size():
		var control: Control = controls[i]
		_pin(control)
		control.position = Vector2(roundf(x), roundf(y))
		control.z_index = 2
		x += widths[i] + GAP


func _under_wood(layer: Node) -> float:
	## Just under the wood counter. A tiny headless window inflates the
	## hearts' pixel scale; following that would drop the row onto the map.
	var wood := layer.get_node_or_null("ResourceHud") as Control
	if wood == null or wood.size.y <= 0.0:
		return SIDE
	var sy := minf(wood.scale.y, 2.0)
	return wood.position.y + wood.size.y * sy + GAP


func _menu_rect(layer: Node) -> Rect2:
	var menu := layer.get_node_or_null("InGameMenu/MenuButton") as Control
	if menu == null:
		return Rect2()
	return menu.get_global_rect()


func _panel_rect(layer: Node) -> Rect2:
	## The wood panel's rect even while it is closed, so the row does not sit
	## where the panel will open.
	var panel := layer.get_node_or_null("MinimapPanel") as Control
	if panel == null:
		return Rect2()
	return Rect2(panel.position, panel.size * panel.scale)


func _shift_clear(row: Rect2, block: Rect2) -> Rect2:
	if block.size == Vector2.ZERO or not row.intersects(block):
		return row
	var left := block.position.x - GAP - row.size.x
	if left >= SIDE:
		row.position.x = left
		return row
	row.position.y = block.end.y + GAP
	return row


func _pin(control: Control) -> void:
	if control.has_meta(&"hud_pinned"):
		return
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.set_meta(&"hud_pinned", true)
