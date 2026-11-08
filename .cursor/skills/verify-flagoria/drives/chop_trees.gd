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
## Viewport px of a one-tree drag. Past the 6 px threshold, and short enough
## that the box still holds only the tree under the finger.
const ONE_DRAG_PX := 7.0
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

	step("one-drag")
	if not await one_drag(it, map, "drag-impact", "drag-cut"):
		done(false)
		return

	step("range")
	if not await range_cut(it, map):
		done(false)
		return

	step("constrained")
	if not await _resize(854, 480):
		done(false)
		return
	if not await one_drag(it, map, "drag-impact-constrained", "drag-cut-constrained"):
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


## A finger drag whose box holds one tree. The chop sheet reaches an impact
## frame, then that tree becomes a stump. `impact_label` and `cut_label` are
## the snapshot names.
func one_drag(it: Node, map: TileMap, impact_label: String, cut_label: String) -> bool:
	var plan := {}
	for _try in 6:
		if not await settle():
			return false
		plan = _one_plan(it, map)
		if not plan.is_empty():
			break
		await hold("ui_down", 12)
	if plan.is_empty():
		printerr("chop: no one-tree drag from %s" % hero().global_position)
		return false
	var cell: Vector2i = plan["cell"]
	print("chop: one-drag targets %d %s, %.1f viewport px, window %s" % [
			int(plan["count"]), cell, float(plan["px"]), DisplayServer.window_get_size()])
	var hits: Array[Vector2i] = []
	var on_hit := func(c: Vector2i, _hit: int) -> void: hits.append(c)
	it.chop_hit.connect(on_hit)
	var start: Vector2 = plan["start"]
	var end_pos: Vector2 = plan["end"]
	await _drag_window(start, end_pos)
	var pose: Sprite2D = hero().get_node("ChopSprite")
	var walk: Sprite2D = hero().get_node("Sprite2D")
	if not it.chopping() or it.chop_cell != cell or not pose.visible or walk.visible \
			or map.choppable(cell) == null:
		it.chop_hit.disconnect(on_hit)
		printerr("chop: one-drag did not start on %s (chopping %s cell %s pose %s walk %s tree %s)" % [
				cell, it.chopping(), it.chop_cell, pose.visible, walk.visible, map.choppable(cell) != null])
		return false
	var saw_impact := false
	var stumped := false
	var deadline := Time.get_ticks_msec() + int(FALL_S * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if it.chopping() and pose.visible and pose.frame_coords.x >= 2 and not saw_impact:
			saw_impact = true
			print("chop: one-drag impact frame %s" % pose.frame_coords)
			await snapshot(impact_label)
		if map.get_cell_atlas_coords(GROUND_DECOR_LAYER, cell) == TileCatalog.STUMP:
			stumped = true
			break
		await process_frame
	it.chop_hit.disconnect(on_hit)
	await snapshot(cut_label)
	var own := not hits.any(func(c: Vector2i) -> bool: return c != cell)
	if not saw_impact or not stumped or hits.size() != 2 or not own:
		printerr("chop: one-drag result swing %s stump %s hits %s" % [saw_impact, stumped, hits])
		return false
	print("chop: one-drag stump at %s after %d hit(s)" % [cell, hits.size()])
	return true


## A drag from the hero toward one tree, long enough for that tree and no other.
func _one_plan(it: Node, map: TileMap) -> Dictionary:
	var zoom: Node = hero().get_node_or_null("Camera2D/MapZoom")
	var origin := hero().global_position
	for c in _trees_in_reach(it, map):
		var cell: Vector2i = c
		var to_cell: Vector2 = it.cell_center(cell) - origin
		if to_cell.length() < 8.0 or to_cell.length() + 12.0 > Interaction.CHOP_REACH:
			continue
		var end_world: Vector2 = origin + to_cell.normalized() * (to_cell.length() + 12.0)
		var start_canvas: Vector2 = hero().get_global_transform_with_canvas() * Vector2.ZERO
		var end_canvas: Vector2 = map.get_global_transform_with_canvas() * map.to_local(end_world)
		var start := root.get_final_transform() * start_canvas
		var end_pos := root.get_final_transform() * end_canvas
		if start.distance_to(end_pos) <= 6.0:
			continue
		if zoom != null and (bool(zoom.call("starts_on_hud", start_canvas)) or bool(zoom.call("starts_on_hud", end_canvas))):
			continue
		it._start = start_canvas
		it._end = end_canvas
		var cells: Array = it.choppables_in_sweep()
		it._start = Vector2.ZERO
		it._end = Vector2.ZERO
		if cells.size() == 1 and cells[0] == cell:
			return {
				"cell": cell,
				"start": start,
				"end": end_pos,
				"count": cells.size(),
				"px": start.distance_to(end_pos),
			}
	return {}


## Drags from the hero through two trees in one cone. The near tree plays the
## chop sheet while the far tree is still standing, then the far tree gets
## its own chop. Both end as stumps.
func range_cut(it: Node, map: TileMap) -> bool:
	var plan := {}
	for _try in 8:
		if not await settle():
			return false
		plan = _range_plan(it, map)
		if not plan.is_empty():
			break
		await hold("ui_down", 12)
	if plan.is_empty():
		printerr("chop: no two trees in one chop cone from %s" % hero().global_position)
		return false
	var cells: Array = plan["cells"]
	var near: Vector2i = cells[0]
	var far: Vector2i = cells[1]
	print("chop: range %s then %s, chop reach %.0f sword reach %.0f ratio %.2f" % [
			near, far, Interaction.CHOP_REACH, AimConeStyle.SWORD_REACH,
			Interaction.CHOP_REACH / AimConeStyle.SWORD_REACH])
	await _drag_window(plan["start"], plan["end"])
	var pose: Sprite2D = hero().get_node("ChopSprite")
	if not it.chopping() or it.chop_cell != near or not pose.visible or map.choppable(far) == null:
		printerr("chop: range did not start on %s (cell %s chopping %s far %s)" % [
				near, it.chop_cell, it.chopping(), map.choppable(far) != null])
		return false
	await snapshot("range-first")
	var deadline := Time.get_ticks_msec() + 4000
	var second := false
	while Time.get_ticks_msec() < deadline:
		if map.choppable(near) == null and it.chopping() and it.chop_cell == far and pose.visible:
			second = true
			await snapshot("range-second")
			break
		await process_frame
	if not second:
		printerr("chop: the far tree %s did not get its own chop" % far)
		return false
	var finish_by := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < finish_by:
		if map.choppable(far) == null:
			await snapshot("range")
			print("chop: range sequence finished %s then %s" % [near, far])
			return true
		await process_frame
	printerr("chop: range sequence did not finish %s %s chopping %s" % [near, far, it.chopping()])
	return false


func _range_plan(it: Node, map: TileMap) -> Dictionary:
	var origin := hero().global_position
	var start_canvas: Vector2 = hero().get_global_transform_with_canvas() * Vector2.ZERO
	for c in _trees_in_reach(it, map):
		var far: Vector2i = c
		var to_far: Vector2 = it.cell_center(far) - origin
		if to_far.length() < 24.0 or to_far.length() + 12.0 > Interaction.CHOP_REACH:
			continue
		var end_world: Vector2 = origin + to_far.normalized() * (to_far.length() + 12.0)
		var end_canvas: Vector2 = map.get_global_transform_with_canvas() * map.to_local(end_world)
		it._start = start_canvas
		it._end = end_canvas
		var selected: Array = it.choppables_in_sweep()
		it._start = Vector2.ZERO
		it._end = Vector2.ZERO
		if selected.size() >= 2:
			return {
				"cells": selected,
				"start": root.get_final_transform() * start_canvas,
				"end": root.get_final_transform() * end_canvas,
			}
	return {}


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
	for dy in range(-16, 17):
		for dx in range(-16, 17):
			var c := at + Vector2i(dx, dy)
			var t: Resource = map.choppable(c)
			if t != null and t.get("id") in ["tree", "pine"] and it.chop_in_reach(c):
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
