extends "res://tests/helpers/test_helpers.gd"
## Points awards, the score HUD and points sync (Scripts/points.gd).


func _test_points_award() -> int:
	## Points.award adds to one player's total with a reason, ignores
	## non-positive amounts and bad ids, and the ScoreHud shows only its own
	## player's total. Offline, so this peer is the server.
	print("-- test_points_award")
	var fail := 0
	var points := Points.new()
	points.name = "Points"
	root.add_child(points)
	var hud := ScoreHud.new()
	root.add_child(hud)
	hud.bind(points, 7)
	var seen: Array = []
	points.total_changed.connect(func(peer_id: int, total: int, amount: int, reason: String) -> void:
		seen.append([peer_id, total, amount, reason]))
	if not points.award(7, 3, "test") or not points.award(7, 2, "test") or not points.award(9, 4, "other"):
		printerr("FAIL points_award a valid award was refused")
		fail += 1
	if points.award(7, 0, "zero") or points.award(7, -5, "negative") or points.award(0, 5, "no player"):
		printerr("FAIL points_award accepted a zero, negative or id-0 award")
		fail += 1
	if points.total_of(7) != 5 or points.total_of(9) != 4 or points.total_of(11) != 0:
		printerr("FAIL points_award totals 7=%s 9=%s 11=%s, want 5, 4, 0"
				% [points.total_of(7), points.total_of(9), points.total_of(11)])
		fail += 1
	if seen != [[7, 3, 3, "test"], [7, 5, 2, "test"], [9, 4, 4, "other"]]:
		printerr("FAIL points_award signals %s" % [seen])
		fail += 1
	if hud.text != "5 pts" or not hud.visible:
		printerr("FAIL points_award HUD shows '%s' (visible %s), want own total '5 pts'" % [hud.text, hud.visible])
		fail += 1
	hud.queue_free()
	points.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_award")
	return fail


func _test_points_hud_in_scene() -> int:
	## In the real main scene, the local player's spawn shows the score
	## counter under the hearts, and an award to that player updates it.
	print("-- test_points_hud_in_scene")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var me: int = scene.multiplayer.get_unique_id()
	scene.add_player(me)
	await process_frame
	var hud: ScoreHud = scene.get_node("CanvasLayer1/ScoreHud")
	var hearts: Control = scene.get_node("CanvasLayer1/HeartsHud")
	if not hud.visible or hud.text != "0 pts":
		printerr("FAIL points_hud_in_scene counter visible %s, text '%s'" % [hud.visible, hud.text])
		fail += 1
	if hud.position.y < hearts.position.y + hearts.size.y * hearts.scale.y or hud.scale != hearts.scale:
		printerr("FAIL points_hud_in_scene counter at %s x%s, hearts at %s size %s x%s"
				% [hud.position, hud.scale, hearts.position, hearts.size, hearts.scale])
		fail += 1
	scene.get_node("Points").award(me, 4, "test")
	if hud.text != "4 pts":
		printerr("FAIL points_hud_in_scene counter '%s' after an award of 4" % hud.text)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_hud_in_scene")
	return fail


