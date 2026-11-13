class_name HudToolRow
extends Node
## Places the top-right half-moon and the Run button (#480).
##
## Buildings, Map and Mode sit on a quarter arc in the top-right corner,
## clear of the menu button. The wood panel sits left of that arc so an open
## map never covers a button. The build tools stack in a column under
## Buildings while that list is open. Run sits beside the attack button.

const GAP := 2.0
const SIDE := 4.0
const ARC_RADIUS := 40.0
const ARC_START := -80.0  ## degrees, y down; Mode sits up-right on the circle
const ARC_STEP := 48.0


func _process(_delta: float) -> void:
	_layout()


func _layout() -> void:
	var layer := get_parent()
	if layer == null:
		return
	var layout := get_node_or_null("/root/HudLayout")
	if layout != null and layout.layout_active():
		layout.apply(layer)
		return
	_restore_touch_defaults(layer)
	var buildings := layer.get_node_or_null("BuildingsButton") as Control
	var map_button := layer.get_node_or_null("MinimapButton") as Control
	var mode := layer.get_node_or_null("ModeButton") as Control
	var view := get_viewport().get_visible_rect().size
	if mode != null:
		var menu := _menu_rect(layer)
		var right := view.x - SIDE
		if menu.size != Vector2.ZERO:
			right = minf(right, menu.position.x - GAP)
		var mode_center := Vector2(right - RoundHudStyle.HIT * 0.5, SIDE + RoundHudStyle.HIT * 0.5)
		# Corner first, then along the arc, so Buildings is the low end and
		# its column can drop without crossing Map or Mode.
		var ordered: Array[Control] = [mode]
		if map_button != null:
			ordered.append(map_button)
		if buildings != null:
			ordered.append(buildings)
		for i in ordered.size():
			var control: Control = ordered[i]
			_pin(control)
			var center := _arc_center(i, mode_center)
			var size := _size_of(control)
			control.position = Vector2(
					roundf(center.x - size.x * 0.5), roundf(center.y - size.y * 0.5))
			control.z_index = 2
	_place_buildings(layer, buildings)
	_place_panel(layer, view)
	_place_run(layer)


func _arc_center(index: int, mode_center: Vector2) -> Vector2:
	var start := deg_to_rad(ARC_START)
	var angle := deg_to_rad(ARC_START - float(index) * ARC_STEP)
	var origin := mode_center - Vector2(cos(start), sin(start)) * ARC_RADIUS
	return origin + Vector2(cos(angle), sin(angle)) * ARC_RADIUS


func _size_of(control: Control) -> Vector2:
	var need := control.get_combined_minimum_size()
	return Vector2(maxf(control.size.x, need.x), maxf(control.size.y, need.y))


func _place_buildings(layer: Node, buildings: Control) -> void:
	if buildings == null:
		return
	var picker := layer.get_node_or_null("BuildPicker") as Control
	if picker == null:
		return
	_pin(picker)
	picker.position = Vector2.ZERO
	picker.z_index = 2
	var top := buildings.position.y + _size_of(buildings).y + GAP
	var x := buildings.position.x
	var y := top
	for child in picker.get_children():
		var button := child as Control
		if button == null or button.is_queued_for_deletion() or not button.visible:
			continue
		_pin(button)
		var size := _size_of(button)
		button.position = Vector2(roundf(x), roundf(y))
		button.z_index = 3
		y += size.y + GAP


func _place_panel(layer: Node, view: Vector2) -> void:
	## Left of every arc button, and of the open column. High enough to stay
	## off the attack button, and below the wood counter when they would meet.
	var panel := layer.get_node_or_null("MinimapPanel") as Control
	if panel == null or panel.size.x <= 0.0:
		return
	var width := panel.size.x * panel.scale.x
	var height := panel.size.y * panel.scale.y
	var arc_left := view.x
	for node_name in ["ModeButton", "MinimapButton", "BuildingsButton"]:
		arc_left = minf(arc_left, _left_of(layer.get_node_or_null(node_name) as Control))
	var picker := layer.get_node_or_null("BuildPicker") as Control
	if picker != null:
		for child in picker.get_children():
			var column := child as Control
			if column != null and column.visible and not column.is_queued_for_deletion():
				arc_left = minf(arc_left, _left_of(column))
	var right := minf(view.x - MinimapPanel.MARGIN * panel.scale.x, arc_left - GAP)
	var y := maxf(MinimapPanel.TOP * panel.scale.y, 23.0)
	var limit := view.y - SIDE
	var attack := layer.get_node_or_null("TouchScreenButton") as TouchScreenButton
	if attack != null and attack.texture_normal != null:
		limit = attack.position.y - GAP
	if y + height > limit:
		y = limit - height
	var x := right - width
	if x < SIDE:
		x = SIDE
	panel.position = Vector2(roundf(x), roundf(y))
	var wood := layer.get_node_or_null("ResourceHud") as Control
	if wood != null and wood.visible and panel.get_global_rect().intersects(wood.get_global_rect()):
		var dropped := wood.get_global_rect().end.y + GAP
		if dropped + height <= limit:
			panel.position.y = roundf(dropped)


func _left_of(control: Control) -> float:
	if control == null:
		return INF
	var rect := control.get_global_rect()
	if rect.size.x <= 0.0:
		return INF
	return rect.position.x


func _place_run(layer: Node) -> void:
	var run := layer.get_node_or_null("RunButton") as Control
	var attack := layer.get_node_or_null("TouchScreenButton") as TouchScreenButton
	if run == null or attack == null or attack.texture_normal == null:
		return
	_pin(run)
	var attack_size := attack.texture_normal.get_size() * attack.scale
	var run_size := _size_of(run)
	# Left of the attack button, vertically centred, within a thumb's rock.
	var x := attack.position.x - GAP - run_size.x
	var y := attack.position.y + (attack_size.y - run_size.y) * 0.5
	if x < SIDE:
		x = attack.position.x + attack_size.x - run_size.x
		y = attack.position.y - GAP - run_size.y
	run.position = Vector2(roundf(x), roundf(y))
	run.z_index = 2


func _menu_rect(layer: Node) -> Rect2:
	var menu := layer.get_node_or_null("InGameMenu/MenuButton") as Control
	if menu == null:
		return Rect2()
	return menu.get_global_rect()


func _restore_touch_defaults(layer: Node) -> void:
	var attack := layer.get_node_or_null("TouchScreenButton") as TouchScreenButton
	if attack != null:
		attack.position = Vector2(378, 182)
		attack.scale = Vector2.ONE
		if attack.shape is CircleShape2D:
			(attack.shape as CircleShape2D).radius = 24.0
	var stick := layer.get_node_or_null("player_joystick") as Node2D
	if stick != null:
		stick.position = Vector2(77, 201)
		stick.scale = Vector2.ONE


func place_panel_only(layer: Node) -> void:
	## Minimap placement when touch controls use a saved layout.
	_place_panel(layer, layer.get_viewport().get_visible_rect().size)


func _pin(control: Control) -> void:
	if control.has_meta(&"hud_pinned"):
		return
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.set_meta(&"hud_pinned", true)
