extends "res://tests/helpers/test_helpers.gd"
## Mob state on other peers, and mobs hidden until their ground is drawn.


func _test_mobs_sync_to_peer() -> int:
	## Two players: a dedicated server places the mobs and a client that joins
	## gets the same set (names, types, near the planned cells), and sees them
	## move as the server wanders them. The client's own mob spawn rate differs
	## from the server's and changes nothing: the server's rate is used.
	print("-- test_mobs_sync_to_peer")
	var game = root.get_node("GameSettings")
	var host_rate: float = game.mob_rate  # the server process loads the same saved settings
	var timeout_ms := 30000
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL mobs_sync_to_peer found no free UDP port")
		return 1
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("FAIL mobs_sync_to_peer could not start the server process")
		return 1
	game.set_mob_rate(game.MOB_RATE_MIN if host_rate == game.MOB_RATE_MAX else game.MOB_RATE_MAX, false)
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var fail := 0
	var mobs_node: MobSpawner = scene.get_node("World/Mobs")
	var world = scene.get_node("World/worldMap")
	scene.add_player_joined(port)
	var plan: Array = []
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		var params: MapGenParams = scene.world_params
		if plan.is_empty() and params != null and params.altitude_seed != 0:
			plan = MobSpawner.plan(world, world.resolve_player_spawn(), params.altitude_seed, host_rate)
		if not plan.is_empty() and mobs_node.mobs().size() >= plan.size():
			break
		await process_frame
	var mobs: Array = mobs_node.mobs()
	if plan.is_empty():
		printerr("FAIL mobs_sync_to_peer no map params or an empty mob plan")
		fail += 1
	elif mobs.size() != plan.size():
		printerr("FAIL mobs_sync_to_peer client has %s mobs, plan has %s" % [mobs.size(), plan.size()])
		fail += 1
	else:
		var start := {}
		for i in plan.size():
			var m: Mob = mobs_node.get_node_or_null("mob_%d" % i)
			var at: Vector2 = world.map_to_local(plan[i]["cell"])
			if m == null or m.mob_type != plan[i]["type"]:
				printerr("FAIL mobs_sync_to_peer mob_%d missing or not a %s" % [i, plan[i]["type"]])
				fail += 1
			elif m.position.distance_to(at) > Mob.WANDER_RADIUS + 1.0:
				printerr("FAIL mobs_sync_to_peer mob_%d at %s, planned %s" % [i, m.position, at])
				fail += 1
			else:
				start[m] = m.position
		var moved := false
		deadline = Time.get_ticks_msec() + 10000
		while fail == 0 and not moved and Time.get_ticks_msec() < deadline:
			await process_frame
			for m in start:
				if is_instance_valid(m) and m.position != start[m]:
					moved = true
		if fail == 0 and not moved:
			printerr("FAIL mobs_sync_to_peer no mob moved on the client in 10 s")
			fail += 1
	OS.kill(pid)
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	game.set_mob_rate(host_rate, false)
	if fail == 0:
		print("PASS test_mobs_sync_to_peer (%s mobs)" % plan.size())
	return fail


