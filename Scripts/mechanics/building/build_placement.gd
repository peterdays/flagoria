class_name BuildPlacement
extends RefCounted
## Build tool (#225 / #273 / #276, #480): Buildings opens a column of round
## Plank / Tower / Wall buttons. Cut is the tool when none is selected. H/V-snapped
## plank and wall drag, single-anchor tower preview,
## green/red preview and wood cost. Placement goes only through
## ConstructionPlacer (planks, towers and walls ask the host in multiplayer,
## #297 / #497 / #498). Preview green cells and cost match exactly what
## commit places and charges. Wall keeps a persistent tip while selected (#276).

enum Tool { CUT, PLANK, TOWER, WALL }

const VALID_TINT := Color(0.2, 0.85, 0.3, 0.42)
const INVALID_TINT := Color(0.92, 0.22, 0.18, 0.48)
const COST_COLOR := Color(0.98, 0.95, 0.88, 1.0)
const REASON_COLOR := Color(1.0, 0.75, 0.55, 1.0)
const PICKER_PATH := "/root/Flagoria/CanvasLayer1/BuildPicker"

const TOOL_ICONS := {
	Tool.CUT: preload("res://art/ui/ui_tool_cut.png"),
	Tool.PLANK: preload("res://art/ui/ui_tool_plank.png"),
	Tool.TOWER: preload("res://art/ui/ui_tool_tower.png"),
	Tool.WALL: preload("res://art/ui/ui_tool_wall.png"),
}
const TOOL_TIPS := {
	Tool.CUT: "Cut", Tool.PLANK: "Plank", Tool.TOWER: "Tower", Tool.WALL: "Wall",
}
const BUTTON_NAMES := {
	Tool.PLANK: "PlankButton", Tool.TOWER: "TowerButton", Tool.WALL: "WallButton",
}
const BUILDINGS_ICON := preload("res://assets/ui/hud/icon_buildings.png")
const _FootprintOrientation := preload("res://Scripts/mechanics/building/footprint_orientation.gd")
## Opaque tool art. Narrower than the disc so the circle and the gold ring show.
const COLUMN_ICON := 12
## Nothing stays hidden once its request exists. Plank (#297), Tower (#497)
## and Wall (#498) stay visible. An empty list hides nothing.
const MP_HIDDEN: Array = []

var tool := Tool.CUT
var cells: Array[Vector2i] = []  ## snapped run or tower footprint under the finger
var cell_ok: Array[bool] = []  ## parallel to cells: green iff commit will place
var cost := 0
var reasons: Array[String] = []
var cost_viewport := Vector2.ZERO  ## where the cost label sits (finger)

var _interaction: Interaction
var _placer: ConstructionPlacer
var _picker: Control
var _buildings: Button
var _list_open := false
var _buttons: Dictionary = {}  ## Tool -> Button
var _snap_from := Vector2i.ZERO
var _snap_to := Vector2i.ZERO
var _snap_valid := false
## Last placed wall cell while the Wall tool stays selected; cleared on leave.
var _wall_tip := Vector2i.ZERO
var _has_wall_tip := false
## Skip-cache extras: same drag cells can still go stale when wood, reach
## (player position) or the map change. Bumped on worldMap.ground_changed.
var _snap_wood := -1
var _snap_player_pos := Vector2(INF, INF)
var _snap_map_rev := -1
var _snap_rotation := -1
var _map_rev := 0
## Last multiplayer_on seen; Interaction polls and calls on_multiplayer_changed.
var _mp_was_on := false
var _rotate := BuildPlacementRotate.new()

var footprint_rotation: int:
	get:
		return _rotate.quarter_turns
	set(value):
		_rotate.quarter_turns = posmod(value, 4)


func setup(interaction: Interaction) -> void:
	_interaction = interaction
	_placer = ConstructionPlacer.new(interaction.world_map)
	if interaction.world_map != null and interaction.world_map.has_signal("ground_changed"):
		interaction.world_map.ground_changed.connect(_on_ground_changed)
	_ensure_picker()
	set_tool(Tool.CUT)
	_mp_was_on = Interaction.multiplayer_on(interaction.multiplayer)
	_refresh_picker_visible()


static func is_footprint_tool(value: Tool) -> bool:
	return value == Tool.TOWER


