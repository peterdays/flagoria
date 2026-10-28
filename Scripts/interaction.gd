class_name Interaction
extends Node2D
## Combat or interact mode for the local player, switched with the HUD mode
## button. Combat is the default and leaves the map to the attack controls.
## In interact mode a tap on the map cuts the nearest tree on or next to the
## tapped cell, and a drag selects a range: when the finger lifts, every tree
## in the range that is within REACH of the player is cut. A cut tree leaves
## a stump and gives WOOD_PER_TREE wood. Mouse clicks and drags count as
## touches (pointing/emulate_touch_from_mouse). Touches that start on a HUD
## control, and two-finger pinches, select nothing. Cuts are local to this
## game: they are not synced to other players.

signal mode_changed(mode: Mode)

enum Mode { COMBAT, INTERACT }

const REACH := 80.0  ## world px from the player to a tree it can cut
const DRAG_START := 6.0  ## viewport px a touch moves before it is a range, not a tap
const WOOD_PER_TREE := 1
const InGameMenu := preload("res://Scripts/ingame_menu.gd")
const BUTTON_PATH := "/root/Flagoria/CanvasLayer1/ModeButton"
const INVENTORY_PATH := "/root/Flagoria/Inventory"
const ICONS := {
	Mode.COMBAT: preload("res://art/ui/ui_mode_combat.png"),
	Mode.INTERACT: preload("res://art/ui/ui_mode_interact.png"),
}
const TOOLTIPS := {Mode.COMBAT: "Combat mode", Mode.INTERACT: "Interact mode"}
const LINE_COLOR := Color(0.949, 0.918, 0.945, 0.9)
const FILL_COLOR := Color(0.949, 0.918, 0.945, 0.18)

var mode := Mode.COMBAT
var player: Node2D  ## the local player, set by bind()
var _touch := -1  ## index of the touch being followed, or -1
var _start := Vector2.ZERO  ## viewport position where it went down
var _end := Vector2.ZERO
var _dragging := false

@onready var world_map: TileMap = get_node("../worldMap")


func _ready() -> void:
	z_index = 3  # over the trees
	var button := get_node_or_null(BUTTON_PATH) as Button
	if button:
		InGameMenu.fit_icon_button(button)
		button.pressed.connect(toggle_mode)
	_refresh_button()


func bind(local_player: Node2D) -> void:
	player = local_player


func toggle_mode() -> void:
	set_mode(Mode.INTERACT if mode == Mode.COMBAT else Mode.COMBAT)


func set_mode(value: Mode) -> void:
	mode = value
	_cancel()
	_refresh_button()
	mode_changed.emit(mode)


func _refresh_button() -> void:
	var button := get_node_or_null(BUTTON_PATH) as Button
	if button:
		button.icon = ICONS[mode]
		button.tooltip_text = TOOLTIPS[mode]
		button.set_pressed_no_signal(mode == Mode.INTERACT)


func _process(_delta: float) -> void:
	if mode == Mode.INTERACT:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.INTERACT or player == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch == -1 and not _on_hud(event.position):
				_touch = event.index
				_start = event.position
				_end = event.position
				_dragging = false
			elif _touch != -1 and event.index != _touch:
				_cancel()  # a second finger: a pinch, not a selection
		elif event.index == _touch:
			_end = event.position
			if _dragging:
				cut_range(selection_rect())
			else:
				interact_at(to_world(_end))
			_cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch:
		_end = event.position
		if _start.distance_to(_end) > DRAG_START:
			_dragging = true


func _on_hud(pos: Vector2) -> bool:
	var zoom := player.get_node_or_null("Camera2D/MapZoom")
	return zoom != null and zoom.starts_on_hud(pos)


func _cancel() -> void:
	_touch = -1
	_dragging = false
	queue_redraw()


func to_world(viewport_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * viewport_pos


func selection_rect() -> Rect2:
	## The dragged range in world coordinates.
	return Rect2(to_world(_start), Vector2.ZERO).expand(to_world(_end))


func in_reach(cell: Vector2i) -> bool:
	return player != null and player.global_position.distance_to(cell_center(cell)) <= REACH


func cell_center(cell: Vector2i) -> Vector2:
	return world_map.to_global(world_map.map_to_local(cell))


func trees_in_rect(rect: Rect2) -> Array[Vector2i]:
	## Cells in reach with a tree that the world-space `rect` overlaps.
	var half := Vector2(world_map.tile_set.tile_size) * world_map.global_scale / 2.0
	var grown := rect.grow_individual(half.x, half.y, half.x, half.y)
	var a := world_map.local_to_map(world_map.to_local(rect.position))
	var b := world_map.local_to_map(world_map.to_local(rect.end))
	var out: Array[Vector2i] = []
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			var cell := Vector2i(x, y)
			if world_map.has_tree(cell) and grown.has_point(cell_center(cell)) and in_reach(cell):
				out.append(cell)
	return out


func cut_range(rect: Rect2) -> int:
	## Cut every tree trees_in_rect finds; returns how many were cut.
	var cut := 0
	for cell in trees_in_rect(rect):
		cut += int(_cut(cell))
	return cut


func interact_at(world_pos: Vector2) -> bool:
	## A tap: cut the tree in reach nearest `world_pos`, on the tapped cell or
	## one of its 8 neighbours.
	var tapped := world_map.local_to_map(world_map.to_local(world_pos))
	var best := Vector2i.ZERO
	var best_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := tapped + Vector2i(dx, dy)
			var d := world_pos.distance_to(cell_center(cell))
			if d < best_d and world_map.has_tree(cell) and in_reach(cell):
				best = cell
				best_d = d
	return best_d < INF and _cut(best)


func _cut(cell: Vector2i) -> bool:
	if not world_map.cut_tree(cell):
		return false
	var inventory := get_node_or_null(INVENTORY_PATH) as Inventory
	if inventory:
		inventory.add(Inventory.WOOD, WOOD_PER_TREE)
	return true


func _draw() -> void:
	if mode != Mode.INTERACT or player == null:
		return
	draw_arc(to_local(player.global_position), REACH, 0.0, TAU, 48, FILL_COLOR, 1.0)
	if _dragging:
		var rect := selection_rect()
		rect.position = to_local(rect.position)
		draw_rect(rect, FILL_COLOR)
		draw_rect(rect, LINE_COLOR, false, 1.0)
