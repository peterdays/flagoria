extends "res://tests/helpers/test_helpers.gd"
## Player respawn on the host and on other peers.


func _test_player_respawn_no_snapback() -> int:
	## A client-owned player respawns: the server moves its copy to the spawn
	## at once, while the owner keeps sending its old position until the
	## respawn reaches it. Over a link with latency (a UDP proxy that delays
	## each packet), the server copy must not jump back to the death spot.
	print("-- test_player_respawn_no_snapback")
	var fail := 0
	await process_frame
	var port := _free_udp_port()
	var proxy_port := _free_udp_port()
	if port == 0 or proxy_port == 0 or port == proxy_port:
		printerr("FAIL respawn_snapback found no free UDP ports")
		return 1
	var server_root := Node.new()
	server_root.name = "SnapServer"
	root.add_child(server_root)
	var s_world := Node2D.new()
	s_world.name = "World"
	server_root.add_child(s_world)
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var smp := SceneMultiplayer.new()
	var cmp := SceneMultiplayer.new()
	set_multiplayer(smp, server_root.get_path())
	set_multiplayer(cmp, scene.get_path())
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer
	# Proxy: client <-> proxy_port <-> server, each packet held DELAY_MS.
	const DELAY_MS := 60
	var listen := UDPServer.new()
	listen.listen(proxy_port, "127.0.0.1")
	var upstream := PacketPeerUDP.new()
	upstream.connect_to_host("127.0.0.1", port)
	var link := {"down": null, "up_q": [], "down_q": []}
	var pump := func() -> void:
		var now := Time.get_ticks_msec()
		listen.poll()
		if listen.is_connection_available():
			link.down = listen.take_connection()
		if link.down:
			while link.down.get_available_packet_count() > 0:
				link.up_q.append([now + DELAY_MS, link.down.get_packet()])
		while upstream.get_available_packet_count() > 0:
			link.down_q.append([now + DELAY_MS, upstream.get_packet()])
		while not link.up_q.is_empty() and link.up_q[0][0] <= now:
			upstream.put_packet(link.up_q.pop_front()[1])
		while link.down and not link.down_q.is_empty() and link.down_q[0][0] <= now:
			link.down.put_packet(link.down_q.pop_front()[1])
	process_frame.connect(pump)
	physics_frame.connect(pump)
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", proxy_port)
	cmp.multiplayer_peer = cpeer
	if not await _client_connected(smp, cpeer):
		printerr("FAIL respawn_snapback client did not connect")
		fail += 1
	else:
		var player_scene := load("res://Player/character_body_2d.tscn")
		var id := str(cpeer.get_unique_id())
		var death := Vector2(100, 100)
		var spawn := Vector2(400, 400)
		var s_copy = player_scene.instantiate()
		s_copy.name = id
		s_copy.position = death
		s_world.add_child(s_copy)
		var owner_copy = player_scene.instantiate()
		owner_copy.name = id
		owner_copy.position = death
		scene.get_node("World").add_child(owner_copy)
		s_copy.health.respawn_delay = 1000.0
		for i in 20:
			await physics_frame
		s_copy.health.take_damage(s_copy.health.max_health)
		var until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until and not owner_copy.health.is_dead():
			await physics_frame
		for i in 10:
			await physics_frame
		var stale: Vector2 = owner_copy.position
		s_copy.health._do_respawn.rpc(spawn, s_copy.health.respawn_count + 1)
		var reached := false
		var snapped := ""
		for f in 30:
			var at: Vector2 = s_copy.position
			var near_spawn := at.distance_to(spawn) < at.distance_to(stale)
			if near_spawn:
				reached = true
			elif reached and snapped == "":
				snapped = "frame %d at %s" % [f, at]
			await physics_frame
		if not reached:
			printerr("FAIL respawn_snapback server copy never reached the spawn (%s)" % s_copy.position)
			fail += 1
		if snapped != "":
			printerr("FAIL respawn_snapback server copy jumped back to the death spot (%s)" % snapped)
			fail += 1
		if owner_copy.position.distance_to(spawn) > 64.0 or s_copy.position.distance_to(owner_copy.position) > 64.0:
			printerr("FAIL respawn_snapback copies apart: owner %s, server %s" % [owner_copy.position, s_copy.position])
			fail += 1
		cpeer.close()
		for i in 3:
			await physics_frame
		s_copy.queue_free()
		owner_copy.queue_free()
		await process_frame
	process_frame.disconnect(pump)
	physics_frame.disconnect(pump)
	cpeer.close()
	speer.close()
	upstream.close()
	listen.stop()
	set_multiplayer(null, scene.get_path())
	set_multiplayer(null, server_root.get_path())
	scene.queue_free()
	server_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_player_respawn_no_snapback")
	return fail


func _test_player_respawn_hold_releases() -> int:
	## The server's copy of a respawned client-owned player holds the spawn
	## only until the owner's first update from after its respawn, wherever
	## the owner then walks: also when it died on the spawn itself, or died
	## near it and walks back past the death spot while the first updates
	## after its respawn are lost. A copy that joined after the owner had
	## already respawned must not show the death spot either.
	print("-- test_player_respawn_hold_releases")
	var fail := 0
	var spawn := Vector2(400, 400)
	fail += await _respawn_follow_case("died on the spawn", spawn, spawn, Vector2(3, 0), 0)
	fail += await _respawn_follow_case("died near the spawn, first updates lost",
			spawn + Vector2(-16, 0), spawn, Vector2(-3, 0), 80)
	fail += await _respawn_follow_case("observer joined after earlier respawns",
			spawn + Vector2(-20, 0), spawn, Vector2(3, 0), 0, 3)
	if fail == 0:
		print("PASS test_player_respawn_hold_releases")
	return fail


