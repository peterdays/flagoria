extends "res://tests/helpers/test_helpers.gd"
## Mobs chasing players.


func _test_mob_chase() -> int:
	## A mob chases the nearest player inside CHASE_RADIUS, stays on its home
	## ground while chasing, ignores players further out, and gives up when the
	## player is past GIVE_UP_RADIUS.
	print("-- test_mob_chase")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	scene.spawn_mobs()
	var near := CharacterBody2D.new()
	var far := CharacterBody2D.new()
	scene.get_node("World").add_child(near)
	scene.get_node("World").add_child(far)
	var dt := 1.0 / 45.0
	var fail := 0
	var tested := 0
	for mob in scene.get_node("World/Mobs").mobs():
		var spot = _chase_spot(world, mob, 3)
		if spot == null:
			continue
		tested += 1
		var label := "%s %s" % [mob.name, mob.mob_type]
		var home: int = MobCatalog.stat(mob.mob_type, "home")
		# Out of range: no chase.
		near.position = mob.position + (spot - mob.position) * 2.0
		far.position = mob.position + Vector2(0, Mob.GIVE_UP_RADIUS * 3)
		mob.think(dt)
		if mob.state == Mob.State.CHASE:
			printerr("FAIL mob_chase %s chased a player %s px away" % [label, mob.position.distance_to(near.position)])
			fail += 1
			continue
		# Two players in range: it picks the nearer one and closes in.
		near.position = spot
		far.position = mob.position + (spot - mob.position) * -1.5
		var start_d: float = mob.position.distance_to(near.position)
		for tick in range(45 * 3):
			mob.think(dt)
			if not MobSpawner.is_home_cell(world, world.local_to_map(mob.position), home):
				printerr("FAIL mob_chase %s left home ground while chasing" % label)
				fail += 1
				break
		if mob.target != near or mob.state != Mob.State.CHASE:
			printerr("FAIL mob_chase %s is not chasing the nearer player (state %s)" % [label, mob.state])
			fail += 1
		elif mob.position.distance_to(near.position) > 8.0:
			printerr("FAIL mob_chase %s only got from %s to %s px" % [label, start_d, mob.position.distance_to(near.position)])
			fail += 1
		if mob.anim_name() != "walk":
			printerr("FAIL mob_chase %s does not play walk while chasing" % label)
			fail += 1
		# Player runs off: it gives up and does not restart at once.
		near.position = mob.position + Vector2(Mob.GIVE_UP_RADIUS + 16, 0)
		far.position = near.position
		mob.think(dt)
		if mob.state == Mob.State.CHASE or mob.target != null:
			printerr("FAIL mob_chase %s kept chasing past GIVE_UP_RADIUS" % label)
			fail += 1
		# Calm time: a player back in range is ignored until it runs out.
		near.position = mob.position + Vector2(Mob.CHASE_RADIUS * 0.5, 0)
		mob.think(dt)
		if mob.state == Mob.State.CHASE:
			printerr("FAIL mob_chase %s re-acquired during the calm time" % label)
			fail += 1
		for tick in range(int((Mob.CALM_TIME + 0.2) / dt)):
			mob.think(dt)
		if mob.state != Mob.State.CHASE:
			printerr("FAIL mob_chase %s did not re-acquire after the calm time" % label)
			fail += 1
		near.position = Vector2(1e6, 1e6)
		far.position = near.position
	if tested == 0:
		printerr("FAIL mob_chase no mob had room to test a chase")
		fail += 1
	if fail == 0:
		print("PASS test_mob_chase (%s mobs)" % tested)
	scene.queue_free()
	return fail


func _test_mob_chase_two_players() -> int:
	## Two players: a client of a dedicated server walks up to a mob, and the
	## server's chase reaches the client as the mob's CHASE state and movement
	## towards that client's player.
	print("-- test_mob_chase_two_players")
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL mob_chase_two_players found no free UDP port")
		return 1
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("FAIL mob_chase_two_players could not start the server process")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var mobs_node: MobSpawner = scene.get_node("World/Mobs")
	scene.add_player_joined(port)
	var fail := 0
	var player: Node2D = null
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		player = scene.get_node("World").get_node_or_null(str(scene.multiplayer.get_unique_id()))
		if player and scene.world_params and not mobs_node.mobs().is_empty():
			break
		await process_frame
	var mob: Mob = null
	var spot = null
	var open_ground := false  # the server picks the map, so a straight run of home ground is not certain
	if player and scene.world_params:
		for m in mobs_node.mobs():
			spot = _chase_spot(world, m, 3)
			if spot != null:
				mob = m
				open_ground = true
				break
		if mob == null and not mobs_node.mobs().is_empty():
			mob = mobs_node.mobs()[0]
			spot = mob.position + Vector2(Mob.CHASE_RADIUS * 0.5, 0)
	if mob == null:
		printerr("FAIL mob_chase_two_players no player or mobs on the client")
		fail += 1
	else:
		var chased := false
		var start_d := 0.0
		deadline = Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < deadline:
			player.position = spot
			player.velocity = Vector2.ZERO
			if not chased and mob.state == Mob.State.CHASE:
				chased = true
				start_d = mob.position.distance_to(spot)
			if chased and (not open_ground or mob.position.distance_to(spot) < start_d - 8.0):
				break
			await process_frame
		if not chased:
			printerr("FAIL mob_chase_two_players %s never chased on the client" % mob.name)
			fail += 1
		elif open_ground and mob.position.distance_to(spot) >= start_d - 8.0:
			printerr("FAIL mob_chase_two_players %s chased but did not close in" % mob.name)
			fail += 1
	OS.kill(pid)
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	if fail == 0:
		print("PASS test_mob_chase_two_players (%s)" % mob.name)
	return fail
