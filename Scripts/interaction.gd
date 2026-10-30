class_name Interaction
extends Node2D
## Combat or interact mode for the local player, switched with the HUD mode
## button. Combat is the default and leaves the map to the attack controls.
## In interact mode a tap on the map chops the nearest tree on or next to the
## tapped cell: the hero faces it and swings HITS_PER_TREE chops, and the tree
## falls FLASH_TIME after the last impact (see step_chop). A drag selects a
## range: when the finger lifts, every tree in the range that is within REACH
## of the player is cut at once. A cut tree leaves a stump and gives
## WOOD_PER_TREE wood. Mouse clicks and drags count as
## touches (pointing/emulate_touch_from_mouse). Touches that start on a HUD
## control, and two-finger pinches, select nothing. Cuts are local to this
## game and not synced to other players, so interact mode is single-player
## only: while multiplayer is active (a client, or a host with a peer
## connected) the mode button is hidden and disabled, the mode is forced to
## combat and map input cuts nothing. Hosting alone counts as single-player.

signal mode_changed(mode: Mode)
## A chop's axe landed on `cell`; `hit` counts from 1 to HITS_PER_TREE.
signal chop_hit(cell: Vector2i, hit: int)

enum Mode { COMBAT, INTERACT }

const REACH := 80.0  ## world px from the player to a tree it can cut
const DRAG_START := 6.0  ## viewport px a touch moves before it is a range, not a tap
const WOOD_PER_TREE := 1
const HITS_PER_TREE := 2
## One chop, in s: wind-up 0.10, swing 0.04, impact 0.10, recover 0.08. Each
## entry ends a column of the hero's chop sheet. Chops chain with no idle.
const CHOP_FRAME_ENDS := [0.10, 0.14, 0.24, 0.32]
const CHOP_TIME := 0.32
const IMPACT_AT := 0.14  ## s into each chop when the axe lands and the hit counts
const FLASH_TIME := 0.10  ## s from the last impact until the tree becomes a stump
const FELL_AT := (HITS_PER_TREE - 1) * CHOP_TIME + IMPACT_AT + FLASH_TIME  ## 0.56 s
const MOVE_CANCEL := 2.0  ## world px the player can move from where a chop started
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
var chop_cell := Vector2i.ZERO  ## the tree being chopped
var chop_time := -1.0  ## s since the chop's first wind-up, or -1 when not chopping
var chop_hits := 0
var _chop_from := Vector2.ZERO  ## player position when the chop started
var _chop_facing := "Down"
var _felled := false
var _puff: Sprite2D  ## the cloud over a tree that just fell
var _puff_time := -1.0

@onready var world_map: TileMap = get_node("../worldMap")


func _ready() -> void:
	z_index = 3  # over the trees
	_puff = Sprite2D.new()
	_puff.texture = load(MobCatalog.PUFF_SHEET)
	_puff.hframes = MobCatalog.PUFF_FRAMES
	_puff.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_puff.visible = false
	add_child(_puff)
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
	return best_d < INF and start_chop(best)


func chopping() -> bool:
	return chop_time >= 0.0


func start_chop(cell: Vector2i) -> bool:
	## Start chopping the tree at `cell`; false while another chop runs, or
	## when there is no tree in reach there.
	if chopping() or not interact_allowed() or not world_map.has_tree(cell) or not in_reach(cell):
		return false
	chop_cell = cell
	chop_time = 0.0
	chop_hits = 0
	_felled = false
	_chop_from = player.global_position
	var d := cell_center(cell) - player.global_position
	if absf(d.x) > absf(d.y):
		_chop_facing = "Left" if d.x < 0.0 else "Right"
	else:
		_chop_facing = "Up" if d.y < 0.0 else "Down"
	_pose()
	return true


func step_chop(delta: float) -> void:
	## Advance the chop and the puff by `delta` s. Each chop's impact counts a
	## hit; FELL_AT after the first wind-up the tree becomes a stump under the
	## puff and gives its wood, and the hero recovers until the last chop ends.
	## Moving away, leaving interact mode or losing the tree before it falls
	## cancels with no stump and no wood.
	if _puff_time >= 0.0:
		_puff_time += delta
		var frame := int(_puff_time * MobCatalog.PUFF_FPS)
		_puff.visible = frame < MobCatalog.PUFF_FRAMES
		_puff.frame = mini(frame, MobCatalog.PUFF_FRAMES - 1)
		if not _puff.visible:
			_puff_time = -1.0
	if not chopping():
		return
	if not _felled and (mode != Mode.INTERACT or player == null or not interact_allowed()
			or player.global_position.distance_to(_chop_from) > MOVE_CANCEL
			or not world_map.has_tree(chop_cell)):
		cancel_chop()
		return
	chop_time += delta
	while chop_hits < HITS_PER_TREE and chop_time >= chop_hits * CHOP_TIME + IMPACT_AT:
		chop_hits += 1
		chop_hit.emit(chop_cell, chop_hits)
	if not _felled and chop_time >= FELL_AT:
		_felled = true
		if _cut(chop_cell):
			_puff.position = to_local(cell_center(chop_cell))
			_puff.frame = 0
			_puff.visible = true
			_puff_time = 0.0
	if chop_time >= HITS_PER_TREE * CHOP_TIME:
		cancel_chop()
	else:
		_pose()


func cancel_chop() -> void:
	## Stop chopping and give the hero back the walk sprite.
	if not chopping():
		return
	chop_time = -1.0
	_pose()


func _pose() -> void:
	if player == null or not player.has_method("set_chop_pose"):
		return
	var col := -1
	if chopping():
		var t := fmod(chop_time, CHOP_TIME)
		col = 0
		while col < CHOP_FRAME_ENDS.size() - 1 and t >= CHOP_FRAME_ENDS[col]:
			col += 1
	player.set_chop_pose(_chop_facing, col)


func _cut(cell: Vector2i) -> bool:
	if not interact_allowed() or not world_map.cut_tree(cell):
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
