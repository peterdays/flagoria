extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## Chop one tree with a tap in interact mode (features/chop-trees.md). With
## seed 49 (the line above, read by verify-drive.yml) the spawn has trees in
## reach. Proof, read from the 01-before and 02-after snapshots: the target
## cell's tree is a stump and wood went up by the tree's yield once, and
## the chop's sounds (Interaction.sfx_log) came in the order of #265.

const SETTLE_FRAMES := 10  ## physics frames the hero must keep still
const TAPS := 3  ## taps tried before the drive fails
const START_S := 0.5  ## s a tap has to start a chop
const FALL_S := 2.0  ## s a started chop has to leave a stump (fell_at(2) is 0.56)
## The chop's sounds in order, with the clip number dropped (#265).
const SOUNDS := ["tree_chop", "leaf_rustle", "tree_chop", "leaf_rustle", "tree_crack", "tree_fall", "wood_pickup"]

var _hits: Array[Vector2i] = []


func run() -> void:
	step("start")
	if not await start_game() or not await settle():
		done(false)
		return
	var it: Node = current_scene.get_node(INTERACTION)
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var tree: Variant = nearest_tree(it, map)
	if tree == null:
		printerr("chop: no tree in reach of the hero at %s; launch with the seed above" % hero().global_position)
		done(false)
		return
	var cell: Vector2i = tree
	var tree_type: Resource = map.choppable(cell)
	var wood_yield: int = tree_type.yields[&"wood"]
	var inventory: Node = current_scene.get_node(INVENTORY)
	var wood_before: int = inventory.count_of(&"wood")
	print("chop: target %s, %.1f px from the hero, %d hits, +%d wood" % [
			cell, hero().global_position.distance_to(it.cell_center(cell)), tree_type.hits, wood_yield])
	await snapshot("before")

	step("interact-mode")
	await toggle_mode()
	if not await wait_until(func() -> bool: return it.mode == 1, 2.0):  # Interaction.Mode.INTERACT
		printerr("chop: the mode button did not switch to interact mode")
		done(false)
		return

	step("chop")
	it.chop_hit.connect(func(c: Vector2i, _hit: int) -> void: _hits.append(c))
	if not await chop(it, map, cell, tree_type.hits):
		done(false)
		return
	for i in 10:  # a second yield would land in these frames
		await physics_frame
	var wood_after: int = inventory.count_of(&"wood")
	if wood_after - wood_before != wood_yield:
		printerr("chop: wood went %d -> %d, not +%d" % [wood_before, wood_after, wood_yield])
		done(false)
		return
	var sounds := []
	for stream: AudioStream in it.sfx_log:
		sounds.append(stream.resource_path.get_file().get_basename().trim_suffix("_01").trim_suffix("_02").trim_suffix("_03"))
	print("chop: sounds %s" % [sounds])
	if sounds != SOUNDS:
		printerr("chop: sounds %s, expected %s" % [sounds, SOUNDS])
		done(false)
		return
	await snapshot("after")

	step("range")
	if not await range_cut(it, map):
		done(false)
		return

	step("constrained")
	if not await constrained_swing(it, map):
		done(false)
		return
	if not await _resize(1280, 720):
		done(false)
		return

	step("save")
	var saved := []
	get_root().get_node("MapGen").map_saved.connect(func(path: String) -> void: saved.append(path))
	if not await menu_save() or not await wait_until(func() -> bool: return not saved.is_empty(), 5.0):
		printerr("chop: the in-game menu did not save the world")
		done(false)
		return
	print("chop: saved %s" % saved[0])
	done(true)


## Waits until the hero has not moved for SETTLE_FRAMES physics frames.
func settle(timeout_s: float = 5.0) -> bool:
	var last := Vector2.INF
	var still := 0
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end:
		var now := hero().global_position
		still = still + 1 if now == last else 0
		if still >= SETTLE_FRAMES:
			return true
		last = now
		await physics_frame
	printerr("chop: the hero did not settle in %.0f s (at %s)" % [timeout_s, hero().global_position])
	return false


