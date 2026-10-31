extends "res://tests/helpers/test_helpers.gd"
## Discovery points (Scripts/discovery_points.gd).


func _test_points_discovery() -> int:
	## The server pays DISCOVERY_POINTS once per chunk, to the first player
	## seen in it on two checks in a row: not again for that chunk, not to a
	## second player there, not for a single stale sample or to a dead
	## player, and a new world starts over.
	print("-- test_points_discovery")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	var discovery: DiscoveryPoints = scene.get_node("Discovery")
	discovery.set_physics_process(false)  # checks run by hand below
	var points: Points = scene.get_node("Points")
	scene.add_player(1)
	scene.add_player(2)
	var p1: Node2D = scene.get_node("World/1")
	var p2: Node2D = scene.get_node("World/2")
	var chunk_px := Vector2(world.chunk_width, world.chunk_height) * 16.0
	var cases := [[Vector2i(0, 0), Vector2i(0, 0)], [Vector2i(31, 31), Vector2i(0, 0)],
			[Vector2i(32, 0), Vector2i(1, 0)], [Vector2i(-1, -33), Vector2i(-1, -2)]]
	for c in cases:
		if DiscoveryPoints.chunk_of(c[0], world) != c[1]:
			printerr("FAIL points_discovery chunk_of(%s) = %s, want %s" % [c[0], DiscoveryPoints.chunk_of(c[0], world), c[1]])
			fail += 1
	var home: Vector2i = DiscoveryPoints.chunk_of(world.local_to_map(p1.position), world)
	p2.position = p1.position + chunk_px * 4.0
	p2.health.set_health_now(0)  # dead: its chunk does not pay
	discovery.check_players()
	if points.total_of(1) != 0:
		printerr("FAIL points_discovery paid %s on the first sample" % points.total_of(1))
		fail += 1
	for i in 3:
		discovery.check_players()
	if points.total_of(1) != Points.DISCOVERY_POINTS or discovery.discoverer_of(home) != 1:
		printerr("FAIL points_discovery host has %s after staying in %s (discoverer %s)"
				% [points.total_of(1), home, discovery.discoverer_of(home)])
		fail += 1
	if points.total_of(2) != 0:
		printerr("FAIL points_discovery dead player got %s" % points.total_of(2))
		fail += 1
	# A second player in the host's chunk gets nothing for it.
	p2.health.set_health_now(p2.health.max_health)
	p2.position = p1.position
	for i in 3:
		discovery.check_players()
	if points.total_of(2) != 0:
		printerr("FAIL points_discovery second player paid %s for a discovered chunk" % points.total_of(2))
		fail += 1
	# Flicking between two new chunks on every check never pays.
	for i in 4:
		p2.position = p1.position + chunk_px * (3.0 if i % 2 == 0 else -3.0)
		discovery.check_players()
	if points.total_of(2) != 0:
		printerr("FAIL points_discovery paid %s for single samples" % points.total_of(2))
		fail += 1
	# The second player discovers a new chunk; the host following does not.
	var far: Vector2 = p1.position + chunk_px * Vector2(3.0, 0.0)
	p2.position = far
	discovery.check_players()
	discovery.check_players()
	p1.position = far
	for i in 3:
		discovery.check_players()
	var far_chunk: Vector2i = DiscoveryPoints.chunk_of(world.local_to_map(far), world)
	if points.total_of(2) != Points.DISCOVERY_POINTS or points.total_of(1) != Points.DISCOVERY_POINTS \
			or discovery.discoverer_of(far_chunk) != 2:
		printerr("FAIL points_discovery after the new chunk: host %s, second %s, discoverer %s"
				% [points.total_of(1), points.total_of(2), discovery.discoverer_of(far_chunk)])
		fail += 1
	# A new world: the same chunk pays again.
	world.apply_map_params(scene.world_params)
	discovery.check_players()
	discovery.check_players()
	if points.total_of(1) != 2 * Points.DISCOVERY_POINTS or discovery.discoverer_of(far_chunk) != 1:
		printerr("FAIL points_discovery new world: host %s, discoverer %s"
				% [points.total_of(1), discovery.discoverer_of(far_chunk)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_discovery")
	return fail


func _test_points_discovery_two_players() -> int:
	## A client of a dedicated server stands still at its spawn: the server
	## pays it for its spawn chunk exactly once, and its counter shows it.
	print("-- test_points_discovery_two_players")
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL points_discovery_two_players found no free UDP port")
		return 1
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("FAIL points_discovery_two_players could not start the server process")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var points: Points = scene.get_node("Points")
	var hud: ScoreHud = scene.get_node("CanvasLayer1/ScoreHud")
	scene.add_player_joined(port)
	var fail := 0
	var me := 0
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		me = scene.multiplayer.get_unique_id()
		if me > 1 and points.total_of(me) > 0:
			break
		await process_frame
	if points.total_of(me) != Points.DISCOVERY_POINTS:
		printerr("FAIL points_discovery_two_players client total %s, want %s" % [points.total_of(me), Points.DISCOVERY_POINTS])
		fail += 1
	else:
		var until := Time.get_ticks_msec() + 1500  # several more checks
		while Time.get_ticks_msec() < until:
			await process_frame
		if points.total_of(me) != Points.DISCOVERY_POINTS or hud.text != "%d pts" % Points.DISCOVERY_POINTS:
			printerr("FAIL points_discovery_two_players standing still: total %s, counter '%s'" % [points.total_of(me), hud.text])
			fail += 1
	OS.kill(pid)
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	if fail == 0:
		print("PASS test_points_discovery_two_players")
	return fail
