class_name Interaction
extends Node2D
## Combat or interact mode for the local player, switched with the HUD mode
## button. Combat is the default and leaves the map to the attack controls.
## In interact mode the Cut/Plank picker shows (#225). Cut: a tap chops the
## nearest tree or bush (a choppable, see InteractableCatalog) on or next to
## the tapped cell through ChopAction; a drag selects a range and cuts every
## choppable in reach when the finger lifts. Plank: a drag snaps to a
## horizontal or vertical run; green/red preview and wood cost follow the
## finger; lift places the longest valid prefix through ConstructionPlacer.
## Mouse clicks and drags count as touches. Touches that start on a HUD
## control, and two-finger pinches, select nothing. While the local player is
## dead, taps and drags do nothing (#349).
## While multiplayer is active (a client, or a host with a peer connected)
## the host decides every cut (#223): a client asks it with request_cut, the
## host drops the request when that peer is over its CutRateLimit (#355),
## checks the plant is there and the cutter is alive (#349) and in reach,
## cuts it, sends apply_cut to every other peer and tells the cutter
## its yields with receive_yields. A client's stump appears when the host's
## apply_cut comes back. Peers that join later get the host's cuts, with
## their ages, with the map params. Regrowth is the host's too (#298): a
## client never regrows a stump on its own, and when stumps regrow on the host
## (TileMap.regrow_due) the host sends every peer one apply_regrow_cells per
## tick (#353), which a client applies only when it came from the host.
## Trees that sprout on the host (TreeSprouts, #361) go out the same way, in
## apply_sprout_cells per sprout pass, SPROUTS_PER_MESSAGE cells at most each.
## Plank bridges sync the same way (#297): a client asks with
## request_place_planks, the host checks the placer is alive and in reach,
## writes through ConstructionPlacer.write_plank, sends apply_bridge to every
## other peer and charges the placer with receive_charge. A host placing with
## peers connected spends its own wood through ConstructionPlacer.place and
## broadcasts apply_bridge. Peers that join later get the host's bridges with
## the map params. Towers and walls stay host-alone until #278.

signal mode_changed(mode: Mode)
## A chop's axe landed on `cell`; `hit` counts from 1 to the type's `hits`.
signal chop_hit(cell: Vector2i, hit: int)

enum Mode { COMBAT, INTERACT }

const REACH := 80.0  ## world px from the player to a plant it can cut
## Extra world px the host allows a client's cut, as its copy of that
## player's position can lag a little behind.
const REACH_SLACK := 24.0
## Most cells in one apply_sprout_cells; a bigger pass goes in several.
const SPROUTS_PER_MESSAGE := 500
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
## The chop, its effects and its sounds (Scripts/mechanics/trees/chop_action.gd).
var _chop := ChopAction.new(self)
## Interact-mode build tool: Cut / Plank / Tower / Wall picker (#225 / #276).
var build := BuildPlacement.new()
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
## The host's per-peer ceiling on request_cut (#355).
var cut_limit := CutRateLimit.new()
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
	build.setup(self)
	_chop.chop_hit.connect(chop_hit.emit)
	world_map.plants_regrown.connect(_on_plants_regrown)
	world_map.trees_sprouted.connect(_on_trees_sprouted)
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
	build.on_mode_changed(mode)
	_refresh_button()
	mode_changed.emit(mode)


func _refresh_button() -> void:
	var button := get_node_or_null(BUTTON_PATH) as Button
	if button:
		button.icon = ICONS[mode]
		button.tooltip_text = TOOLTIPS[mode]
		button.set_pressed_no_signal(mode == Mode.INTERACT)


static func multiplayer_on(api: MultiplayerAPI) -> bool:
	## True for a client (connecting or connected) and for a host with at
	## least one peer connected; false offline or when hosting alone.
	var peer := api.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer \
			or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return false
	return not api.is_server() or not api.get_peers().is_empty()