## The tree cell in reach nearest the hero, or null.
func nearest_tree(it: Node, map: TileMap) -> Variant:
	var h := hero()
	var at := map.local_to_map(map.to_local(h.global_position))
	var best: Variant = null
	var best_d := INF
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c := at + Vector2i(dx, dy)
			var t: Resource = map.choppable(c)
			var d := h.global_position.distance_to(it.cell_center(c))
			if t != null and t.get("id") in ["tree", "pine"] and it.in_reach(c) and d < best_d:
				best = c
				best_d = d
	return best


## Taps `cell` until a chop starts on it, then waits for its stump. A tap
## that starts no chop, or a chop that ends with no stump, is printed with
## what the game saw and tried again, up to TAPS taps.
func chop(it: Node, map: TileMap, cell: Vector2i, hits: int) -> bool:
	for attempt in range(1, TAPS + 1):
		if not await settle():
			return false
		_hits.clear()
		it.sfx_log.clear()  # only the last tap's chop counts
		await tap_cell(cell)
		if not await wait_until(func() -> bool: return it.chopping() or not _hits.is_empty(), START_S):
			printerr("chop: tap %d started no chop: %s" % [attempt, diagnose(it, map, cell)])
			continue
		var saw_swing := false
		var saw_impact := false
		var stump := func() -> bool: return map.get_cell_atlas_coords(GROUND_DECOR_LAYER, cell) == TileCatalog.STUMP
		var stumped := false
		var deadline := Time.get_ticks_msec() + int(FALL_S * 1000.0)
		while Time.get_ticks_msec() < deadline:
			var pose: Sprite2D = hero().get_node("ChopSprite")
			if it.chopping() and pose.visible:
				var col: int = pose.frame_coords.x
				if col >= 1 and not saw_swing:
					saw_swing = true
					print("chop: swing frame %s" % pose.frame_coords)
					await snapshot("swing")
				if col >= 2 and not saw_impact:
					saw_impact = true
					print("chop: impact frame %s" % pose.frame_coords)
					await snapshot("impact")
			if stump.call():
				stumped = true
				break
			await process_frame
		if not saw_swing or not saw_impact:
			printerr("chop: tap %d did not show the chop sheet (swing %s, impact %s)" % [attempt, saw_swing, saw_impact])
			return false
		if _hits.any(func(c: Vector2i) -> bool: return c != cell):
			printerr("chop: tap %d chopped %s, not the tree at %s" % [attempt, _hits, cell])
			return false
		if stumped:
			if _hits.size() != hits:
				printerr("chop: %d hit(s) on %s, expected %d" % [_hits.size(), cell, hits])
				return false
			print("chop: stump at %s after %d hit(s), tap %d" % [cell, _hits.size(), attempt])
			return true
		printerr("chop: tap %d chop ended with no stump after %d hit(s): %s" % [attempt, _hits.size(), diagnose(it, map, cell)])
	printerr("chop: no stump at %s after %d taps" % [cell, TAPS])
	return false


## Drags across two trees in reach. Both become stumps at once and the hero
## stays on the walk sprite: a range cut, not a chop.
func range_cut(it: Node, map: TileMap) -> bool:
	var pair: Array[Vector2i] = []
	for _try in 6:
		pair = _axis_pair(_trees_in_reach(it, map))
		if pair.size() == 2:
			break
		await hold("ui_down", 15)
		if not await settle():
			return false
	if pair.size() != 2:
		printerr("chop: no two trees in a row to range-cut from %s" % hero().global_position)
		return false
	var a: Vector2i = pair[0]
	var b: Vector2i = pair[1]
	print("chop: range %s -> %s" % [a, b])
	var start := to_window(map, map.map_to_local(a))
	var end := to_window(map, map.map_to_local(b))
	await _drag_window(start, end)
	var pose: Sprite2D = hero().get_node("ChopSprite")
	var cut: bool = map.choppable(a) == null and map.choppable(b) == null and not it.chopping() and not pose.visible
	print("chop: range cut %s pose %s chopping %s" % [cut, pose.visible, it.chopping()])
	await snapshot("range")
	if not cut:
		printerr("chop: the drag did not range-cut %s and %s (chopping %s, pose %s)" % [a, b, it.chopping(), pose.visible])
		return false
	return true


