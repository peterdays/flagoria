extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 11
## Free-form wall chain in interact mode (features/free-form-walls.md). Seed 11
## gives clear land near spawn. Proof from snapshots: Wall picker, a first
## land block that 4-touches the castle, a short chain off the tip, and a
## refused gap that spends no wood. Minimap is closed for evidence.

const SETTLE_FRAMES := 10


func run() -> void:
	step("start")
	if not await start_game() or not await settle():
		done(false)
		return
	var it: Interaction = current_scene.get_node(INTERACTION)
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var inventory: Inventory = current_scene.get_node(INVENTORY)
	inventory.add(Inventory.WOOD, 40)
	# Evidence: hide the default-open explored map (M toggles it in play) so
	# wall / tip / gap shots show the play view, not the mist panel.
	var minimap: MinimapPanel = current_scene.get_node_or_null("CanvasLayer1/MinimapPanel")
	if minimap != null:
		minimap.shown = false
		minimap.visible = false
	await snapshot("start")

	step("interact")
	await toggle_mode()
	if not await wait_until(func() -> bool: return it.mode == Interaction.Mode.INTERACT, 2.0):
		printerr("free_form_walls: mode did not switch to interact")
		done(false)
		return
	it.build.set_tool(BuildPlacement.Tool.WALL)
	if it.build.tool != BuildPlacement.Tool.WALL:
		printerr("free_form_walls: Wall tool did not stick")
		done(false)
		return

	step("first-block")
	var first: Variant = _clear_land_in_reach(it, map)
	if first == null:
		printerr("free_form_walls: no clear land in reach; launch with the seed above")
		done(false)
		return
	var cell0: Vector2i = first
	var wood_before := inventory.count_of(Inventory.WOOD)
	var vp0 := _cell_vp(it, map, cell0)
	it.build.update_preview(vp0, vp0)
	if it.build.cost != 2 or not it.build.commit() or not map.has_wall(cell0) \
			or inventory.count_of(Inventory.WOOD) != wood_before - 2:
		printerr("free_form_walls: first block failed cost=%d wall=%s wood %d->%d"
				% [it.build.cost, map.has_wall(cell0), wood_before, inventory.count_of(Inventory.WOOD)])
		done(false)
		return
	print("free_form_walls: first block at %s" % [cell0])
	# Keep preview tint on screen for the snapshot.
	it._dragging = true
	it._start = vp0
	it._end = vp0
	it.queue_redraw()
	for i in 8:
		await process_frame
	await snapshot("first-block")

	step("chain")
	var next: Vector2i = cell0 + Vector2i.RIGHT
	var end: Vector2i = cell0 + Vector2i(2, 0)
	if not _land_clear(map, next) or not _land_clear(map, end):
		# Try other cardinals for a 2-cell run.
		var found := false
		for step_dir in [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]:
			next = cell0 + step_dir
			end = cell0 + step_dir * 2
			if _land_clear(map, next) and _land_clear(map, end) and it.in_reach(next) and it.in_reach(end):
				found = true
				break
		if not found:
			printerr("free_form_walls: no 2-cell clear run off tip %s" % [cell0])
			done(false)
			return
	wood_before = inventory.count_of(Inventory.WOOD)
	var vpn := _cell_vp(it, map, next)
	var vpe := _cell_vp(it, map, end)
	it.build.update_preview(vpn, vpe)
	var expect_n := it.build.cells.size()
	var expect_cost := expect_n * 2
	if expect_n < 2 or it.build.cost != expect_cost:
		printerr("free_form_walls: chain preview cells=%s cost=%d" % [it.build.cells, it.build.cost])
		done(false)
		return
	if not it.build.commit():
		printerr("free_form_walls: chain commit false")
		done(false)
		return
	var spent := wood_before - inventory.count_of(Inventory.WOOD)
	if spent != expect_cost or not map.has_wall(next):
		printerr("free_form_walls: chain spent %d want %d wall_next=%s" % [spent, expect_cost, map.has_wall(next)])
		done(false)
		return
	print("free_form_walls: chain next=%s end=%s spent=%d tip=%s" % [next, end, spent, it.build._wall_tip])
	# Do not re-preview onto the new tip (that paints "not adjacent" over the
	# just-placed run). Snapshot shows the palisade tiles themselves.
	it._dragging = false
	it.queue_redraw()
	for i in 8:
		await process_frame
	await snapshot("chain")

	step("gap")
	var tip: Vector2i = it.build._wall_tip
	# Prefer an empty land cell two steps off the tip so the red refusal tint
	# lands on sand, not on an already-placed wall.
	var far: Vector2i = tip + Vector2i(2, 0)
	var found_far := false
	for step_dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var candidate: Vector2i = tip + step_dir * 2
		if it.in_reach(candidate) and _land_clear(map, candidate):
			far = candidate
			found_far = true
			break
	if not found_far and not it.in_reach(far):
		far = tip + Vector2i(-2, 0)
	wood_before = inventory.count_of(Inventory.WOOD)
	var vpf := _cell_vp(it, map, far)
	it.build.update_preview(vpf, vpf)
	if it.build.cells != [far] or it.build.cell_ok != [false] \
			or "not adjacent" not in it.build.reasons:
		printerr("free_form_walls: gap cells=%s reasons=%s" % [it.build.cells, it.build.reasons])
		done(false)
		return
	if it.build.commit() or inventory.count_of(Inventory.WOOD) != wood_before:
		printerr("free_form_walls: gap spent wood")
		done(false)
		return
	# commit() clears the preview; rebuild it for the snapshot.
	it.build.update_preview(vpf, vpf)
	print("free_form_walls: gap refused at %s" % [far])
	it._dragging = true
	it._start = vpf
	it._end = vpf
	it.queue_redraw()
	for i in 8:
		await process_frame
	await snapshot("gap")
	done(true)


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
	printerr("free_form_walls: hero did not settle")
	return false


func _cell_vp(it: Interaction, map: TileMap, cell: Vector2i) -> Vector2:
	return it.get_canvas_transform() * map.to_global(map.map_to_local(cell))


func _land_clear(map: TileMap, cell: Vector2i) -> bool:
	return map.get_cell_source_id(0, cell) != -1 and map.predicted_clear(cell) \
			and not map.has_wall(cell) and not map._structures.has_cell(cell) \
			and not map.player_on_cell(cell) and not map.mob_on_cell(cell)


func _touches_support(map: TileMap, cell: Vector2i) -> bool:
	## First wall block must 4-touch a tower, castle or wall (design decision for #276).
	for n in [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
		if map.has_wall(n) or map._structures.has_cell(n):
			return true
	return false


func _clear_land_in_reach(it: Interaction, map: TileMap) -> Variant:
	var at := map.local_to_map(map.to_local(hero().global_position))
	var best: Variant = null
	var best_d := INF
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var c := at + Vector2i(dx, dy)
			if not _land_clear(map, c) or not it.in_reach(c):
				continue
			if not _touches_support(map, c):
				continue
			# Prefer a cell that has at least one clear 4-neighbour for the chain.
			var has_n := false
			for n in [c + Vector2i.LEFT, c + Vector2i.RIGHT, c + Vector2i.UP, c + Vector2i.DOWN]:
				if _land_clear(map, n) and it.in_reach(n):
					has_n = true
					break
			if not has_n:
				continue
			var d := hero().global_position.distance_to(it.cell_center(c))
			if d < best_d:
				best = c
				best_d = d
	return best
