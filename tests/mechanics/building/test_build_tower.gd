extends "res://tests/helpers/test_helpers.gd"
## Interact-mode Tower picker, preview and place (#273).


func _clear_tower_anchor(world) -> Variant:
	var s: Structure = StructurePlacer.load_named("tower_wood")
	if s == null:
		return null
	for seed_value in [11, 42, 99, 7, 1, 3, 5]:
		world.apply_map_params(_spawn_params(seed_value, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell: Vector2i in world.get_used_cells(0):
			var cells: Array = StructurePlacer.footprint(s, cell).keys()
			if cells.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
				return cell
	return null


func _boot_tower_scene() -> Dictionary:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	var anchor: Variant = _clear_tower_anchor(world)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var inventory: Inventory = scene.get_node("Inventory")
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	var place_cell: Vector2i = anchor if anchor != null else Vector2i(10, 10)
	# Stand just outside the footprint so the player does not occupy it.
	player.position = world.to_global(world.map_to_local(place_cell + Vector2i(0, 3)))
	scene.get_node("World").add_child(player)
	interaction.bind(player)
	await process_frame
	return {
		"scene": scene, "world": world, "interaction": interaction,
		"inventory": inventory, "player": player, "anchor": anchor,
	}


func _cell_vp(interaction: Interaction, world, cell: Vector2i) -> Vector2:
	return interaction.get_canvas_transform() * world.to_global(world.map_to_local(cell))


func _test_build_picker_includes_tower() -> int:
	## The row shows Plank / Tower / Wall; Tower hides while multiplayer
	## is on (Plank stays, #297). Time cost: about 0.35 s in tools/verify.sh
	## (~2.0 s alone with --only=build_picker_includes_tower).
	print("-- test_build_picker_includes_tower")
	var fail := 0
	var ctx := await _boot_tower_scene()
	var scene = ctx["scene"]
	var interaction: Interaction = ctx["interaction"]
	var picker: Control = scene.get_node_or_null("CanvasLayer1/BuildPicker")
	interaction.set_mode(Interaction.Mode.INTERACT)
	await process_frame
	if picker == null or picker.get_child_count() < 3:
		printerr("FAIL build_picker_includes_tower: picker child count %s"
				% [picker.get_child_count() if picker else null])
		fail += 1
	elif not picker.visible:
		printerr("FAIL build_picker_includes_tower: picker hidden in interact")
		fail += 1
	interaction.build.set_tool(BuildPlacement.Tool.TOWER)
	if interaction.build.tool != BuildPlacement.Tool.TOWER:
		printerr("FAIL build_picker_includes_tower: set_tool TOWER did not stick")
		fail += 1
	var peer := ENetMultiplayerPeer.new()
	var api := SceneMultiplayer.new()
	if peer.create_client("127.0.0.1", 1) != OK:
		printerr("FAIL build_picker_includes_tower: could not start ENet client")
		fail += 1
	else:
		api.multiplayer_peer = peer
		set_multiplayer(api, scene.get_path())
		interaction.build._refresh_picker_visible()
		_open_buildings(scene)
		await process_frame
		var tower_btn: Button = interaction.build._buttons.get(BuildPlacement.Tool.TOWER)
		var plank_btn: Button = interaction.build._buttons.get(BuildPlacement.Tool.PLANK)
		if tower_btn == null or tower_btn.visible:
			printerr("FAIL build_picker_includes_tower: MP should hide Tower")
			fail += 1
		if plank_btn == null or not plank_btn.visible:
			printerr("FAIL build_picker_includes_tower: MP should keep Plank visible")
			fail += 1
		if interaction.build.tool == BuildPlacement.Tool.TOWER:
			printerr("FAIL build_picker_includes_tower: MP left tool on Tower")
			fail += 1
		api.multiplayer_peer = null
		peer.close()
		set_multiplayer(null, scene.get_path())
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_picker_includes_tower")
	return fail


func _test_build_tower_preview_matches_commit() -> int:
	## Green footprint and cost 10 match what commit places; red when refused.
	## Time cost: about 0.5 s in tools/verify.sh (~2.2 s alone with --only=).
	print("-- test_build_tower_preview_matches_commit")
	var fail := 0
	var ctx := await _boot_tower_scene()
	var anchor: Variant = ctx["anchor"]
	if anchor == null:
		printerr("FAIL build_tower_preview_matches_commit: no clear anchor")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	inventory.add(Inventory.WOOD, 10)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.TOWER)
	var vp := _cell_vp(interaction, world, anchor)
	interaction.build.update_preview(vp, vp)
	var s: Structure = StructurePlacer.load_named("tower_wood")
	var foot: Array = StructurePlacer.footprint(s, anchor).keys()
	if interaction.build.cells.size() != foot.size() \
			or not interaction.build.cell_ok.all(func(ok: bool) -> bool: return ok) \
			or interaction.build.cost != 10 \
			or not interaction.build.reasons.is_empty():
		printerr("FAIL build_tower_preview_matches_commit: cells %s ok %s cost %d reasons %s"
				% [interaction.build.cells, interaction.build.cell_ok,
					interaction.build.cost, interaction.build.reasons])
		fail += 1
	if not interaction.build.commit():
		printerr("FAIL build_tower_preview_matches_commit: commit false")
		fail += 1
	if world.placed_structures().is_empty() or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL build_tower_preview_matches_commit: after commit structs %s wood %d"
				% [world.placed_structures(), inventory.count_of(Inventory.WOOD)])
		fail += 1
	# Zero wood: all red, cost 0, refusal.
	inventory.add(Inventory.WOOD, 0)
	var clear2: Variant = null
	for cell: Vector2i in world.get_used_cells(0):
		var cells: Array = StructurePlacer.footprint(s, cell).keys()
		if cells.all(func(c): return world.predicted_clear(c) and not world._structures.has_cell(c)):
			clear2 = cell
			break
	if clear2 != null:
		var vp2 := _cell_vp(interaction, world, clear2)
		interaction.build.set_tool(BuildPlacement.Tool.TOWER)
		interaction.build.update_preview(vp2, vp2)
		if interaction.build.cell_ok.any(func(ok: bool) -> bool: return ok) \
				or interaction.build.cost != 0 \
				or ConstructionPlacer.NOT_ENOUGH_WOOD not in interaction.build.reasons:
			printerr("FAIL build_tower_preview_matches_commit: zero wood ok=%s cost=%d reasons=%s"
					% [interaction.build.cell_ok, interaction.build.cost, interaction.build.reasons])
			fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_tower_preview_matches_commit")
	return fail


