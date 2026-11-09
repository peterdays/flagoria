extends "res://tests/helpers/test_helpers.gd"
## Interact-mode build picker and plank preview (#225).


func _test_build_placement_snap_run() -> int:
	## A plank drag snaps to a horizontal or vertical cell run; a diagonal
	## finger path becomes the dominant axis. Time cost: under 0.05 s in
	## tools/verify.sh (~1.7 s alone with --only=, against runner start-up).
	print("-- test_build_placement_snap_run")
	var fail := 0
	var horiz := BuildPlacement.snap_run(Vector2i(3, 5), Vector2i(7, 8))
	var want_h: Array[Vector2i] = [
		Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5),
	]
	if horiz != want_h:
		printerr("FAIL build_placement_snap_run: diagonal->H got %s" % [horiz])
		fail += 1
	var vert := BuildPlacement.snap_run(Vector2i(3, 5), Vector2i(4, 9))
	var want_v: Array[Vector2i] = [
		Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(3, 9),
	]
	if vert != want_v:
		printerr("FAIL build_placement_snap_run: diagonal->V got %s" % [vert])
		fail += 1
	var one := BuildPlacement.snap_run(Vector2i(2, 2), Vector2i(2, 2))
	if one != [Vector2i(2, 2)]:
		printerr("FAIL build_placement_snap_run: single cell got %s" % [one])
		fail += 1
	if fail == 0:
		print("PASS test_build_placement_snap_run")
	return fail


func _test_build_picker_switches_tool() -> int:
	## Entering interact mode shows the Cut/Plank picker; picking Plank
	## switches the tool; leaving interact hides the picker and resets to
	## Cut. Time cost: about 0.3 s in tools/verify.sh (~2.0 s alone with
	## --only=build_picker_switches_tool).
	print("-- test_build_picker_switches_tool")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var picker: HBoxContainer = scene.get_node_or_null("CanvasLayer1/BuildPicker")
	if picker == null or picker.get_child_count() < 2:
		printerr("FAIL build_picker_switches_tool: picker missing or short")
		fail += 1
	elif picker.visible:
		printerr("FAIL build_picker_switches_tool: picker visible in combat")
		fail += 1
	interaction.set_mode(Interaction.Mode.INTERACT)
	await process_frame
	if picker == null or not picker.visible:
		printerr("FAIL build_picker_switches_tool: picker hidden in interact")
		fail += 1
	if interaction.build.tool != BuildPlacement.Tool.CUT:
		printerr("FAIL build_picker_switches_tool: default tool %s" % interaction.build.tool)
		fail += 1
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	if interaction.build.tool != BuildPlacement.Tool.PLANK:
		printerr("FAIL build_picker_switches_tool: set_tool did not stick")
		fail += 1
	interaction.set_mode(Interaction.Mode.COMBAT)
	await process_frame
	if picker != null and picker.visible:
		printerr("FAIL build_picker_switches_tool: picker still visible in combat")
		fail += 1
	if interaction.build.tool != BuildPlacement.Tool.CUT:
		printerr("FAIL build_picker_switches_tool: combat did not reset to Cut")
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_picker_switches_tool")
	return fail


func _shore_run(world) -> Dictionary:
	## `{shore, water_run}` for a 2+ water cells east of land near the origin.
	var land := func(c: Vector2i) -> bool:
		return not world.has_bridge(c) and world.ground_is_walkable(world.predict_cell(c)[0])
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if not land.call(cell):
				continue
			var run: Array[Vector2i] = []
			for i in range(1, 4):
				var w: Vector2i = cell + Vector2i(i, 0)
				if world.predict_cell(w)[0] != TileCatalog.WATER or world.has_bridge(w):
					break
				run.append(w)
			if run.size() >= 2:
				return {"shore": cell, "water_run": run}
	return {}


func _boot_interact_scene(world_seed_finder: bool = true) -> Dictionary:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	var found := {}
	if world_seed_finder:
		found = _shore_run(world)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var inventory: Inventory = scene.get_node("Inventory")
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	var place_cell: Vector2i = found.get("shore", Vector2i(10, 10))
	player.position = world.to_global(world.map_to_local(place_cell))
	scene.get_node("World").add_child(player)
	interaction.bind(player)
	await process_frame
	return {
		"scene": scene, "world": world, "interaction": interaction,
		"inventory": inventory, "player": player, "found": found,
	}


func _cell_vp(interaction: Interaction, world, cell: Vector2i) -> Vector2:
	return interaction.get_canvas_transform() * world.to_global(world.map_to_local(cell))


