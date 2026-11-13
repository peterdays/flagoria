extends "res://tests/helpers/test_helpers.gd"
## Interact-mode Wall picker, tip chain and preview (#276).


func _clear_wall_run(world, count: int = 4) -> Array[Vector2i]:
	## Clear land run of `count` cells that 4-touches a seeded support wall
	## (first block must touch tower/castle/wall — design decision for #276).
	for seed_value in [11, 42, 99, 7, 1, 3, 5, 13, 17]:
		world.apply_map_params(_spawn_params(seed_value, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell: Vector2i in world.get_used_cells(0):
			var run: Array[Vector2i] = []
			for i in range(count + 1):
				var c: Vector2i = cell + Vector2i(i, 0)
				if world.get_cell_source_id(0, c) == -1 or not world.predicted_clear(c) \
						or world.has_wall(c) or world._structures.has_cell(c):
					break
				run.append(c)
			if run.size() == count + 1:
				var support: Array[Vector2i] = [run[0]]
				if not world.place_wall_cells(support):
					continue
				var out: Array[Vector2i] = []
				for i in range(1, run.size()):
					out.append(run[i])
				return out
	return []


func _boot_wall_scene() -> Dictionary:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	var run := _clear_wall_run(world, 4)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var inventory: Inventory = scene.get_node("Inventory")
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	var place_cell: Vector2i = run[0] if not run.is_empty() else Vector2i(10, 10)
	var stand: Vector2 = world.to_global(world.map_to_local(place_cell + Vector2i(0, 2)))
	player.position = stand
	# Body collision off: a support wall's physics box can shove the hero onto
	# the first build cell during the boot frame (flake alone and on CI).
	var body: CollisionShape2D = player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body:
		body.disabled = true
	player.set_physics_process(false)
	scene.get_node("World").add_child(player)
	interaction.bind(player)
	await process_frame
	player.position = stand
	return {
		"scene": scene, "world": world, "interaction": interaction,
		"inventory": inventory, "player": player, "run": run,
	}


func _cell_vp(interaction: Interaction, world, cell: Vector2i) -> Vector2:
	return interaction.get_canvas_transform() * world.to_global(world.map_to_local(cell))


func _test_build_picker_includes_wall() -> int:
	## The row shows Plank / Tower / Wall; Wall hides while
	## multiplayer is on (Plank stays, #297). Time cost: about 0.35 s in
	## tools/verify.sh (~2.0 s alone with --only=build_picker_includes_wall).
	print("-- test_build_picker_includes_wall")
	var fail := 0
	var ctx := await _boot_wall_scene()
	var scene = ctx["scene"]
	var interaction: Interaction = ctx["interaction"]
	var picker: Control = scene.get_node_or_null("CanvasLayer1/BuildPicker")
	interaction.set_mode(Interaction.Mode.INTERACT)
	await process_frame
	if picker == null or picker.get_child_count() < 3:
		printerr("FAIL build_picker_includes_wall: picker child count %s"
				% [picker.get_child_count() if picker else null])
		fail += 1
	elif not picker.visible:
		printerr("FAIL build_picker_includes_wall: picker hidden in interact")
		fail += 1
	interaction.build.set_tool(BuildPlacement.Tool.WALL)
	if interaction.build.tool != BuildPlacement.Tool.WALL:
		printerr("FAIL build_picker_includes_wall: set_tool WALL did not stick")
		fail += 1
	var peer := ENetMultiplayerPeer.new()
	var api := SceneMultiplayer.new()
	if peer.create_client("127.0.0.1", 1) != OK:
		printerr("FAIL build_picker_includes_wall: could not start ENet client")
		fail += 1
	else:
		api.multiplayer_peer = peer
		set_multiplayer(api, scene.get_path())
		interaction.build._refresh_picker_visible()
		_open_buildings(scene)
		await process_frame
		var wall_btn: Button = interaction.build._buttons.get(BuildPlacement.Tool.WALL)
		var plank_btn: Button = interaction.build._buttons.get(BuildPlacement.Tool.PLANK)
		if wall_btn == null or not wall_btn.visible:
			printerr("FAIL build_picker_includes_wall: MP should show Wall")
			fail += 1
		if plank_btn == null or not plank_btn.visible:
			printerr("FAIL build_picker_includes_wall: MP should keep Plank visible")
			fail += 1
		if interaction.build.tool != BuildPlacement.Tool.WALL:
			printerr("FAIL build_picker_includes_wall: MP cleared the Wall tool")
			fail += 1
		api.multiplayer_peer = null
		peer.close()
		set_multiplayer(null, scene.get_path())
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_picker_includes_wall")
	return fail


func _test_build_wall_segment_tip_and_gap() -> int:
	## wall_segment: first placement free; with tip, tap must 4-touch; drag is
	## H/V from the tip neighbour; gap and diagonal return empty. Time cost:
	## under 0.05 s in tools/verify.sh (~1.8 s alone with
	## --only=build_wall_segment_tip_and_gap).
	print("-- test_build_wall_segment_tip_and_gap")
	var fail := 0
	var tip := Vector2i(10, 10)
	# First placement: tap or drag.
	var first_tap: Array[Vector2i] = BuildPlacement.new().wall_segment(tip, false, tip, tip)
	if first_tap != [tip]:
		printerr("FAIL build_wall_segment_tip_and_gap: first tap got %s" % [first_tap])
		fail += 1
	var first_drag: Array[Vector2i] = BuildPlacement.new().wall_segment(
			tip, false, tip, tip + Vector2i(3, 0))
	if first_drag.size() != 4 or first_drag[0] != tip or first_drag[3] != tip + Vector2i(3, 0):
		printerr("FAIL build_wall_segment_tip_and_gap: first drag got %s" % [first_drag])
		fail += 1
	# With tip: adjacent tap.
	var adj: Array[Vector2i] = BuildPlacement.new().wall_segment(
			tip, true, tip + Vector2i.RIGHT, tip + Vector2i.RIGHT)
	if adj != [tip + Vector2i.RIGHT]:
		printerr("FAIL build_wall_segment_tip_and_gap: adj tap got %s" % [adj])
		fail += 1
	# Gap (two cells away).
	var gap: Array[Vector2i] = BuildPlacement.new().wall_segment(
			tip, true, tip + Vector2i(2, 0), tip + Vector2i(2, 0))
	if not gap.is_empty():
		printerr("FAIL build_wall_segment_tip_and_gap: gap got %s" % [gap])
		fail += 1
	# Diagonal tap.
	var diag: Array[Vector2i] = BuildPlacement.new().wall_segment(
			tip, true, tip + Vector2i(1, 1), tip + Vector2i(1, 1))
	if not diag.is_empty():
		printerr("FAIL build_wall_segment_tip_and_gap: diag got %s" % [diag])
		fail += 1
	# Drag from tip eastward: starts on tip+RIGHT through end.
	var drag: Array[Vector2i] = BuildPlacement.new().wall_segment(
			tip, true, tip + Vector2i.RIGHT, tip + Vector2i(3, 0))
	if drag.size() != 3 or drag[0] != tip + Vector2i.RIGHT or drag[2] != tip + Vector2i(3, 0):
		printerr("FAIL build_wall_segment_tip_and_gap: tip drag got %s" % [drag])
		fail += 1
	if fail == 0:
		print("PASS test_build_wall_segment_tip_and_gap")
	return fail


func _test_build_wall_preview_matches_commit() -> int:
	## Green cells and cost match what commit places; tip advances; leaving
	## the Wall tool clears the tip; gap shows not adjacent and spends nothing.
	## Time cost: about 0.6 s in tools/verify.sh (~2.3 s alone with
	## --only=build_wall_preview_matches_commit).
	print("-- test_build_wall_preview_matches_commit")
	var fail := 0
	var ctx := await _boot_wall_scene()
	var run: Array[Vector2i] = ctx["run"]
	if run.size() < 4:
		printerr("FAIL build_wall_preview_matches_commit: no clear run")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	inventory.add(Inventory.WOOD, 20)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.WALL)
	var vp0 := _cell_vp(interaction, world, run[0])
	interaction.build.update_preview(vp0, vp0)
	if interaction.build.cells != [run[0]] \
			or not interaction.build.cell_ok.all(func(ok: bool) -> bool: return ok) \
			or interaction.build.cost != 2 \
			or not interaction.build.reasons.is_empty():
		printerr("FAIL build_wall_preview_matches_commit: first preview cells %s ok %s cost %d reasons %s"
				% [interaction.build.cells, interaction.build.cell_ok,
					interaction.build.cost, interaction.build.reasons])
		fail += 1
	var wood_before := inventory.count_of(Inventory.WOOD)
	if not interaction.build.commit():
		printerr("FAIL build_wall_preview_matches_commit: first commit false")
		fail += 1
	if not world.has_wall(run[0]) or inventory.count_of(Inventory.WOOD) != wood_before - 2:
		printerr("FAIL build_wall_preview_matches_commit: after first wall %s wood %d"
				% [world.has_wall(run[0]), inventory.count_of(Inventory.WOOD)])
		fail += 1
	if not interaction.build._has_wall_tip or interaction.build._wall_tip != run[0]:
		printerr("FAIL build_wall_preview_matches_commit: tip not set to %s (has=%s tip=%s)"
				% [run[0], interaction.build._has_wall_tip, interaction.build._wall_tip])
		fail += 1
	# Chain: drag run[1]..run[3] next to tip.
	var vp1 := _cell_vp(interaction, world, run[1])
	var vp3 := _cell_vp(interaction, world, run[3])
	interaction.build.update_preview(vp1, vp3)
	if interaction.build.cells.size() != 3 \
			or interaction.build.cost != 6 \
			or not interaction.build.cell_ok.all(func(ok: bool) -> bool: return ok):
		printerr("FAIL build_wall_preview_matches_commit: chain preview cells %s ok %s cost %d"
				% [interaction.build.cells, interaction.build.cell_ok, interaction.build.cost])
		fail += 1
	wood_before = inventory.count_of(Inventory.WOOD)
	if not interaction.build.commit():
		printerr("FAIL build_wall_preview_matches_commit: chain commit false")
		fail += 1
	if not [run[1], run[2], run[3]].all(func(c: Vector2i) -> bool: return world.has_wall(c)) \
			or inventory.count_of(Inventory.WOOD) != wood_before - 6:
		printerr("FAIL build_wall_preview_matches_commit: after chain wood %d"
				% inventory.count_of(Inventory.WOOD))
		fail += 1
	if interaction.build._wall_tip != run[3]:
		printerr("FAIL build_wall_preview_matches_commit: tip want %s got %s"
				% [run[3], interaction.build._wall_tip])
		fail += 1
	# Gap off tip: empty segment, not adjacent, no spend.
	var far := run[3] + Vector2i(2, 0)
	var vpf := _cell_vp(interaction, world, far)
	wood_before = inventory.count_of(Inventory.WOOD)
	interaction.build.update_preview(vpf, vpf)
	if interaction.build.cells != [far] \
			or interaction.build.cell_ok != [false] \
			or "not adjacent" not in interaction.build.reasons \
			or interaction.build.cost != 0:
		printerr("FAIL build_wall_preview_matches_commit: gap cells %s ok %s reasons %s cost %d"
				% [interaction.build.cells, interaction.build.cell_ok,
					interaction.build.reasons, interaction.build.cost])
		fail += 1
	if interaction.build.commit() or inventory.count_of(Inventory.WOOD) != wood_before:
		printerr("FAIL build_wall_preview_matches_commit: gap spent wood")
		fail += 1
	# Leaving Wall clears tip.
	interaction.build.set_tool(BuildPlacement.Tool.CUT)
	if interaction.build._has_wall_tip:
		printerr("FAIL build_wall_preview_matches_commit: tip survived leave")
		fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_wall_preview_matches_commit")
	return fail

func _test_build_wall_first_must_touch_structure() -> int:
	## First wall block must 4-touch an existing tower, castle or wall;
	## otherwise preview shows not adjacent, commit spends nothing (design decision for #276). Time cost: about 0.5 s in tools/verify.sh (~2.2 s
	## alone with --only=build_wall_first_must_touch_structure).
	print("-- test_build_wall_first_must_touch_structure")
	var fail := 0
	var ctx := await _boot_wall_scene()
	var world = ctx["world"]
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var run: Array[Vector2i] = ctx["run"]
	inventory.add(Inventory.WOOD, 20)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.WALL)
	# Floating cell: leave Wall tip clear, tap a clear cell that does not
	# 4-touch any wall/structure (far from the seeded support + run).
	var floating := Vector2i(1 << 18, 1 << 18)
	for cell: Vector2i in world.get_used_cells(0):
		if not world.predicted_clear(cell) or world.has_wall(cell) \
				or world._structures.has_cell(cell):
			continue
		var touches := false
		for n in [cell + Vector2i.LEFT, cell + Vector2i.RIGHT,
				cell + Vector2i.UP, cell + Vector2i.DOWN]:
			if world.has_wall(n) or world._structures.has_cell(n):
				touches = true
				break
		if touches:
			continue
		# Keep the player in reach of this cell.
		ctx["player"].position = world.to_global(world.map_to_local(cell + Vector2i(0, 1)))
		await process_frame
		if not interaction.in_reach(cell):
			continue
		floating = cell
		break
	if floating.x == 1 << 18:
		printerr("FAIL build_wall_first_must_touch_structure: no floating land cell")
		fail += 1
	else:
		var vpf := _cell_vp(interaction, world, floating)
		var wood_before := inventory.count_of(Inventory.WOOD)
		interaction.build.update_preview(vpf, vpf)
		if "not adjacent" not in interaction.build.reasons \
				or interaction.build.cost != 0 \
				or interaction.build.commit() \
				or inventory.count_of(Inventory.WOOD) != wood_before \
				or world.has_wall(floating):
			printerr("FAIL build_wall_first_must_touch_structure: floating cells %s ok %s reasons %s cost %d wood %d"
					% [interaction.build.cells, interaction.build.cell_ok,
						interaction.build.reasons, interaction.build.cost,
						inventory.count_of(Inventory.WOOD)])
			fail += 1
	# Supported first block (run[0] 4-touches seeded wall) still places.
	if run.is_empty():
		printerr("FAIL build_wall_first_must_touch_structure: no supported run")
		fail += 1
	else:
		ctx["player"].position = world.to_global(world.map_to_local(run[0] + Vector2i(0, 2)))
		await process_frame
		var vp0 := _cell_vp(interaction, world, run[0])
		var wood_before := inventory.count_of(Inventory.WOOD)
		interaction.build.update_preview(vp0, vp0)
		if interaction.build.cells != [run[0]] or interaction.build.cost != 2 \
				or not interaction.build.reasons.is_empty() \
				or not interaction.build.commit() \
				or not world.has_wall(run[0]) \
				or inventory.count_of(Inventory.WOOD) != wood_before - 2:
			printerr("FAIL build_wall_first_must_touch_structure: supported first cells %s cost %d reasons %s"
					% [interaction.build.cells, interaction.build.cost, interaction.build.reasons])
			fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_wall_first_must_touch_structure")
	return fail


func _open_buildings(scene: Node) -> void:
	var buildings := scene.get_node_or_null("CanvasLayer1/BuildingsButton") as Button
	if buildings != null and not buildings.button_pressed:
		buildings.set_pressed(true)