func _process(delta: float) -> void:
	step_chop(delta)
	var mp := multiplayer_on(multiplayer)
	build.on_multiplayer_changed(mp)
	if mode == Mode.INTERACT:
		# Keep the build preview honest while the finger is held still: wood,
		# reach (player walked) or the map can change without a new drag event.
		if _touch != -1 and build.tool in [BuildPlacement.Tool.PLANK, BuildPlacement.Tool.TOWER, BuildPlacement.Tool.WALL]:
			build.update_preview(_start, _end)
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.INTERACT or player == null:
		return
	if player_dead(player):
		if _touch != -1:
			_cancel()
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
			if build.tool in [BuildPlacement.Tool.PLANK, BuildPlacement.Tool.TOWER, BuildPlacement.Tool.WALL]:
				build.update_preview(_start, _end)
				build.commit()
			elif _dragging:
				cut_range(selection_rect())
			else:
				interact_at(to_world(_end))
			_cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch:
		_end = event.position
		if _start.distance_to(_end) > DRAG_START:
			_dragging = true
		if build.tool in [BuildPlacement.Tool.PLANK, BuildPlacement.Tool.TOWER, BuildPlacement.Tool.WALL]:
			build.update_preview(_start, _end)


static func player_dead(node: Node) -> bool:
	var health := node.get_node_or_null("Health") as PlayerHealth
	return health != null and health.is_dead()


func _on_hud(pos: Vector2) -> bool:
	var zoom := player.get_node_or_null("Camera2D/MapZoom")
	return zoom != null and zoom.starts_on_hud(pos)


func _cancel() -> void:
	_touch = -1
	_dragging = false
	build.clear_preview()
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
	## Cut the plant on `cell` for the local player. Alone it is cut here; a
	## host decides it with host_cut; a client asks the host and returns
	## true when it asked (the fall plays, the stump and wood come back).
	if not multiplayer_on(multiplayer):
		var type: InteractableType = world_map.cut_choppable(cell)
		if type != null:
			receive_yields(type.yields)
		return type != null
	if multiplayer.is_server():
		var cut := host_cut(cell)
		if cut != null:
			receive_yields(cut.yields)
		return cut != null
	if world_map.choppable(cell) == null \
			or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	request_cut.rpc_id(1, cell)
	return true


func host_cut(cell: Vector2i) -> InteractableType:
	## Host: cut the plant the map grows on `cell`, drawn here or not, and
	## send the cut to every peer. Returns the type cut, or null when there
	## is none (never grown there, or cut already).
	var type: InteractableType = world_map.cut_grown(cell)
	if type != null:
		apply_cut.rpc(cell)
	return type


@rpc("any_peer", "reliable", "call_remote")
func request_cut(cell: Vector2i) -> void:
	## Host: a client asks to cut `cell`. Dropped when the client is over its
	## CutRateLimit; cut when its player is alive and in reach of it, and
	## send the client its yields.
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not cut_limit.allow(peer):
		return
	var cutter := get_node_or_null("../" + str(peer)) as Node2D
	if cutter == null or player_dead(cutter) \
			or cutter.global_position.distance_to(cell_center(cell)) > REACH + REACH_SLACK:
		return
	var type := host_cut(cell)
	if type != null:
		receive_yields.rpc_id(peer, type.yields)


@rpc("authority", "reliable", "call_remote")
func apply_cut(cell: Vector2i) -> void:
	## A cut the host decided: show the stump here too, drawn or not.
	world_map.cut_grown(cell)


func _on_plants_regrown(cells: Array[Vector2i]) -> void:
	## Host: stumps regrew in one tick; regrow them on every peer too, in one
	## message.
	if multiplayer_on(multiplayer) and multiplayer.is_server():
		apply_regrow_cells.rpc(cells)


@rpc("authority", "reliable", "call_remote")
func apply_regrow_cells(cells: Array[Vector2i]) -> void:
	## Regrowths the host decided: the plants come back here at once. Applied
	## only when the host (peer 1) sent it, whatever the RPC mode above; a
	## cell with no cut here is left alone.
	if multiplayer.get_remote_sender_id() != 1:
		return
	for cell in cells:
		world_map.grow_back(cell)


func _on_trees_sprouted(cells: Array[Vector2i]) -> void:
	## Host: trees sprouted in one pass; sprout them on every peer too, at
	## most SPROUTS_PER_MESSAGE cells per message (like the join cut list, #354).
	if multiplayer_on(multiplayer) and multiplayer.is_server():
		for i in range(0, cells.size(), SPROUTS_PER_MESSAGE):
			apply_sprout_cells.rpc(cells.slice(i, i + SPROUTS_PER_MESSAGE))


