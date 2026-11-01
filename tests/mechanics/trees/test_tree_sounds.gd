extends "res://tests/helpers/test_helpers.gd"
## Tree chop sounds, and a chop cancelled by the hero's death (#265).


func _chop_scene() -> Dictionary:
	## The main scene with a grass patch, one tree at (10, 8) and the local
	## player two cells below it; the test steps the chop clock itself.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(4, 16):
		for y in range(4, 14):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	world.set_cell(1, Vector2i(10, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)
	interaction.set_mode(Interaction.Mode.INTERACT)
	return {"scene": scene, "world": world, "player": player, "interaction": interaction,
		"inventory": scene.get_node("Inventory")}


static func _names(log: Array[AudioStream]) -> Array[String]:
	var names: Array[String] = []
	for stream in log:
		names.append(stream.resource_path.get_file().get_basename())
	return names


func _test_chop_tree_sounds() -> int:
	## Each impact plays a tree_chop clip (never the same one twice in a row)
	## with leaf_rustle, the last impact adds tree_crack, and the fall at
	## 560 ms plays tree_fall then wood_pickup as the wood is added. All on
	## the SFX bus, the fall on its own player. A bush's slots stay empty, so its sounds are unchanged.
	print("-- test_chop_tree_sounds")
	var fail := 0
	var s: Dictionary = await _chop_scene()
	var interaction: Interaction = s["interaction"]
	var inventory: Inventory = s["inventory"]
	var tree := Vector2i(10, 8)
	var run_to := func(t: float) -> void:
		interaction.step_chop(t - maxf(interaction.chop_time, 0.0))
	if not interaction.start_chop(tree):
		printerr("FAIL chop_tree_sounds: could not start chopping %s" % tree)
		fail += 1
	run_to.call(0.15)
	var got := _names(interaction.sfx_log)
	if got.size() != 2 or not got[0].begins_with("tree_chop_") or got[1] != "leaf_rustle_01":
		printerr("FAIL chop_tree_sounds: first hit sounds %s" % [got])
		fail += 1
	run_to.call(0.47)
	got = _names(interaction.sfx_log)
	if got.size() != 5 or not got[2].begins_with("tree_chop_") or got[2] == got[0] \
			or got[3] != "leaf_rustle_01" or got[4] != "tree_crack_01":
		printerr("FAIL chop_tree_sounds: last hit sounds %s" % [got])
		fail += 1
	run_to.call(0.55)
	if interaction.sfx_log.size() != 5 or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL chop_tree_sounds: sounds or wood before the fall: %s" % [_names(interaction.sfx_log)])
		fail += 1
	run_to.call(0.57)
	got = _names(interaction.sfx_log)
	if got.size() != 7 or got[5] != "tree_fall_01" or not got[6].begins_with("wood_pickup_") \
			or inventory.count_of(Inventory.WOOD) != InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL chop_tree_sounds: at the fall sounds %s, wood %s" % [got, inventory.count_of(Inventory.WOOD)])
		fail += 1
	# The fall comes 0.1 s after the last impact, on its own player, so the
	# last chop is not cut off.
	var fell_chop: ChopAction = interaction._chop
	if fell_chop._sfx_fell.stream == null or fell_chop._sfx_fell.stream.resource_path.get_file().get_basename() != "tree_fall_01" \
			or fell_chop._sfx.stream.resource_path.get_file().get_basename() != got[2]:
		printerr("FAIL chop_tree_sounds: the fall did not keep the last chop playing")
		fail += 1
	interaction.step_chop(1.0)
	if interaction.sfx_log.size() != 7:
		printerr("FAIL chop_tree_sounds: sounds after the chop ended: %s" % [_names(interaction.sfx_log)])
		fail += 1
	var chop: ChopAction = interaction._chop
	for player in [chop._sfx, chop._sfx_layer, chop._sfx_last, chop._sfx_pickup, chop._sfx_fell]:
		if player.bus != &"SFX":
			printerr("FAIL chop_tree_sounds: %s plays on bus %s" % [player, player.bus])
			fail += 1
	# No repeat, over many picks from the three chop clips.
	var hit_sounds := InteractableCatalog.by_id("tree").hit_sounds
	var prev: AudioStream = null
	var seen := {}
	for i in 60:
		chop._play(hit_sounds, chop._sfx, prev)
		if chop._sfx.stream == prev:
			printerr("FAIL chop_tree_sounds: %s picked twice in a row" % chop._sfx.stream.resource_path)
			fail += 1
			break
		prev = chop._sfx.stream
		seen[prev] = true
	if seen.size() != hit_sounds.size():
		printerr("FAIL chop_tree_sounds: only %d of %d chop clips picked in 60" % [seen.size(), hit_sounds.size()])
		fail += 1
	var bush := InteractableCatalog.by_id("bush")
	if bush.hit_no_repeat or bush.fell_own_player or not bush.hit_layer_sounds.is_empty() or not bush.last_hit_sounds.is_empty() \
			or not bush.pickup_sounds.is_empty():
		printerr("FAIL chop_tree_sounds: the bush got new sounds")
		fail += 1
	s["player"].queue_free()
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_tree_sounds")
	return fail


func _test_chop_cancel_on_death() -> int:
	## The hero dying mid-chop, even after the last impact and before the
	## fall, cancels it: the tree stays, no wood is added and no fall or
	## pickup sound plays. After the respawn a new chop works.
	print("-- test_chop_cancel_on_death")
	var fail := 0
	var s: Dictionary = await _chop_scene()
	var interaction: Interaction = s["interaction"]
	var inventory: Inventory = s["inventory"]
	var world = s["world"]
	var health: PlayerHealth = s["player"].health
	var tree := Vector2i(10, 8)
	var run_to := func(t: float) -> void:
		interaction.step_chop(t - maxf(interaction.chop_time, 0.0))
	if not interaction.start_chop(tree):
		printerr("FAIL chop_cancel_on_death: could not start chopping %s" % tree)
		fail += 1
	run_to.call(0.5)  # both hits landed, the fall is at 560 ms
	health.set_health_now(0)
	interaction.step_chop(1.0)
	var got := _names(interaction.sfx_log)
	if interaction.chopping() or not world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != 0 \
			or got.has("tree_fall_01") or got.size() != 5:
		printerr("FAIL chop_cancel_on_death: chopping %s, tree %s, wood %s, sounds %s"
				% [interaction.chopping(), world.has_tree(tree), inventory.count_of(Inventory.WOOD), got])
		fail += 1
	health.respawn()
	s["player"].position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	if health.is_dead() or not interaction.start_chop(tree):
		printerr("FAIL chop_cancel_on_death: no new chop after the respawn (dead %s)" % health.is_dead())
		fail += 1
	interaction.step_chop(0.6)
	if world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL chop_cancel_on_death: the chop after the respawn did not fell the tree")
		fail += 1
	s["player"].queue_free()
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_cancel_on_death")
	return fail
