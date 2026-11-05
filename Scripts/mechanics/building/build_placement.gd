class_name BuildPlacement
extends RefCounted
## Interact-mode build tool (#225 / #273 / #276): Cut / Plank / Tower / Wall
## picker, H/V-snapped plank and wall drag, single-anchor tower preview,
## green/red preview and wood cost. Placement goes only through
## ConstructionPlacer. Preview green cells and cost match exactly what commit
## places and charges. Wall keeps a persistent tip while selected (#276).

enum Tool { CUT, PLANK, TOWER, WALL }

const VALID_TINT := Color(0.2, 0.85, 0.3, 0.42)
const INVALID_TINT := Color(0.92, 0.22, 0.18, 0.48)
const COST_COLOR := Color(0.98, 0.95, 0.88, 1.0)
const REASON_COLOR := Color(1.0, 0.75, 0.55, 1.0)
const PICKER_PATH := "/root/Flagoria/CanvasLayer1/BuildPicker"
const InGameMenuScript := preload("res://Scripts/ingame_menu.gd")

const TOOL_ICONS := {
	Tool.CUT: preload("res://art/ui/ui_tool_cut.png"),
	Tool.PLANK: preload("res://art/ui/ui_tool_plank.png"),
	Tool.TOWER: preload("res://art/ui/ui_tool_tower.png"),
	Tool.WALL: preload("res://art/ui/ui_tool_wall.png"),
}
const TOOL_TIPS := {
	Tool.CUT: "Cut", Tool.PLANK: "Plank", Tool.TOWER: "Tower", Tool.WALL: "Wall",
}
## Tools refused while multiplayer is on (same gate as ConstructionPlacer).
const MP_HIDDEN := [Tool.PLANK, Tool.TOWER, Tool.WALL]

var tool := Tool.CUT
var cells: Array[Vector2i] = []  ## snapped run or tower footprint under the finger
var cell_ok: Array[bool] = []  ## parallel to cells: green iff commit will place
var cost := 0
var reasons: Array[String] = []
var cost_viewport := Vector2.ZERO  ## where the cost label sits (finger)

var _interaction: Interaction
var _placer: ConstructionPlacer
var _picker: HBoxContainer
var _buttons: Dictionary = {}  ## Tool -> Button
var _snap_from := Vector2i.ZERO
var _snap_to := Vector2i.ZERO
var _snap_valid := false
## Last placed wall cell while the Wall tool stays selected; cleared on leave.
var _wall_tip := Vector2i.ZERO
var _has_wall_tip := false


func setup(interaction: Interaction) -> void:
	_interaction = interaction
	_placer = ConstructionPlacer.new(interaction.world_map)
	_ensure_picker()
	set_tool(Tool.CUT)
	_refresh_picker_visible()


func set_tool(value: Tool) -> void:
	if tool == Tool.WALL and value != Tool.WALL:
		_has_wall_tip = false
	tool = value
	clear_preview()
	for t in _buttons:
		var button: Button = _buttons[t]
		button.set_pressed_no_signal(t == tool)


func clear_preview() -> void:
	cells.clear()
	cell_ok.clear()
	cost = 0
	reasons.clear()
	cost_viewport = Vector2.ZERO
	_snap_valid = false