func set_tool(value: Tool) -> void:
	if tool == Tool.WALL and value != Tool.WALL:
		_has_wall_tip = false
	tool = value
	_rotate.reset()
	clear_preview()
	for t in _buttons:
		var button: Button = _buttons[t]
		button.set_pressed_no_signal(t == tool)
	if value != Tool.CUT:
		_list_open = false
		if _buildings != null:
			_buildings.set_pressed_no_signal(false)
	_refresh_picker_visible()


func clear_preview() -> void:
	cells.clear()
	cell_ok.clear()
	cost = 0
	reasons.clear()
	cost_viewport = Vector2.ZERO
	_snap_valid = false
	_snap_wood = -1
	_snap_player_pos = Vector2(INF, INF)
	_snap_map_rev = -1
	_snap_rotation = -1
	_refresh_rotate_visible()


func rotate_footprint() -> void:
	## Turn the footprint preview 90° clockwise (#493).
	if not is_footprint_tool(tool):
		return
	_rotate.step_cw()
	_snap_valid = false
	if cost_viewport != Vector2.ZERO:
		var inventory := _inventory()
		if inventory != null:
			update_preview(cost_viewport, cost_viewport)


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
	## the snapped cells, wood count, player position and map revision are
	## unchanged (#383).
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
	if is_footprint_tool(tool) and _snap_valid and cells.size() > 0:
		var mark: Vector2 = ci.to_local(_interaction.cell_center(_snap_from))
		_FootprintOrientation.draw_at(ci, mark, _rotate.quarter_turns)
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
	else:
		_refresh_rotate_visible()
	_mp_was_on = Interaction.multiplayer_on(_interaction.multiplayer) if _interaction else false
	_refresh_picker_visible()


func on_multiplayer_changed(mp_on: bool) -> void:
	## Called from Interaction when multiplayer_on flips (peer joins while the
	## host is already in interact + Plank, etc.).
	if mp_on == _mp_was_on:
		return
	_mp_was_on = mp_on
	_refresh_picker_visible()


func _update_plank_preview(start_viewport: Vector2, end_viewport: Vector2, inventory: Inventory) -> void:
	var from_cell := _cell_at(start_viewport)
	var to_cell := _cell_at(end_viewport)
	if _preview_inputs_unchanged(from_cell, to_cell, inventory):
		return
	_remember_preview_inputs(from_cell, to_cell, inventory)
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
	if _preview_inputs_unchanged(anchor, anchor, inventory):
		return
	_remember_preview_inputs(anchor, anchor, inventory)
	cells = _placer.tower_footprint(anchor, _rotate.quarter_turns)
	cell_ok.clear()
	var one: Array[Vector2i] = [anchor]
	var placeable := false
	reasons.clear()
	if cells.is_empty():
		reasons.append(ConstructionPlacer.EMPTY_CELLS)
	elif not _interaction.in_reach(anchor):
		var why := _placer.can_place(BuildCosts.TOWER, one, inventory, _rotate.quarter_turns)
		if why.is_empty():
			reasons.append("out of reach")
		else:
			reasons = why
	else:
		var why := _placer.can_place(BuildCosts.TOWER, one, inventory, _rotate.quarter_turns)
		placeable = why.is_empty()
		if not placeable:
			reasons = why
	for _i in cells.size():
		cell_ok.append(placeable)
	cost = _placer.cost(BuildCosts.TOWER, one) if placeable else 0
	_position_rotate_button(end_viewport)


func _commit_plank(inventory: Inventory) -> bool:
	var in_reach: Array[Vector2i] = []
	for cell in cells:
		if _interaction.in_reach(cell):
			in_reach.append(cell)
	var placeable := longest_placeable(in_reach, inventory)
	# Route through Interaction so multiplayer asks the host (#297). Offline
	# and host-alone still spend and write through ConstructionPlacer.place.
	return not placeable.is_empty() and _interaction.place_planks(placeable)


func _commit_tower(inventory: Inventory) -> bool:
	## Place on the preview's anchor (centre of the footprint's first cell set
	## via _snap_from). Green preview means can_place already passed.
	var anchor := _snap_from
	if not _interaction.in_reach(anchor):
		return false
	var one: Array[Vector2i] = [anchor]
	return _placer.place(BuildCosts.TOWER, one, inventory, _rotate.quarter_turns)