func _test_build_tower_tap_places() -> int:
	## A tap in Tower tool places through ConstructionPlacer. Time cost: about
	## 0.5 s in tools/verify.sh (~2.2 s alone with --only=build_tower_tap_places).
	print("-- test_build_tower_tap_places")
	var fail := 0
	var ctx := await _boot_tower_scene()
	var anchor: Variant = ctx["anchor"]
	if anchor == null:
		printerr("FAIL build_tower_tap_places: no clear anchor")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	var scene = ctx["scene"]
	inventory.add(Inventory.WOOD, 10)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.TOWER)
	var vp_pos := _cell_vp(interaction, world, anchor)
	var viewport: Viewport = scene.get_viewport()
	var press := InputEventScreenTouch.new()
	press.position = vp_pos
	press.pressed = true
	viewport.push_input(press, true)
	var release := InputEventScreenTouch.new()
	release.position = vp_pos
	release.pressed = false
	viewport.push_input(release, true)
	await process_frame
	if world.placed_structures().is_empty() or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL build_tower_tap_places: structs %s wood %d"
				% [world.placed_structures(), inventory.count_of(Inventory.WOOD)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_tower_tap_places")
	return fail


func _test_build_tower_out_of_reach() -> int:
	## A clear tower anchor beyond reach is red with the correct reason,
	## costs zero and cannot commit; moving into reach re-enables placement.
	print("-- test_build_tower_out_of_reach")
	var ctx := await _boot_tower_scene()
	if ctx["anchor"] == null:
		printerr("FAIL build_tower_out_of_reach: no clear anchor")
		ctx["scene"].queue_free()
		await process_frame
		return 1
	var fail := 0
	var interaction: Interaction = ctx["interaction"]
	var inventory: Inventory = ctx["inventory"]
	var world = ctx["world"]
	var player = ctx["player"]
	var anchor: Vector2i = ctx["anchor"]
	var near: Vector2 = player.position
	inventory.add(Inventory.WOOD, 10)
	interaction.set_mode(Interaction.Mode.INTERACT)
	interaction.build.set_tool(BuildPlacement.Tool.TOWER)
	# Keep terrain and inventory valid: only the anchor's reach changes.
	player.position = world.to_global(world.map_to_local(anchor + Vector2i(0, 10)))
	var vp := _cell_vp(interaction, world, anchor)
	interaction.build.update_preview(vp, vp)
	if interaction.in_reach(anchor) or interaction.build.reasons != ["out of reach"] \
			or interaction.build.cell_ok.any(func(ok: bool) -> bool: return ok) \
			or interaction.build.cost != 0:
		printerr("FAIL build_tower_out_of_reach: reasons %s, ok %s, cost %d"
				% [interaction.build.reasons, interaction.build.cell_ok, interaction.build.cost])
		fail += 1
	if interaction.build.commit() or inventory.count_of(Inventory.WOOD) != 10 \
			or not world.placed_structures().is_empty():
		printerr("FAIL build_tower_out_of_reach: refused tower placed or spent wood")
		fail += 1
	player.position = near
	vp = _cell_vp(interaction, world, anchor)
	interaction.build.update_preview(vp, vp)
	if not interaction.build.reasons.is_empty() or interaction.build.cost != 10 \
			or not interaction.build.cell_ok.all(func(ok: bool) -> bool: return ok):
		printerr("FAIL build_tower_out_of_reach: moving into reach did not restore the green preview")
		fail += 1
	ctx["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_tower_out_of_reach")
	return fail


func _test_construction_tower_cached() -> int:
	## Footprint, geometry check and placement reuse the same parsed tower
	## across anchor changes; none mutates the cached definition (#386).
	print("-- test_construction_tower_cached")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var anchor = _clear_tower_anchor(world)
	if anchor == null:
		printerr("FAIL construction_tower_cached: no clear anchor")
		scene.queue_free()
		await process_frame
		return 1
	var placer := ConstructionPlacer.new(world)
	var foot := placer.tower_footprint(anchor)
	var cached: Structure = placer.get("_tower")
	if cached == null:
		printerr("FAIL construction_tower_cached: footprint did not cache the tower")
		fail += 1
	else:
		var original: Dictionary = StructurePlacer.footprint(cached, Vector2i.ZERO).duplicate(true)
		for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP]:
			var at: Vector2i = anchor + offset
			var cells: Array[Vector2i] = [at]
			placer.tower_footprint(at)
			placer.can_place_geometry(BuildCosts.TOWER, cells)
			if placer.get("_tower") != cached:
				printerr("FAIL construction_tower_cached: anchor change replaced the cached tower")
				fail += 1
		var inventory: Inventory = scene.get_node("Inventory")
		inventory.add(Inventory.WOOD, 10)
		var one: Array[Vector2i] = [anchor]
		if not placer.place(BuildCosts.TOWER, one, inventory) or placer.get("_tower") != cached \
				or inventory.count_of(Inventory.WOOD) != 0:
			printerr("FAIL construction_tower_cached: placement did not reuse the cached tower")
			fail += 1
		if original != StructurePlacer.footprint(cached, Vector2i.ZERO) \
				or foot != placer.tower_footprint(anchor):
			printerr("FAIL construction_tower_cached: preview or placement mutated the definition")
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_tower_cached")
	return fail


func _open_buildings(scene: Node) -> void:
	var buildings := scene.get_node_or_null("CanvasLayer1/BuildingsButton") as Button
	if buildings != null and not buildings.button_pressed:
		buildings.set_pressed(true)
