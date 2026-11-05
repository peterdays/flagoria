class_name BuildPlacement
extends RefCounted
## Interact-mode build tool (#225 / #273): Cut / Plank / Tower picker, H/V-
## snapped plank drag, single-anchor tower preview, green/red preview and wood
## cost. Placement goes only through ConstructionPlacer. Preview green cells
## and cost match exactly what commit places and charges.

enum Tool { CUT, PLANK, TOWER }

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
}
const TOOL_TIPS := {Tool.CUT: "Cut", Tool.PLANK: "Plank", Tool.TOWER: "Tower"}
## Tools refused while multiplayer is on (same gate as ConstructionPlacer).
const MP_HIDDEN := [Tool.PLANK, Tool.TOWER]

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


func setup(interaction: Interaction) -> void:
	_interaction = interaction
	_placer = ConstructionPlacer.new(interaction.world_map)
	_ensure_picker()
	set_tool(Tool.CUT)
	_refresh_picker_visible()


func set_tool(value: Tool) -> void:
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
	clear_preview()
	return ok


func draw_preview(ci: CanvasItem) -> void:
	## Green/red cell tints, wood cost and refusal reason near the finger.
	if tool == Tool.CUT or cells.is_empty() or _interaction == null:
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
	_picker.offset_left = -110.0
	_picker.offset_top = 4.0
	_picker.offset_right = -48.0
	_picker.offset_bottom = 22.0
	_picker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in _picker.get_children():
		child.queue_free()
	_buttons.clear()
	var theme: Theme = load("res://art/ui/main_menu_theme.tres")
	for t in [Tool.CUT, Tool.PLANK, Tool.TOWER]:
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


func _inventory() -> Inventory:
	return _interaction.get_node_or_null(Interaction.INVENTORY_PATH) as Inventory


func _cell_at(viewport_pos: Vector2) -> Vector2i:
	var world: Vector2 = _interaction.to_world(viewport_pos)
	return _interaction.world_map.local_to_map(_interaction.world_map.to_local(world))


func _cell_looks_placeable(cell: Vector2i) -> bool:
	## Cheap per-cell check kept for callers; tint now follows longest_placeable.
	return not _interaction.world_map.has_bridge(cell) \
			and _interaction.world_map.predict_cell(cell)[0] == TileCatalog.WATER