func _test_mob_hidden_on_uncharted() -> int:
	## A mob is drawn only where this peer has generated the ground under it:
	## visible on a loaded tile, hidden on an unloaded one, visible again once
	## that tile loads. A type flagged visible_in_uncharted (final bosses)
	## always shows. Hiding never changes the mob's position, state or hurt box.
	print("-- test_mob_hidden_on_uncharted")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world: TileMap = scene.get_node("World/worldMap")
	world.apply_map_params(_spawn_params(42, 0.003))
	world.generate_chunk(Vector2.ZERO)
	var mobs_node: Node = scene.get_node("World/Mobs")
	var far := Vector2i(400, 400)  # far outside the loaded chunk
	var add_mob := func(cell: Vector2i, boss: bool) -> Mob:
		var m: Mob = load("res://Mobs/mob.tscn").instantiate()
		m.setup(MobCatalog.SLIME, world.map_to_local(cell), 7)
		m.visible_in_uncharted = boss
		mobs_node.add_child(m, true)
		return m
	var near_mob: Mob = add_mob.call(Vector2i(0, 0), false)
	var far_mob: Mob = add_mob.call(far, false)
	var boss: Mob = add_mob.call(far + Vector2i(2, 0), true)
	var fail := 0
	if world.get_cell_source_id(0, far) != -1 or world.get_cell_source_id(0, Vector2i.ZERO) == -1:
		printerr("FAIL mob_hidden_on_uncharted setup: far tile loaded or near tile missing")
		scene.queue_free()
		return 1
	var before := {}
	for m in [near_mob, far_mob, boss]:
		before[m] = [m.position, m.state, m.facing, m.hp, m.hurt_box.monitoring]
	var tick := func() -> void:
		for m in [near_mob, far_mob, boss]:
			m._process(0.01)
	tick.call()
	if not near_mob.visible:
		printerr("FAIL mob_hidden_on_uncharted mob on a loaded tile is hidden")
		fail += 1
	if far_mob.visible:
		printerr("FAIL mob_hidden_on_uncharted mob on an unloaded tile is visible")
		fail += 1
	if not boss.visible:
		printerr("FAIL mob_hidden_on_uncharted visible_in_uncharted mob is hidden")
		fail += 1
	world.generate_chunk(world.map_to_local(far))
	tick.call()
	if not far_mob.visible:
		printerr("FAIL mob_hidden_on_uncharted mob still hidden after its tile loaded")
		fail += 1
	for m in [near_mob, far_mob, boss]:
		var now := [m.position, m.state, m.facing, m.hp, m.hurt_box.monitoring]
		if now != before[m]:
			printerr("FAIL mob_hidden_on_uncharted %s changed: %s -> %s" % [m.name, before[m], now])
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_mob_hidden_on_uncharted")
	return fail


func _test_mob_shown_when_ground_drawn() -> int:
	## A player respawns (or joins) next to a mob on ground this peer has not
	## generated yet. The mob must become visible in the same frame the chunk
	## under it is drawn, not on a later visibility check.
	print("-- test_mob_shown_when_ground_drawn")
	# Let earlier tests' queue_free() run so this instance is /root/Flagoria,
	# the path TileMap._process uses to find the player.
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	if scene.get_path() != NodePath("/root/Flagoria"):
		printerr("FAIL mob_shown_when_ground_drawn scene at %s, not /root/Flagoria" % scene.get_path())
		scene.queue_free()
		return 1
	var world: TileMap = scene.get_node("World/worldMap")
	world.apply_map_params(_spawn_params(42, 0.003))
	world.generate_chunk(Vector2.ZERO)
	var player := Node2D.new()
	player.name = str(world.multiplayer.get_unique_id())
	scene.get_node("World").add_child(player)
	world.player_spawned = true
	var mob_cell := Vector2i(400, 400)  # far outside the loaded chunk
	var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
	mob.setup(MobCatalog.SLIME, world.map_to_local(mob_cell), 7)
	scene.get_node("World/Mobs").add_child(mob, true)
	var fail := 0
	for i in 3:
		await process_frame
	if mob.visible or world.get_cell_source_id(0, mob_cell) != -1:
		printerr("FAIL mob_shown_when_ground_drawn setup: mob visible %s, its tile loaded %s"
				% [mob.visible, world.get_cell_source_id(0, mob_cell) != -1])
		fail += 1
	else:
		player.position = world.map_to_local(mob_cell + Vector2i(1, 0))  # respawned beside it
		var drawn_at := -1
		for f in world.chunk_refresh_frames * 3:
			await process_frame
			if world.get_cell_source_id(0, mob_cell) != -1:
				drawn_at = f
				break
		if drawn_at < 0:
			printerr("FAIL mob_shown_when_ground_drawn the chunk under the mob was never drawn")
			fail += 1
		elif not mob.visible:
			printerr("FAIL mob_shown_when_ground_drawn ground drawn on frame %d but the mob is still hidden" % drawn_at)
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_mob_shown_when_ground_drawn")
	return fail