func _test_player_respawn_hold_before_first_sync() -> int:
	## A copy created just before its owner's next respawn: the respawn
	## arrives before the copy's first synced update, then a stale update
	## the owner sent before that respawn, then a fresh one. The copy must
	## hold the spawn through the stale update and follow the fresh one.
	print("-- test_player_respawn_hold_before_first_sync")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var copy = load("res://Player/character_body_2d.tscn").instantiate()
	copy.name = "2"  # owned by peer 2; this (offline) peer is the server
	scene.get_node("World").add_child(copy)
	copy.set_physics_process(false)
	var sync: MultiplayerSynchronizer = copy.get_node("MultiplayerSynchronizer")
	var death := Vector2(380, 400)
	var spawn := Vector2(400, 400)
	var n := 4  # the owner had respawned 3 times before this copy existed
	copy.position = death
	await physics_frame
	copy.health._do_respawn(spawn, n)
	copy.position = death  # stale update: sent before the owner saw respawn n
	copy.owner_respawns = n - 1
	sync.synchronized.emit()
	if copy.position != spawn:
		printerr("FAIL respawn_first_sync stale update shown: copy at %s, spawn %s" % [copy.position, spawn])
		fail += 1
	var fresh := spawn + Vector2(6, 0)
	copy.position = fresh  # fresh update: sent after the owner saw respawn n
	copy.owner_respawns = n
	sync.synchronized.emit()
	var next := spawn + Vector2(12, 0)
	copy.position = next
	sync.synchronized.emit()
	if copy.position != next:
		printerr("FAIL respawn_first_sync copy still held after the fresh update: at %s, owner %s" % [copy.position, next])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_player_respawn_hold_before_first_sync")
	return fail


func _test_respawn_teleport_ghosts() -> int:
	## A respawn moves a body, and the physics server only moves it at its
	## next step: for one tick a player who also just respawned still stands
	## where it died. The player respawning onto that spot must stay on the
	## spot it was sent to, not be pushed off it, or carried along when the
	## other body (its top taken for a floor) jumps to its own spot. A player
	## standing where a dead player lay must not be shoved when that one
	## respawns elsewhere. Real player scenes, the local one the owner.
	print("-- test_respawn_teleport_ghosts")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world: Node = scene.get_node("World")
	var spot := Vector2(4000, 4000)  # off the map: no walls, only the two bodies
	# [label, where the local player died (null: it stays alive there),
	#  where the other died, where each respawns]
	var cases := [
		["onto the other's death spot", spot + Vector2(-32, 0), spot, spot, spot + Vector2(32, 0)],
		["just above the other's death spot", spot + Vector2(-32, 0), spot + Vector2(0, 6), spot, spot + Vector2(32, 6)],
		["side by side with it", spot + Vector2(-32, 0), spot + Vector2(5, 0), spot, spot + Vector2(32, 0)],
		["standing where it lay dead", null, spot, spot, spot + Vector2(32, 0)],
	]
	for c in cases:
		var label: String = c[0]
		var me = load("res://Player/character_body_2d.tscn").instantiate()
		me.name = str(scene.multiplayer.get_unique_id())
		var other = load("res://Player/character_body_2d.tscn").instantiate()
		other.name = "2"  # a copy: only its owner would move it
		world.add_child(me)
		world.add_child(other)
		for p in [me, other]:
			p.health.respawn_delay = 1000.0  # respawned by hand below
		me.position = c[1] if c[1] != null else c[3]
		other.position = c[2]
		for i in 2:
			await physics_frame
		other.health.set_health_now(0)
		if c[1] != null:
			me.health.set_health_now(0)
		for i in 3:
			await physics_frame
		if c[1] == null:
			me.position = c[3]  # walks onto the dead body's spot (no collision)
			for i in 3:
				await physics_frame
		# The server's batch: both in one frame, as one packet delivers them.
		await process_frame
		if c[1] != null:
			me.health._do_respawn(c[3], 1)
		other.health._do_respawn(c[4], 1)
		var worst := 0.0
		for i in 10:
			await physics_frame
			worst = maxf(worst, (me.position as Vector2).distance_to(c[3]))
		if worst > 0.5 or not (other.position as Vector2).is_equal_approx(c[4]):
			printerr("FAIL respawn_teleport_ghosts %s: the local player ends at %s, up to %.1f px off its spot %s; the other at %s, sent to %s"
					% [label, me.position, worst, c[3], other.position, c[4]])
			fail += 1
		if me.body_shape.disabled or other.body_shape.disabled:
			printerr("FAIL respawn_teleport_ghosts %s: collision still off after the respawn (%s, %s)"
					% [label, me.body_shape.disabled, other.body_shape.disabled])
			fail += 1
		me.free()
		other.free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_respawn_teleport_ghosts")
	return fail