func _test_points_sync() -> int:
	## Two peers over ENet loopback: totals awarded before the client joins
	## reach it as it connects (late join), later awards reach it with their
	## reason, and the client cannot award points itself.
	print("-- test_points_sync")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL points_sync found no free UDP port")
		return 1
	var server_root := Node.new()
	server_root.name = "PointsServer"
	var client_root := Node.new()
	client_root.name = "PointsClient"
	root.add_child(server_root)
	root.add_child(client_root)
	var smp := SceneMultiplayer.new()
	var cmp := SceneMultiplayer.new()
	set_multiplayer(smp, server_root.get_path())
	set_multiplayer(cmp, client_root.get_path())
	var s_points := Points.new()
	s_points.name = "Points"
	server_root.add_child(s_points)
	var c_points := Points.new()
	c_points.name = "Points"
	client_root.add_child(c_points)
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer
	s_points.award(1, 6, "before join")
	var c_seen: Array = []
	c_points.total_changed.connect(func(peer_id: int, total: int, _amount: int, reason: String) -> void:
		c_seen.append([peer_id, total, reason]))

	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	cmp.multiplayer_peer = cpeer
	var me := cpeer.get_unique_id()
	var wait := func(cond: Callable) -> bool:
		var until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	if not await _client_connected(smp, cpeer):
		printerr("FAIL points_sync client did not connect")
		fail += 1
	else:
		if not await wait.call(func() -> bool: return c_points.total_of(1) == 6):
			printerr("FAIL points_sync late joiner sees %s for the host, server 6" % c_points.total_of(1))
			fail += 1
		if c_points.award(me, 50, "cheat") or c_points.total_of(me) != 0:
			printerr("FAIL points_sync client awarded itself (%s)" % c_points.total_of(me))
			fail += 1
		s_points.award(me, 3, "discovery")
		if not await wait.call(func() -> bool: return c_points.total_of(me) == 3):
			printerr("FAIL points_sync client total %s, server %s" % [c_points.total_of(me), s_points.total_of(me)])
			fail += 1
		if c_seen != [[me, 3, "discovery"]]:
			printerr("FAIL points_sync client signals %s" % [c_seen])
			fail += 1
		if s_points.total_of(me) != 3 or s_points.total_of(1) != 6:
			printerr("FAIL points_sync server totals %s / %s" % [s_points.total_of(me), s_points.total_of(1)])
			fail += 1

	cpeer.close()
	speer.close()
	set_multiplayer(null, client_root.get_path())
	set_multiplayer(null, server_root.get_path())
	server_root.queue_free()
	client_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_sync")
	return fail


func _test_points_mob_kill() -> int:
	## Kill points by type (slime 5, crab 8, piglet 10) go to the player
	## whose hit kills the mob, once: earlier hits by another player and hits
	## on a dying mob pay nothing, and a hit with no known player pays no one.
	print("-- test_points_mob_kill")
	var fail := 0
	var want_values := {MobCatalog.SLIME: 5, MobCatalog.CRAB: 8, MobCatalog.PIGLET: 10}
	if Points.MOB_KILL_POINTS != want_values or Points.MOB_KILL_POINTS.size() != MobCatalog.names().size():
		printerr("FAIL points_mob_kill values %s for types %s" % [Points.MOB_KILL_POINTS, MobCatalog.names()])
		fail += 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("Discovery").set_physics_process(false)  # only kill points here
	var points: Points = scene.get_node("Points")
	var mobs_root: Node = scene.get_node("World/Mobs")
	var paid: Array = []
	points.total_changed.connect(func(peer_id: int, _total: int, amount: int, reason: String) -> void:
		paid.append([peer_id, amount, reason]))
	var want_paid: Array = []
	for t in MobCatalog.names():
		var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
		mob.setup(t, Vector2(4000, 4000), 7)
		mobs_root.add_child(mob)
		mob.set_physics_process(false)  # hits by hand below
		# Peer 2 lands every hit but the last; peer 1 lands the killing hit.
		while mob.hp > 1:
			mob.take_hit(2)
			mob.state = Mob.State.IDLE  # end the hurt window
		mob.take_hit(1)
		mob.take_hit(2)  # dying: ignored
		mob.take_hit(1)
		want_paid.append([1, want_values[t], "mob_kill"])
		mob.free()
	var unknown: Mob = load("res://Mobs/mob.tscn").instantiate()
	unknown.setup(MobCatalog.SLIME, Vector2(4000, 4000), 7)
	mobs_root.add_child(unknown)
	unknown.set_physics_process(false)
	unknown.take_hit()
	unknown.state = Mob.State.IDLE
	unknown.take_hit()  # killed by an unknown hitter
	unknown.free()
	if paid != want_paid:
		printerr("FAIL points_mob_kill awards %s, want %s" % [paid, want_paid])
		fail += 1
	if points.total_of(2) != 0:
		printerr("FAIL points_mob_kill earlier hitter got %s" % points.total_of(2))
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_mob_kill")
	return fail