@rpc("authority", "reliable", "call_remote")
func apply_sprout_cells(cells: Array[Vector2i]) -> void:
	## Sprouts the host decided, added here at once. Applied only when the
	## host (peer 1) sent it.
	if multiplayer.get_remote_sender_id() != 1:
		return
	for cell in cells:
		world_map.tree_sprouts().add(cell)


func place_planks(cells: Array[Vector2i]) -> bool:
	## Place a plank run for the local player. Alone it goes through
	## ConstructionPlacer.place; a host with peers spends then broadcasts
	## apply_bridge; a client asks the host and returns true when it asked
	## (the bridge and the wood charge come back).
	if cells.is_empty():
		return false
	if not multiplayer_on(multiplayer):
		return _place_planks_local(cells)
	if multiplayer.is_server():
		return host_place_planks(cells, multiplayer.get_unique_id())
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	request_place_planks.rpc_id(1, cells)
	return true


func _place_planks_local(cells: Array[Vector2i]) -> bool:
	var inventory := get_node_or_null(INVENTORY_PATH) as Inventory
	if inventory == null:
		return false
	return ConstructionPlacer.new(world_map).place(BuildCosts.PLANK, cells, inventory)


func host_place_planks(cells: Array[Vector2i], peer_id: int) -> bool:
	## Host: write the plank run for `peer_id`, send it to every other peer,
	## and charge that peer. When the host places for itself, spend and write
	## stay atomic through ConstructionPlacer.place.
	if not multiplayer.is_server() or cells.is_empty():
		return false
	var placer_node := get_node_or_null("../" + str(peer_id)) as Node2D
	if placer_node == null or player_dead(placer_node):
		return false
	for cell in cells:
		if placer_node.global_position.distance_to(cell_center(cell)) > REACH + REACH_SLACK:
			return false
	var placer := ConstructionPlacer.new(world_map)
	var ends: Array[Vector2i] = []
	if peer_id == multiplayer.get_unique_id():
		var inventory := get_node_or_null(INVENTORY_PATH) as Inventory
		if inventory == null or not placer.place(BuildCosts.PLANK, cells, inventory):
			return false
		ends = placer.plank_ends(cells)
	else:
		ends = placer.write_plank(cells)
		if ends.is_empty():
			return false
		receive_charge.rpc_id(peer_id, cells.size())
	if not ends.is_empty():
		apply_bridge.rpc(ends[0], ends[1])
	return true


@rpc("any_peer", "reliable", "call_remote")
func request_place_planks(cells: Array[Vector2i]) -> void:
	## Host: a client asks to place planks on `cells`. Dropped when the
	## placer is dead or out of reach, or the run fails geometry.
	if not multiplayer.is_server():
		return
	host_place_planks(cells, multiplayer.get_remote_sender_id())


@rpc("authority", "reliable", "call_remote")
func apply_bridge(from: Vector2i, to: Vector2i) -> void:
	## A plank run the host decided: lay it here too.
	world_map.build_bridge(from, to)


@rpc("authority", "reliable", "call_remote")
func receive_charge(wood: int) -> void:
	## Take `wood` from the local inventory after the host accepted a place.
	var inventory := get_node_or_null(INVENTORY_PATH) as Inventory
	if inventory and wood > 0:
		inventory.spend(Inventory.WOOD, wood)


@rpc("authority", "reliable", "call_remote")
func receive_yields(yields: Dictionary) -> void:
	## Add what a cut earned to the local inventory (the host sends a
	## client's; inventories stay local per peer).
	var inventory := get_node_or_null(INVENTORY_PATH) as Inventory
	if inventory:
		for resource in yields:
			inventory.add(StringName(resource), int(yields[resource]))


func _draw() -> void:
	if mode != Mode.INTERACT or player == null:
		return
	draw_arc(to_local(player.global_position), REACH, 0.0, TAU, 48, FILL_COLOR, 1.0)
	if build.tool in [BuildPlacement.Tool.PLANK, BuildPlacement.Tool.TOWER, BuildPlacement.Tool.WALL]:
		build.draw_preview(self)
	elif _dragging:
		var rect := selection_rect()
		rect.position = to_local(rect.position)
		draw_rect(rect, FILL_COLOR)
		draw_rect(rect, LINE_COLOR, false, 1.0)