func _test_build_plank_preview_tint_and_cost() -> int:
	## A snapped plank drag marks valid water cells green and invalid cells
	## red, and the preview cost matches ConstructionPlacer. Time cost: about
	## 0.5 s in tools/verify.sh (~2.2 s alone with --only=).
	print("-- test_build_plank_preview_tint_and_cost")
	var fail := 0
	var ctx := await _boot_interact_scene()
	var found: Dictionary = ctx["found"]
	if found.is_empty():
		printerr("FAIL build_plank_preview_tint_and_cost: no shore run")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	var water_run: Array[Vector2i] = found["water_run"]
	inventory.add(Inventory.WOOD, water_run.size() + 2)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	var start := _cell_vp(interaction, world, water_run[0])
	var end := _cell_vp(interaction, world, water_run[water_run.size() - 1])
	interaction.build.update_preview(start, end)
	if interaction.build.cells != water_run:
		printerr("FAIL build_plank_preview_tint_and_cost: cells %s want %s"
				% [interaction.build.cells, water_run])
		fail += 1
	if interaction.build.cell_ok.size() != water_run.size() \
			or not interaction.build.cell_ok.all(func(ok: bool) -> bool: return ok):
		printerr("FAIL build_plank_preview_tint_and_cost: cell_ok %s" % [interaction.build.cell_ok])
		fail += 1
	var want_cost := ConstructionPlacer.new(world).cost(BuildCosts.PLANK, water_run)
	if interaction.build.cost != want_cost or not interaction.build.reasons.is_empty():
		printerr("FAIL build_plank_preview_tint_and_cost: cost %d want %d, reasons %s"
				% [interaction.build.cost, want_cost, interaction.build.reasons])
		fail += 1
	# Land cell is invalid (red).
	var shore: Vector2i = found["shore"]
	interaction.build.update_preview(_cell_vp(interaction, world, shore), _cell_vp(interaction, world, shore))
	if interaction.build.cell_ok.is_empty() or interaction.build.cell_ok[0]:
		printerr("FAIL build_plank_preview_tint_and_cost: land should be red, ok=%s reasons=%s"
				% [interaction.build.cell_ok, interaction.build.reasons])
		fail += 1
	# Zero wood on a water run: nothing placeable, all red, refusal shown.
	inventory.spend(Inventory.WOOD, inventory.count_of(Inventory.WOOD))
	interaction.build.update_preview(start, end)
	if interaction.build.cell_ok.any(func(ok: bool) -> bool: return ok) \
			or ConstructionPlacer.NOT_ENOUGH_WOOD not in interaction.build.reasons \
			or interaction.build.cost != 0:
		printerr("FAIL build_plank_preview_tint_and_cost: zero wood ok=%s cost=%d reasons=%s"
				% [interaction.build.cell_ok, interaction.build.cost, interaction.build.reasons])
		fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_plank_preview_tint_and_cost")
	return fail


func _test_build_plank_places_and_spends() -> int:
	## Releasing a plank drag places the longest valid prefix through
	## ConstructionPlacer and spends wood. Time cost: about 0.5 s in
	## tools/verify.sh (~2.2 s alone with --only=).
	print("-- test_build_plank_places_and_spends")
	var fail := 0
	var ctx := await _boot_interact_scene()
	var found: Dictionary = ctx["found"]
	if found.is_empty():
		printerr("FAIL build_plank_places_and_spends: no shore run")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	var water_run: Array[Vector2i] = found["water_run"]
	inventory.add(Inventory.WOOD, water_run.size())
	var before := inventory.count_of(Inventory.WOOD)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	var start := _cell_vp(interaction, world, water_run[0])
	var end := _cell_vp(interaction, world, water_run[water_run.size() - 1])
	interaction.build.update_preview(start, end)
	if not interaction.build.commit():
		printerr("FAIL build_plank_places_and_spends: commit returned false")
		fail += 1
	if not water_run.all(func(c: Vector2i) -> bool: return world.has_bridge(c)):
		printerr("FAIL build_plank_places_and_spends: bridges %s"
				% [water_run.map(func(c: Vector2i) -> bool: return world.has_bridge(c))])
		fail += 1
	if inventory.count_of(Inventory.WOOD) != before - water_run.size():
		printerr("FAIL build_plank_places_and_spends: wood %d -> %d"
				% [before, inventory.count_of(Inventory.WOOD)])
		fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_plank_places_and_spends")
	return fail


