class_name Interaction
extends Node2D
## Combat or interact mode for the local player, switched with the HUD mode
## button. Combat is the default and leaves the map to the attack controls.
## In interact mode a tap on the map chops the nearest tree or bush (a
## choppable, see InteractableCatalog) on or next to the tapped cell: the
## hero faces it and swings its type's `hits` chops, and it falls FLASH_TIME
## after the last impact (the chop is ChopAction,
## Scripts/mechanics/trees/chop_action.gd). A drag selects a range: when the
## finger lifts, every choppable in the range that is within REACH of the
## player is cut at once. A cut plant leaves its type's stump and gives its
## type's `yields` (data/interactables/*.tres). Mouse clicks and drags count as
## touches (pointing/emulate_touch_from_mouse). Touches that start on a HUD
## control, and two-finger pinches, select nothing. Cuts are local to this
## game and not synced to other players, so interact mode is single-player
## only: while multiplayer is active (a client, or a host with a peer
## connected) the mode button is hidden and disabled, the mode is forced to
## combat and map input cuts nothing. Hosting alone counts as single-player.

signal mode_changed(mode: Mode)
## A chop's axe landed on `cell`; `hit` counts from 1 to the type's `hits`.
signal chop_hit(cell: Vector2i, hit: int)

enum Mode { COMBAT, INTERACT }

const REACH := 80.0  ## world px from the player to a plant it can cut
const DRAG_START := 6.0  ## viewport px a touch moves before it is a range, not a tap
## The invisible alternative tile a chop swaps in (kept in ChopAction).
const HIDDEN_ALT := ChopAction.HIDDEN_ALT
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
var _allowed := true  ## interact mode is available (not in multiplayer)
## The chop, its effects and its sounds (Scripts/mechanics/trees/chop_action.gd).
var _chop := ChopAction.new(self)
## The chop's state, read through these (kept in ChopAction).
var chop_cell: Vector2i:
	get:
		return _chop.chop_cell
var chop_type: InteractableType:
	get:
		return _chop.chop_type
var chop_time: float:
	get:
		return _chop.chop_time
var sfx_log: Array[AudioStream]:
	get:
		return _chop.sfx_log
var _puff: Sprite2D:
	get:
		return _chop._puff
var _hit: Sprite2D:
	get:
		return _chop._hit
var _fx: Sprite2D:
	get:
		return _chop._fx

@onready var world_map: TileMap = get_node("../worldMap")


func _ready() -> void:
	z_index = 3  # over the trees
	_chop.setup()
	_chop.chop_hit.connect(chop_hit.emit)
	var button := get_node_or_null(BUTTON_PATH) as Button
	if button:
		InGameMenu.fit_icon_button(button)
		button.pressed.connect(toggle_mode)
	_update_allowed()
	_refresh_button()


func bind(local_player: Node2D) -> void:
	player = local_player


func toggle_mode() -> void:
	set_mode(Mode.INTERACT if mode == Mode.COMBAT else Mode.COMBAT)


func set_mode(value: Mode) -> void:
	if value == Mode.INTERACT and not interact_allowed():
		value = Mode.COMBAT
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
		button.visible = _allowed
		button.disabled = not _allowed


func multiplayer_active() -> bool:
	return multiplayer_on(multiplayer)


static func multiplayer_on(api: MultiplayerAPI) -> bool:
	## True for a client (connecting or connected) and for a host with at
	## least one peer connected; false offline or when hosting alone.
	var peer := api.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer \
			or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return false
	return not api.is_server() or not api.get_peers().is_empty()


func interact_allowed() -> bool:
	return not multiplayer_active()


func _update_allowed() -> void:
	## Follow multiplayer starting or ending: force combat mode and hide the
	## button while it is active, show the button again when it ends.
	var allowed := interact_allowed()
	if allowed == _allowed:
		return
	_allowed = allowed
	if not allowed and mode == Mode.INTERACT:
		set_mode(Mode.COMBAT)
	_refresh_button()


func _process(delta: float) -> void:
	_update_allowed()
	step_chop(delta)
	if mode == Mode.INTERACT:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.INTERACT or player == null or not interact_allowed():
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


func choppables_in_rect(rect: Rect2) -> Array[Vector2i]:
	## Cells in reach with a tree or bush that the world-space `rect` overlaps.
	var half := Vector2(world_map.tile_set.tile_size) * world_map.global_scale / 2.0
	var grown := rect.grow_individual(half.x, half.y, half.x, half.y)
	var a := world_map.local_to_map(world_map.to_local(rect.position))
	var b := world_map.local_to_map(world_map.to_local(rect.end))
	var out: Array[Vector2i] = []
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			var cell := Vector2i(x, y)
			if world_map.choppable(cell) and grown.has_point(cell_center(cell)) and in_reach(cell):
				out.append(cell)
	return out


func cut_range(rect: Rect2) -> int:
	## Cut every plant choppables_in_rect finds; returns how many were cut.
	var cut := 0
	for cell in choppables_in_rect(rect):
		cut += int(_cut(cell))
	return cut


func interact_at(world_pos: Vector2) -> bool:
	## A tap: chop the tree or bush in reach nearest `world_pos`, on the
	## tapped cell or one of its 8 neighbours.
	var tapped := world_map.local_to_map(world_map.to_local(world_pos))
	var best := Vector2i.ZERO
	var best_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := tapped + Vector2i(dx, dy)
			var d := world_pos.distance_to(cell_center(cell))
			if d < best_d and world_map.choppable(cell) and in_reach(cell):
				best = cell
				best_d = d
	return best_d < INF and start_chop(best)


func chopping() -> bool:
	return _chop.chopping()


func start_chop(cell: Vector2i) -> bool:
	return _chop.start_chop(cell)


func step_chop(delta: float) -> void:
	_chop.step_chop(delta)


func _cut(cell: Vector2i) -> bool:
	if not interact_allowed():
		return false
	var type: InteractableType = world_map.cut_choppable(cell)
	if type == null:
		return false
	var inventory := get_node_or_null(INVENTORY_PATH) as Inventory
	if inventory:
		for resource in type.yields:
			inventory.add(resource, type.yields[resource])
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