static func snap_run(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	## Contiguous horizontal or vertical cells from `from_cell` to `to_cell`,
	## snapping to the dominant axis (ties go horizontal).
	var delta := to_cell - from_cell
	var horizontal := absi(delta.x) >= absi(delta.y)
	var end := Vector2i(to_cell.x, from_cell.y) if horizontal else Vector2i(from_cell.x, to_cell.y)
	var step := Vector2i(
		0 if end.x == from_cell.x else (1 if end.x > from_cell.x else -1),
		0 if end.y == from_cell.y else (1 if end.y > from_cell.y else -1),
	)
	var out: Array[Vector2i] = [from_cell]
	var cur := from_cell
	while cur != end:
		cur += step
		out.append(cur)
	return out


func update_preview(start_viewport: Vector2, end_viewport: Vector2) -> void:
	## Recompute the preview for the active tool. Plank: snapped run, green =
	## longest placeable prefix. Tower: footprint of the anchor under the
	## finger, all green iff commit will place, else all red. Skips work when
	## the cell under the finger has not moved.
	if tool == Tool.CUT or _interaction == null or _interaction.player == null:
		clear_preview()
		return
	var inventory := _inventory()
	if inventory == null:
		clear_preview()
		return
	cost_viewport = end_viewport
	if tool == Tool.TOWER:
		_update_tower_preview(end_viewport, inventory)
		return
	if tool == Tool.WALL:
		_update_wall_preview(start_viewport, end_viewport, inventory)
		return
	_update_plank_preview(start_viewport, end_viewport, inventory)


func longest_placeable(run: Array[Vector2i], inventory: Inventory) -> Array[Vector2i]:
	## Longest prefix of `run` ConstructionPlacer will accept (no gaps).
	for n in range(run.size(), 0, -1):
		var prefix: Array[Vector2i] = []
		for i in n:
			prefix.append(run[i])
		if _placer.can_place(BuildCosts.PLANK, prefix, inventory).is_empty():
			return prefix
	return []


func commit() -> bool:
	## Place what the current preview greens; false when none.
	if tool == Tool.CUT or cells.is_empty():
		clear_preview()
		return false
	var inventory := _inventory()
	if inventory == null:
		clear_preview()
		return false
	var ok := false
	if tool == Tool.TOWER:
		ok = _commit_tower(inventory)
	elif tool == Tool.PLANK:
		ok = _commit_plank(inventory)
	elif tool == Tool.WALL:
		if "not adjacent" in reasons:
			clear_preview()
			return false
		ok = _commit_wall(inventory)
	clear_preview()
	return ok


func draw_preview(ci: CanvasItem) -> void:
	## Green/red cell tints, wood cost and refusal reason near the finger.
	## A wall gap / diagonal leaves cells empty but still shows the reason (#276).
	if tool == Tool.CUT or _interaction == null:
		return
	if cells.is_empty() and reasons.is_empty():
		return
	var map: TileMap = _interaction.world_map
	var half: Vector2 = Vector2(map.tile_set.tile_size) * map.global_scale / 2.0
	for i in cells.size():
		var center: Vector2 = ci.to_local(_interaction.cell_center(cells[i]))
		var rect := Rect2(center - half, half * 2.0)
		ci.draw_rect(rect, VALID_TINT if cell_ok[i] else INVALID_TINT)
	var anchor: Vector2 = ci.to_local(_interaction.to_world(cost_viewport)) + Vector2(8, -12)
	var font: Font = ThemeDB.fallback_font
	var font_size := 10
	if cost > 0 or not reasons.is_empty():
		var label := "%d wood" % cost if cost > 0 else ""
		if not reasons.is_empty():
			label = ("%s — %s" % [label, ", ".join(PackedStringArray(reasons))]).strip_edges()
			if label.begins_with("—"):
				label = label.substr(2).strip_edges()
		ci.draw_string(font, anchor, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COST_COLOR \
				if reasons.is_empty() else REASON_COLOR)


func on_mode_changed(mode: Interaction.Mode) -> void:
	if mode != Interaction.Mode.INTERACT:
		set_tool(Tool.CUT)
	_refresh_picker_visible()


func _update_plank_preview(start_viewport: Vector2, end_viewport: Vector2, inventory: Inventory) -> void:
	var from_cell := _cell_at(start_viewport)
	var to_cell := _cell_at(end_viewport)
	if _snap_valid and from_cell == _snap_from and to_cell == _snap_to:
		return
	_snap_from = from_cell
	_snap_to = to_cell
	_snap_valid = true
	cells = snap_run(from_cell, to_cell)
	var in_reach: Array[Vector2i] = []
	for cell in cells:
		if _interaction.in_reach(cell):
			in_reach.append(cell)
	var placeable := longest_placeable(in_reach, inventory)
	var placeable_set := {}
	for cell in placeable:
		placeable_set[cell] = true
	cell_ok.clear()
	for cell in cells:
		cell_ok.append(placeable_set.has(cell))
	if placeable.is_empty():
		cost = 0
		reasons = _placer.can_place(BuildCosts.PLANK, in_reach, inventory) if not in_reach.is_empty() \
				else [ConstructionPlacer.EMPTY_CELLS]
	else:
		cost = _placer.cost(BuildCosts.PLANK, placeable)
		reasons = []


func _update_tower_preview(end_viewport: Vector2, inventory: Inventory) -> void:
	## Footprint of the anchor under the finger. All green and cost 10 when
	## commit will place; all red with reasons otherwise.
	var anchor := _cell_at(end_viewport)
	if _snap_valid and anchor == _snap_from:
		return
	_snap_from = anchor
	_snap_to = anchor
	_snap_valid = true
	cells = _placer.tower_footprint(anchor)
	cell_ok.clear()
	var one: Array[Vector2i] = [anchor]
	var placeable := false
	reasons.clear()
	if cells.is_empty():
		reasons.append(ConstructionPlacer.EMPTY_CELLS)
	elif not _interaction.in_reach(anchor):
		var why := _placer.can_place(BuildCosts.TOWER, one, inventory)
		if why.is_empty():
			reasons.append(ConstructionPlacer.OCCUPIED)
		else:
			reasons = why
	else:
		var why := _placer.can_place(BuildCosts.TOWER, one, inventory)
		placeable = why.is_empty()
		if not placeable:
			reasons = why
	for _i in cells.size():
		cell_ok.append(placeable)
	cost = _placer.cost(BuildCosts.TOWER, one) if placeable else 0


func _commit_plank(inventory: Inventory) -> bool:
	var in_reach: Array[Vector2i] = []
	for cell in cells:
		if _interaction.in_reach(cell):
			in_reach.append(cell)
	var placeable := longest_placeable(in_reach, inventory)
	return not placeable.is_empty() and _placer.place(BuildCosts.PLANK, placeable, inventory)


func _commit_tower(inventory: Inventory) -> bool:
	## Place on the preview's anchor (centre of the footprint's first cell set
	## via _snap_from). Green preview means can_place already passed.
	var anchor := _snap_from
	if not _interaction.in_reach(anchor):
		return false
	var one: Array[Vector2i] = [anchor]
	return _placer.place(BuildCosts.TOWER, one, inventory)


func _ensure_picker() -> void:
	var hud := _interaction.get_node_or_null("/root/Flagoria/CanvasLayer1") as CanvasLayer
	if hud == null:
		return
	_picker = hud.get_node_or_null("BuildPicker") as HBoxContainer
	if _picker == null:
		_picker = HBoxContainer.new()
		_picker.name = "BuildPicker"
		_picker.add_theme_constant_override("separation", 2)
		hud.add_child(_picker)
	_picker.anchor_left = 1.0
	_picker.anchor_right = 1.0
	_picker.offset_left = -130.0
	_picker.offset_top = 4.0
	_picker.offset_right = -48.0
	_picker.offset_bottom = 22.0
	_picker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in _picker.get_children():
		child.queue_free()
	_buttons.clear()
	var theme: Theme = load("res://art/ui/main_menu_theme.tres")
	for t in [Tool.CUT, Tool.PLANK, Tool.TOWER, Tool.WALL]:
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.icon = TOOL_ICONS[t] as Texture2D
		button.tooltip_text = TOOL_TIPS[t] as String
		button.theme = theme
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.custom_minimum_size = Vector2(18, 18)
		InGameMenuScript.fit_icon_button(button)
		var captured: Tool = t
		button.pressed.connect(func() -> void: set_tool(captured))
		_picker.add_child(button)
		_buttons[t] = button


func _refresh_picker_visible() -> void:
	if _picker == null or _interaction == null:
		return
	_picker.visible = _interaction.mode == Interaction.Mode.INTERACT
	var mp := Interaction.multiplayer_on(_interaction.multiplayer)
	for t in MP_HIDDEN:
		if _buttons.has(t):
			(_buttons[t] as Button).visible = not mp
	if mp and tool in MP_HIDDEN:
		set_tool(Tool.CUT)



func wall_segment(tip: Vector2i, has_tip: bool, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	## Cells the Wall tool would try to place for this gesture. First placement
	## (no tip): the tapped cell, or an H/V snap of the drag — ConstructionPlacer
	## still requires that cell to 4-touch a tower, castle or wall. With a tip:
	## a single 4-neighbour on tap, or an H/V run that starts on the neighbour
	## of the tip toward the finger. Empty when the gesture is a diagonal step
	## off the tip or does not touch it (gap).
	var empty: Array[Vector2i] = []
	if not has_tip:
		if from_cell == to_cell:
			var one: Array[Vector2i] = [to_cell]
			return one
		return snap_run(from_cell, to_cell)
	var delta := to_cell - tip
	if delta == Vector2i.ZERO:
		return empty
	var neighbours := {
		tip + Vector2i.LEFT: true, tip + Vector2i.RIGHT: true,
		tip + Vector2i.UP: true, tip + Vector2i.DOWN: true,
	}
	if from_cell == to_cell:
		if not neighbours.has(to_cell):
			return empty
		var adj: Array[Vector2i] = [to_cell]
		return adj
	var horizontal := absi(delta.x) >= absi(delta.y)
	if horizontal and delta.x == 0:
		return empty
	if not horizontal and delta.y == 0:
		return empty
	# Diagonal-only off the tip (both axes non-zero and equal length intent):
	# snap still yields a straight run, but the first step must 4-touch tip.
	var step := Vector2i(
		(1 if delta.x > 0 else -1) if horizontal else 0,
		0 if horizontal else (1 if delta.y > 0 else -1),
	)
	var start := tip + step
	var end := Vector2i(to_cell.x, tip.y) if horizontal else Vector2i(tip.x, to_cell.y)
	if start == tip:
		return empty
	return snap_run(start, end)


func _update_wall_preview(start_viewport: Vector2, end_viewport: Vector2, inventory: Inventory) -> void:
	var from_cell := _cell_at(start_viewport)
	var to_cell := _cell_at(end_viewport)
	if _snap_valid and from_cell == _snap_from and to_cell == _snap_to:
		return
	_snap_from = from_cell
	_snap_to = to_cell
	_snap_valid = true
	var run := wall_segment(_wall_tip, _has_wall_tip, from_cell, to_cell)
	cells = run
	cell_ok.clear()
	reasons.clear()
	if run.is_empty():
		cost = 0
		reasons.clear()
		if _has_wall_tip:
			reasons.append("not adjacent")
			# Show the refused finger cell in red so the gap / diagonal is
			# visible even when wall_segment returns no cells.
			var refused: Array[Vector2i] = [to_cell]
			var refused_ok: Array[bool] = [false]
			cells = refused
			cell_ok = refused_ok
		else:
			reasons.append(ConstructionPlacer.EMPTY_CELLS)
		return
	var in_reach: Array[Vector2i] = []
	for cell in run:
		if _interaction.in_reach(cell):
			in_reach.append(cell)
	# Green == commit: whole in-reach prefix the placer accepts, else all red.
	var placeable: Array[Vector2i] = []
	if not in_reach.is_empty() and _placer.can_place(BuildCosts.WALL_BLOCK, in_reach, inventory).is_empty():
		placeable = in_reach
	var placeable_set := {}
	for cell in placeable:
		placeable_set[cell] = true
	for cell in cells:
		cell_ok.append(placeable_set.has(cell))
	if placeable.is_empty():
		cost = 0
		reasons.clear()
		if in_reach.is_empty():
			reasons.append(ConstructionPlacer.EMPTY_CELLS)
		else:
			reasons = _placer.can_place(BuildCosts.WALL_BLOCK, in_reach, inventory)
	else:
		cost = _placer.cost(BuildCosts.WALL_BLOCK, placeable)
		reasons.clear()


func _commit_wall(inventory: Inventory) -> bool:
	var in_reach: Array[Vector2i] = []
	for cell in cells:
		if _interaction.in_reach(cell):
			in_reach.append(cell)
	if in_reach.is_empty():
		return false
	if not _placer.can_place(BuildCosts.WALL_BLOCK, in_reach, inventory).is_empty():
		return false
	if not _placer.place(BuildCosts.WALL_BLOCK, in_reach, inventory):
		return false
	_wall_tip = in_reach[in_reach.size() - 1]
	_has_wall_tip = true
	return true


func _inventory() -> Inventory:
	return _interaction.get_node_or_null(Interaction.INVENTORY_PATH) as Inventory


func _cell_at(viewport_pos: Vector2) -> Vector2i:
	var world: Vector2 = _interaction.to_world(viewport_pos)
	return _interaction.world_map.local_to_map(_interaction.world_map.to_local(world))


func _cell_looks_placeable(cell: Vector2i) -> bool:
	## Cheap per-cell check kept for callers; tint now follows longest_placeable.
	return not _interaction.world_map.has_bridge(cell) \
			and _interaction.world_map.predict_cell(cell)[0] == TileCatalog.WATER