func _test_build_cut_mode_unchanged() -> int:
	## With Cut selected, a tap still chops a tree in reach. Time cost: about
	## 0.4 s in tools/verify.sh (~2.1 s alone with --only=).
	print("-- test_build_cut_mode_unchanged")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(-2, 20):
		for y in range(-2, 20):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	world.set_cell(1, Vector2i(10, 6), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.bind(player)
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	interaction.set_mode(Interaction.Mode.INTERACT)
	if interaction.build.tool != BuildPlacement.Tool.CUT:
		printerr("FAIL build_cut_mode_unchanged: expected Cut tool")
		fail += 1
	var at := func(cell: Vector2) -> Vector2:
		return interaction.get_canvas_transform() * world.to_global(cell * 16.0)
	var touch := func(pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.position = pos
		e.pressed = pressed
		vp.push_input(e, true)
	var want_wood := inventory.count_of(Inventory.WOOD)
	_chop_toward(vp, interaction, player, scene.get_node("CanvasLayer1/TouchScreenButton"), world.to_global(world.map_to_local(Vector2i(10, 6))))
	interaction.step_chop(1.0)
	var tree_wood := InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD)
	if world.has_tree(Vector2i(10, 6)) or inventory.count_of(Inventory.WOOD) != want_wood + tree_wood:
		printerr("FAIL build_cut_mode_unchanged: tap did not cut (10, 6); wood %d"
				% inventory.count_of(Inventory.WOOD))
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_cut_mode_unchanged")
	return fail


func _test_build_plank_drag_places() -> int:
	## A real plank drag through unhandled input places the bridge. Time cost:
	## about 0.6 s in tools/verify.sh (~2.3 s alone with --only=).
	print("-- test_build_plank_drag_places")
	var fail := 0
	var ctx := await _boot_interact_scene()
	var found: Dictionary = ctx["found"]
	if found.is_empty():
		printerr("FAIL build_plank_drag_places: no shore run")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	var scene = ctx["scene"]
	var water_run: Array[Vector2i] = found["water_run"]
	inventory.add(Inventory.WOOD, water_run.size())
	var before := inventory.count_of(Inventory.WOOD)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	var vp: Viewport = scene.get_viewport()
	var start := _cell_vp(interaction, world, water_run[0])
	var end := _cell_vp(interaction, world, water_run[water_run.size() - 1])
	var press := InputEventScreenTouch.new()
	press.position = start
	press.pressed = true
	vp.push_input(press, true)
	var drag := InputEventScreenDrag.new()
	drag.position = end
	drag.index = 0
	drag.relative = end - start
	vp.push_input(drag, true)
	var release := InputEventScreenTouch.new()
	release.position = end
	release.pressed = false
	vp.push_input(release, true)
	await process_frame
	if not water_run.all(func(c: Vector2i) -> bool: return world.has_bridge(c)):
		printerr("FAIL build_plank_drag_places: bridges %s cells preview was %s"
				% [water_run.map(func(c: Vector2i) -> bool: return world.has_bridge(c)),
					interaction.build.cells])
		fail += 1
	if inventory.count_of(Inventory.WOOD) != before - water_run.size():
		printerr("FAIL build_plank_drag_places: wood %d -> %d"
				% [before, inventory.count_of(Inventory.WOOD)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_plank_drag_places")
	return fail


func _shore_run_min(world, want: int) -> Dictionary:
	## `{shore, water_run}` with at least `want` water cells off land (H or V).
	var land := func(c: Vector2i) -> bool:
		return not world.has_bridge(c) and world.ground_is_walkable(world.predict_cell(c)[0])
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for s in range(1, 120):
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if not land.call(cell):
				continue
			for d in dirs:
				var run: Array[Vector2i] = []
				for i in range(1, want + 6):
					var w: Vector2i = cell + d * i
					if world.predict_cell(w)[0] != TileCatalog.WATER or world.has_bridge(w):
						break
					run.append(w)
				if run.size() >= want:
					return {"shore": cell, "water_run": run.slice(0, want)}
	return {}


func _boot_shore_min(want: int) -> Dictionary:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	var found := _shore_run_min(world, want)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var inventory: Inventory = scene.get_node("Inventory")
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	var place_cell: Vector2i = found.get("shore", Vector2i(10, 10))
	player.position = world.to_global(world.map_to_local(place_cell))
	scene.get_node("World").add_child(player)
	interaction.bind(player)
	await process_frame
	return {
		"scene": scene, "world": world, "interaction": interaction,
		"inventory": inventory, "player": player, "found": found,
	}


func _preview_green(build: BuildPlacement) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in build.cells.size():
		if build.cell_ok[i]:
			out.append(build.cells[i])
	return out


func _test_build_preview_matches_commit_short_wood() -> int:
	## With 1 wood and a 5-cell water drag, preview greens exactly the 1 cell
	## commit will place and shows cost 1; the rest is red. Time cost: about
	## 0.2 s in tools/verify.sh (~1.9 s alone with --only=).
	print("-- test_build_preview_matches_commit_short_wood")
	var fail := 0
	var ctx: Dictionary = await _boot_shore_min(5)
	var found: Dictionary = ctx["found"]
	if found.is_empty():
		printerr("FAIL preview_matches_commit_short_wood: no 5-cell shore run")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	var drag: Array[Vector2i] = found["water_run"]
	inventory.add(Inventory.WOOD, 1)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	var start := _cell_vp(interaction, world, drag[0])
	var end := _cell_vp(interaction, world, drag[drag.size() - 1])
	interaction.build.update_preview(start, end)
	var green := _preview_green(interaction.build)
	var preview_cost := interaction.build.cost
	if green != [drag[0]] or preview_cost != 1 or not interaction.build.reasons.is_empty():
		printerr("FAIL preview_matches_commit_short_wood: green %s cost %d reasons %s cell_ok %s"
				% [green, preview_cost, interaction.build.reasons, interaction.build.cell_ok])
		fail += 1
	var before := inventory.count_of(Inventory.WOOD)
	if not interaction.build.commit():
		printerr("FAIL preview_matches_commit_short_wood: commit false")
		fail += 1
	var placed: Array[Vector2i] = []
	for cell in drag:
		if world.has_bridge(cell):
			placed.append(cell)
	if placed != green:
		printerr("FAIL preview_matches_commit_short_wood: placed %s want green %s"
				% [placed, green])
		fail += 1
	if inventory.count_of(Inventory.WOOD) != before - preview_cost:
		printerr("FAIL preview_matches_commit_short_wood: wood %d -> %d (cost %d)"
				% [before, inventory.count_of(Inventory.WOOD), preview_cost])
		fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_preview_matches_commit_short_wood")
	return fail


func _test_build_preview_matches_commit_mid_invalid() -> int:
	## An occupied cell mid-run: preview greens exactly the water prefix commit
	## will place and shows that cost; cells from the occupied one onward are
	## red. Time cost: about 0.2 s in tools/verify.sh (~1.9 s alone with --only=).
	print("-- test_build_preview_matches_commit_mid_invalid")
	var fail := 0
	var ctx: Dictionary = await _boot_shore_min(5)
	var found: Dictionary = ctx["found"]
	if found.is_empty():
		printerr("FAIL preview_matches_commit_mid_invalid: no 5-cell shore run")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	var drag: Array[Vector2i] = found["water_run"]
	# Force-occupy mid cell without going through adjacency (mid alone is not
	# next to land). Same check commit/preview see: has_bridge(cell).
	var mid_cell: Vector2i = drag[2]
	world.set_bridge_cell(mid_cell, TileCatalog.TILES["BRIDGE_PLANK_H_WATER"]["atlas"])
	inventory.add(Inventory.WOOD, 10)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	var start := _cell_vp(interaction, world, drag[0])
	var end := _cell_vp(interaction, world, drag[drag.size() - 1])
	interaction.build.update_preview(start, end)
	var green := _preview_green(interaction.build)
	var preview_cost := interaction.build.cost
	var want_green: Array[Vector2i] = [drag[0], drag[1]]
	if green != want_green or preview_cost != want_green.size() \
			or not interaction.build.reasons.is_empty():
		printerr("FAIL preview_matches_commit_mid_invalid: green %s cost %d reasons %s cell_ok %s"
				% [green, preview_cost, interaction.build.reasons, interaction.build.cell_ok])
		fail += 1
	for i in range(2, drag.size()):
		if i < interaction.build.cell_ok.size() and interaction.build.cell_ok[i]:
			printerr("FAIL preview_matches_commit_mid_invalid: cell %d should be red" % i)
			fail += 1
	var before := inventory.count_of(Inventory.WOOD)
	if not interaction.build.commit():
		printerr("FAIL preview_matches_commit_mid_invalid: commit false")
		fail += 1
	var placed_now: Array[Vector2i] = []
	for cell in want_green:
		if world.has_bridge(cell):
			placed_now.append(cell)
	if placed_now != green:
		printerr("FAIL preview_matches_commit_mid_invalid: placed %s want green %s"
				% [placed_now, green])
		fail += 1
	if inventory.count_of(Inventory.WOOD) != before - preview_cost:
		printerr("FAIL preview_matches_commit_mid_invalid: wood %d -> %d (cost %d)"
				% [before, inventory.count_of(Inventory.WOOD), preview_cost])
		fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_preview_matches_commit_mid_invalid")
	return fail


func _test_build_preview_cache_invalidates_on_wood() -> int:
	## Same drag cells after wood changes must recompute (not keep a green
	## skip-cache). Time cost: about 0.5 s in tools/verify.sh (~2.2 s alone
	## with --only=build_preview_cache_invalidates_on_wood).
	print("-- test_build_preview_cache_invalidates_on_wood")
	var fail := 0
	var ctx := await _boot_interact_scene()
	var found: Dictionary = ctx["found"]
	if found.is_empty():
		printerr("FAIL preview_cache_invalidates_on_wood: no shore run")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	var water_run: Array[Vector2i] = found["water_run"]
	inventory.add(Inventory.WOOD, water_run.size() + 2)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	var start := _cell_vp(interaction, world, water_run[0])
	var end := _cell_vp(interaction, world, water_run[water_run.size() - 1])
	interaction.build.update_preview(start, end)
	if interaction.build.cell_ok.is_empty() \
			or not interaction.build.cell_ok.all(func(ok: bool) -> bool: return ok):
		printerr("FAIL preview_cache_invalidates_on_wood: expected green before spend, ok=%s"
				% [interaction.build.cell_ok])
		fail += 1
	inventory.spend(Inventory.WOOD, inventory.count_of(Inventory.WOOD))
	# Same cells as the green preview — must not skip.
	interaction.build.update_preview(start, end)
	if interaction.build.cell_ok.any(func(ok: bool) -> bool: return ok) \
			or ConstructionPlacer.NOT_ENOUGH_WOOD not in interaction.build.reasons \
			or interaction.build.cost != 0:
		printerr("FAIL preview_cache_invalidates_on_wood: after zero wood ok=%s cost=%d reasons=%s"
				% [interaction.build.cell_ok, interaction.build.cost, interaction.build.reasons])
		fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_preview_cache_invalidates_on_wood")
	return fail


func _test_build_picker_hides_on_multiplayer_start() -> int:
	## Host alone in interact + Plank: when multiplayer turns on, the picker
	## refreshes without a mode change. Plank stays (bridge sync #297); Tower
	## and Wall hide. With Plank selected the tool stays Plank.
	## Time cost: about 0.4 s in tools/verify.sh (~2.1 s alone with
	## --only=build_picker_hides_on_multiplayer_start).
	print("-- test_build_picker_hides_on_multiplayer_start")
	var fail := 0
	var ctx := await _boot_interact_scene(false)
	var scene = ctx["scene"]
	var interaction: Interaction = ctx["interaction"]
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.PLANK)
	await process_frame
	var plank_btn: Button = interaction.build._buttons.get(BuildPlacement.Tool.PLANK)
	if plank_btn == null or not plank_btn.visible or interaction.build.tool != BuildPlacement.Tool.PLANK:
		printerr("FAIL picker_hides_on_multiplayer_start: Plank not visible host-alone")
		fail += 1
	var peer := ENetMultiplayerPeer.new()
	var api := SceneMultiplayer.new()
	if peer.create_client("127.0.0.1", 1) != OK:
		printerr("FAIL picker_hides_on_multiplayer_start: could not start ENet client")
		fail += 1
	else:
		api.multiplayer_peer = peer
		set_multiplayer(api, scene.get_path())
		# Do not call _refresh_picker_visible by hand — Interaction._process must.
		await process_frame
		await process_frame
		plank_btn = interaction.build._buttons.get(BuildPlacement.Tool.PLANK)
		var tower_btn: Button = interaction.build._buttons.get(BuildPlacement.Tool.TOWER)
		var wall_btn: Button = interaction.build._buttons.get(BuildPlacement.Tool.WALL)
		if plank_btn == null or not plank_btn.visible:
			printerr("FAIL picker_hides_on_multiplayer_start: Plank should stay visible in MP")
			fail += 1
		if tower_btn == null or tower_btn.visible or wall_btn == null or wall_btn.visible:
			printerr("FAIL picker_hides_on_multiplayer_start: Tower/Wall should hide in MP")
			fail += 1
		if interaction.build.tool != BuildPlacement.Tool.PLANK:
			printerr("FAIL picker_hides_on_multiplayer_start: tool %s want Plank"
					% interaction.build.tool)
			fail += 1
		api.multiplayer_peer = null
		peer.close()
		set_multiplayer(null, scene.get_path())
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_picker_hides_on_multiplayer_start")
	return fail