func _on_buildings_toggled(on: bool) -> void:
	if HudLayoutVisual.blocks_hud_actions():
		_buildings.set_pressed_no_signal(false); return
	_list_open = on
	_refresh_picker_visible()


func _ensure_picker() -> void:
	var hud := _interaction.get_node_or_null("/root/Flagoria/CanvasLayer1") as CanvasLayer
	if hud == null:
		return
	var theme: Theme = load("res://art/ui/main_menu_theme.tres")
	_buildings = hud.get_node_or_null("BuildingsButton") as Button
	if _buildings == null:
		_buildings = Button.new()
		_buildings.name = "BuildingsButton"
		_buildings.toggle_mode = true
		_buildings.theme = theme
		_buildings.tooltip_text = "Buildings"
		_buildings.icon = BUILDINGS_ICON
		RoundHudStyle.apply(_buildings)
		_buildings.toggled.connect(_on_buildings_toggled)
		hud.add_child(_buildings)
	_picker = hud.get_node_or_null("BuildPicker") as Control
	if _picker == null:
		_picker = Control.new()
		_picker.name = "BuildPicker"
		_picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_picker)
	for child in _picker.get_children():
		child.queue_free()
	_buttons.clear()
	for t in [Tool.PLANK, Tool.TOWER, Tool.WALL]:
		var button := Button.new()
		button.name = BUTTON_NAMES[t]
		button.toggle_mode = true
		button.theme = theme
		button.icon = TOOL_ICONS[t] as Texture2D
		button.tooltip_text = TOOL_TIPS[t] as String
		RoundHudStyle.apply(button, RoundHudStyle.HIT, RoundHudStyle.SIZE, COLUMN_ICON)
		var captured: Tool = t
		button.pressed.connect(func() -> void: set_tool(captured))
		_picker.add_child(button)
		_buttons[t] = button
	_picker.reset_size()
	_rotate.ensure(hud, theme)
	_rotate.connect_pressed(rotate_footprint)


func _refresh_picker_visible() -> void:
	## Column stays hidden until Buildings is open. Plank, Tower and Wall
	## stay once the list is open (#498).
	if _picker == null or _interaction == null:
		return
	var mp := Interaction.multiplayer_on(_interaction.multiplayer)
	if mp and tool in MP_HIDDEN:
		set_tool(Tool.CUT)
		return
	_picker.visible = true
	for t in _buttons:
		(_buttons[t] as Button).visible = _list_open and not (mp and t in MP_HIDDEN)



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
	if _preview_inputs_unchanged(from_cell, to_cell, inventory):
		return
	_remember_preview_inputs(from_cell, to_cell, inventory)
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


func _on_ground_changed(_cells: Rect2i) -> void:
	_map_rev += 1


func _preview_inputs_unchanged(from_cell: Vector2i, to_cell: Vector2i, inventory: Inventory) -> bool:
	if not _snap_valid or from_cell != _snap_from or to_cell != _snap_to:
		return false
	if _rotate.quarter_turns != _snap_rotation:
		return false
	if inventory.count_of(Inventory.WOOD) != _snap_wood:
		return false
	if _map_rev != _snap_map_rev:
		return false
	var pos := _interaction.player.global_position if _interaction.player else Vector2(INF, INF)
	return pos == _snap_player_pos


func _remember_preview_inputs(from_cell: Vector2i, to_cell: Vector2i, inventory: Inventory) -> void:
	_snap_from = from_cell
	_snap_to = to_cell
	_snap_valid = true
	_snap_rotation = _rotate.quarter_turns
	_snap_wood = inventory.count_of(Inventory.WOOD)
	_snap_player_pos = _interaction.player.global_position if _interaction.player else Vector2(INF, INF)
	_snap_map_rev = _map_rev


func _refresh_rotate_visible() -> void:
	if _interaction == null:
		return
	var show := _interaction.mode == Interaction.Mode.INTERACT and is_footprint_tool(tool) \
			and not cells.is_empty()
	_rotate.set_visible(show)


func _position_rotate_button(viewport_pos: Vector2) -> void:
	_refresh_rotate_visible()
	_rotate.position_at(viewport_pos)