## One more chop at the short landscape window, so the swing is on screen there too.
func constrained_swing(it: Node, map: TileMap) -> bool:
	if not await _resize(854, 480):
		return false
	var tree: Variant = _nearest_tree(it, map)
	for _try in 6:
		if tree != null:
			break
		await hold("ui_down", 15)
		if not await settle():
			return false
		tree = _nearest_tree(it, map)
	if tree == null:
		printerr("chop: no tree for the constrained swing at %s" % hero().global_position)
		return false
	var cell: Vector2i = tree
	print("chop: constrained tree %s" % cell)
	if not await settle():
		return false
	await tap_cell(cell)
	var saw := false
	var deadline := Time.get_ticks_msec() + int(FALL_S * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var pose: Sprite2D = hero().get_node("ChopSprite")
		if it.chopping() and pose.visible and pose.frame_coords.x >= 1 and not saw:
			saw = true
			print("chop: constrained swing frame %s" % pose.frame_coords)
			await snapshot("swing-constrained")
		if map.get_cell_atlas_coords(GROUND_DECOR_LAYER, cell) == TileCatalog.STUMP:
			break
		await process_frame
	if not saw:
		printerr("chop: constrained window showed no chop swing")
		return false
	return true


func _drag_window(start: Vector2, end_pos: Vector2) -> void:
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = start
	Input.parse_input_event(press)
	await process_frame
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = end_pos
	drag.relative = end_pos - start
	Input.parse_input_event(drag)
	await process_frame
	await process_frame
	var lift := InputEventScreenTouch.new()
	lift.index = 0
	lift.pressed = false
	lift.position = end_pos
	Input.parse_input_event(lift)
	await process_frame
	await process_frame


func _trees_in_reach(it: Node, map: TileMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at := map.local_to_map(map.to_local(hero().global_position))
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var c := at + Vector2i(dx, dy)
			var t: Resource = map.choppable(c)
			if t != null and t.get("id") in ["tree", "pine"] and it.in_reach(c):
				out.append(c)
	return out


func _axis_pair(cells: Array[Vector2i]) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_d := 99
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			var d: Vector2i = cells[j] - cells[i]
			if d.x != 0 and d.y != 0:
				continue
			var span := absi(d.x) + absi(d.y)
			if span >= 1 and span < best_d:
				best_d = span
				best = [cells[i], cells[j]]
	return best


func _nearest_tree(it: Node, map: TileMap) -> Variant:
	var h := hero()
	var at := map.local_to_map(map.to_local(h.global_position))
	var best: Variant = null
	var best_d := INF
	for c in _trees_in_reach(it, map):
		var d := h.global_position.distance_to(it.cell_center(c))
		if d < best_d:
			best = c
			best_d = d
	return best


func _resize(width: int, height: int) -> bool:
	root.size = Vector2i(width, height)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(width, height))
	for _i in 10:
		await process_frame
	var got := DisplayServer.window_get_size()
	print("chop: window %s (asked %dx%d)" % [got, width, height])
	return got.x == width and got.y == height


func diagnose(it: Node, map: TileMap, cell: Vector2i) -> String:
	var h := hero()
	return "hero=%s dist=%.1f in_reach=%s mode=%s chopping=%s choppable=%s tap_window=%s" % [
			h.global_position, h.global_position.distance_to(it.cell_center(cell)), it.in_reach(cell),
			it.mode, it.chopping(), map.choppable(cell) != null,
			to_window(map, map.map_to_local(cell))]
