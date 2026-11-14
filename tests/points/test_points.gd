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


func _test_points_scoreboard_two_players() -> int:
	## After the host awards points, both peers' scoreboards list every
	## connected player with the same totals, highest first (#509).
	print("-- test_points_scoreboard_two_players")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL points_scoreboard_two_players found no free UDP port")
		return 1
	var server_root := Node.new()
	server_root.name = "ScoreboardServer"
	var client_root := Node.new()
	client_root.name = "ScoreboardClient"
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
	var s_panel := ScoreboardPanel.new()
	server_root.add_child(s_panel)
	var c_panel := ScoreboardPanel.new()
	client_root.add_child(c_panel)
	s_panel.bind(s_points, Points.SERVER_ID)
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	cmp.multiplayer_peer = cpeer
	var me := cpeer.get_unique_id()
	c_panel.bind(c_points, me)
	var wait := func(cond: Callable) -> bool:
		var until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	if not await _client_connected(smp, cpeer):
		printerr("FAIL points_scoreboard_two_players client did not connect")
		fail += 1
	else:
		if not s_points.award(Points.SERVER_ID, 10, "test") or not s_points.award(me, 4, "test"):
			printerr("FAIL points_scoreboard_two_players host refused an award")
			fail += 1
		elif not await wait.call(func() -> bool: return c_points.total_of(me) == 4):
			printerr("FAIL points_scoreboard_two_players client total %s, want 4" % c_points.total_of(me))
			fail += 1
		else:
			var want := [[Points.SERVER_ID, 10], [me, 4]]
			if s_panel.sorted_rows() != want or c_panel.sorted_rows() != want:
				printerr("FAIL points_scoreboard_two_players host %s client %s, want %s"
						% [s_panel.sorted_rows(), c_panel.sorted_rows(), want])
				fail += 1
			s_points.award(me, 12, "test")
			if not await wait.call(func() -> bool: return c_points.total_of(me) == 16):
				printerr("FAIL points_scoreboard_two_players client total %s after bump, want 16"
						% c_points.total_of(me))
				fail += 1
			want = [[me, 16], [Points.SERVER_ID, 10]]
			if s_panel.sorted_rows() != want or c_panel.sorted_rows() != want:
				printerr("FAIL points_scoreboard_two_players after bump host %s client %s, want %s"
						% [s_panel.sorted_rows(), c_panel.sorted_rows(), want])
				fail += 1
	cpeer.close()
	speer.close()
	set_multiplayer(null, client_root.get_path())
	set_multiplayer(null, server_root.get_path())
	server_root.queue_free()
	client_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_scoreboard_two_players")
	return fail


func _test_points_scoreboard_late_join() -> int:
	## A joiner's scoreboard lists every connected player's current total
	## after the join snapshot (#509).
	print("-- test_points_scoreboard_late_join")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL points_scoreboard_late_join found no free UDP port")
		return 1
	var server_root := Node.new()
	server_root.name = "ScoreboardLateServer"
	var client_root := Node.new()
	client_root.name = "ScoreboardLateClient"
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
	s_points.award(Points.SERVER_ID, 7, "before join")
	s_points.award(99, 50, "offline")  ## stale total, not connected
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
		printerr("FAIL points_scoreboard_late_join client did not connect")
		fail += 1
	elif not await wait.call(func() -> bool: return c_points.total_of(Points.SERVER_ID) == 7):
		printerr("FAIL points_scoreboard_late_join client host total %s, want 7" % c_points.total_of(Points.SERVER_ID))
		fail += 1
	else:
		var c_panel := ScoreboardPanel.new()
		client_root.add_child(c_panel)
		c_panel.bind(c_points, me)
		await process_frame
		var want := [[Points.SERVER_ID, 7], [me, 0]]
		if c_panel.sorted_rows() != want:
			printerr("FAIL points_scoreboard_late_join joiner rows %s, want %s" % [c_panel.sorted_rows(), want])
			fail += 1
		s_points.award(me, 2, "after join")
		if not await wait.call(func() -> bool: return c_points.total_of(me) == 2):
			printerr("FAIL points_scoreboard_late_join client total %s, want 2" % c_points.total_of(me))
			fail += 1
		want = [[Points.SERVER_ID, 7], [me, 2]]
		var s_panel := ScoreboardPanel.new()
		server_root.add_child(s_panel)
		s_panel.bind(s_points, Points.SERVER_ID)
		await process_frame
		if s_panel.sorted_rows() != want or c_panel.sorted_rows() != want:
			printerr("FAIL points_scoreboard_late_join after award host %s client %s, want %s"
					% [s_panel.sorted_rows(), c_panel.sorted_rows(), want])
			fail += 1
	cpeer.close()
	speer.close()
	set_multiplayer(null, client_root.get_path())
	set_multiplayer(null, server_root.get_path())
	server_root.queue_free()
	client_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_scoreboard_late_join")
	return fail


func _test_points_scoreboard_four_players() -> int:
	## Four connected peers see join-order names with flag colours, not raw
	## peer ids; the panel height stays within the 480x270 HUD band.
	print("-- test_points_scoreboard_four_players")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL points_scoreboard_four_players found no free UDP port")
		return 1
	var server_root := Node.new()
	server_root.name = "ScoreboardFourServer"
	root.add_child(server_root)
	var smp := SceneMultiplayer.new()
	set_multiplayer(smp, server_root.get_path())
	var s_points := Points.new()
	s_points.name = "Points"
	server_root.add_child(s_points)
	var s_panel := ScoreboardPanel.new()
	server_root.add_child(s_panel)
	s_panel.bind(s_points, Points.SERVER_ID)
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer
	var clients: Array = []
	var wait := func(cond: Callable) -> bool:
		var until := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	for i in 3:
		var client_root := Node.new()
		client_root.name = "ScoreboardFourClient%d" % (i + 1)
		root.add_child(client_root)
		var cmp := SceneMultiplayer.new()
		set_multiplayer(cmp, client_root.get_path())
		var c_points := Points.new()
		c_points.name = "Points"
		client_root.add_child(c_points)
		var cpeer := ENetMultiplayerPeer.new()
		cpeer.create_client("127.0.0.1", port)
		cmp.multiplayer_peer = cpeer
		clients.append({"root": client_root, "peer": cpeer, "points": c_points, "api": cmp})
		if not await _client_connected(smp, cpeer):
			printerr("FAIL points_scoreboard_four_players client %d did not connect" % (i + 1))
			fail += 1
			break
	if fail == 0:
		var ids := [Points.SERVER_ID]
		for entry in clients:
			ids.append(entry["peer"].get_unique_id())
		for peer_id in ids:
			s_points.award(peer_id, peer_id % 10, "test")
		if not await wait.call(func() -> bool: return s_panel.sorted_rows().size() == 4):
			printerr("FAIL points_scoreboard_four_players rows %s, want 4" % s_panel.sorted_rows())
			fail += 1
		var lines := s_panel.display_lines()
		if lines.size() != 4:
			printerr("FAIL points_scoreboard_four_players display %s" % lines)
			fail += 1
		for line in lines:
			var t := str(line)
			if not t.begins_with("You") and not t.begins_with("Player"):
				printerr("FAIL points_scoreboard_four_players unreadable label: %s" % t)
				fail += 1
			for entry in clients:
				var huge := str(entry["peer"].get_unique_id())
				if t.find(huge) >= 0:
					printerr("FAIL points_scoreboard_four_players label used a raw id: %s" % t)
					fail += 1
		if fail == 0 and s_panel.custom_minimum_size.y > 58.0:
			printerr("FAIL points_scoreboard_four_players panel art height %s, want <= 58"
					% s_panel.custom_minimum_size.y)
			fail += 1
	for entry in clients:
		entry["peer"].close()
		set_multiplayer(null, entry["root"].get_path())
		entry["root"].queue_free()
	speer.close()
	set_multiplayer(null, server_root.get_path())
	server_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_scoreboard_four_players")
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
		mob.name = "mob_%s" % t
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
	unknown.name = "mob_unknown"
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


func _test_points_mob_kill_once() -> int:
	## The same mob id pays once on the host and on a client. award_kill sends
	## the award message each time it is called; the second delivery leaves
	## both totals and the total_changed signal unchanged. Another mob id
	## still pays, and after the server clears kill credits the first id can
	## pay once more.
	print("-- test_points_mob_kill_once")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL points_mob_kill_once found no free UDP port")
		return 1
	var server_root := Node.new()
	server_root.name = "KillOnceServer"
	var client_root := Node.new()
	client_root.name = "KillOnceClient"
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
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	cmp.multiplayer_peer = cpeer
	var me := cpeer.get_unique_id()
	var s_seen: Array = []
	var c_seen: Array = []
	s_points.total_changed.connect(func(peer_id: int, total: int, amount: int, reason: String) -> void:
		s_seen.append([peer_id, total, amount, reason]))
	c_points.total_changed.connect(func(peer_id: int, total: int, amount: int, reason: String) -> void:
		c_seen.append([peer_id, total, amount, reason]))
	var wait := func(cond: Callable) -> bool:
		var until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	if not await _client_connected(smp, cpeer):
		printerr("FAIL points_mob_kill_once client did not connect")
		fail += 1
	else:
		if c_points.award_kill(me, "mob_0", 8):
			printerr("FAIL points_mob_kill_once client awarded a kill itself")
			fail += 1
		if not s_points.award_kill(me, "mob_0", 8):
			printerr("FAIL points_mob_kill_once host refused the first mob_0 award")
			fail += 1
		if s_points.award_kill(me, "mob_0", 8):
			printerr("FAIL points_mob_kill_once host accepted a second mob_0 award")
			fail += 1
		if s_points.total_of(me) != 8 or s_seen != [[me, 8, 8, "mob_kill"]]:
			printerr("FAIL points_mob_kill_once host total %s, signals %s"
					% [s_points.total_of(me), s_seen])
			fail += 1
		if not await wait.call(func() -> bool: return c_points.total_of(me) == 8):
			printerr("FAIL points_mob_kill_once client total %s after two mob_0 messages, want 8"
					% c_points.total_of(me))
			fail += 1
		for i in 30:  # a second delivery would land in these frames
			await process_frame
		if c_points.total_of(me) != 8 or c_seen != [[me, 8, 8, "mob_kill"]]:
			printerr("FAIL points_mob_kill_once client total %s, signals %s after the repeat"
					% [c_points.total_of(me), c_seen])
			fail += 1
		if not s_points.award_kill(me, "mob_1", 5) or s_points.total_of(me) != 13:
			printerr("FAIL points_mob_kill_once a second mob paid %s, want 13" % s_points.total_of(me))
			fail += 1
		if not await wait.call(func() -> bool: return c_points.total_of(me) == 13 and c_seen.size() == 2):
			printerr("FAIL points_mob_kill_once client after mob_1: total %s, signals %s"
					% [c_points.total_of(me), c_seen])
			fail += 1
		s_points.clear_kill_credits()
		if not s_points.award_kill(me, "mob_0", 8) or s_points.award_kill(me, "mob_0", 8):
			printerr("FAIL points_mob_kill_once after a clear, mob_0 did not pay exactly once (total %s)"
					% s_points.total_of(me))
			fail += 1
		if s_points.total_of(me) != 21:
			printerr("FAIL points_mob_kill_once host total %s after the cleared mob_0, want 21"
					% s_points.total_of(me))
			fail += 1
		if not await wait.call(func() -> bool: return c_points.total_of(me) == 21):
			printerr("FAIL points_mob_kill_once client total %s after the cleared mob_0, want 21"
					% c_points.total_of(me))
			fail += 1
		for i in 30:
			await process_frame
		if c_points.total_of(me) != 21 or c_seen != [[me, 8, 8, "mob_kill"], [me, 13, 5, "mob_kill"], [me, 21, 8, "mob_kill"]]:
			printerr("FAIL points_mob_kill_once client ended at %s, signals %s"
					% [c_points.total_of(me), c_seen])
			fail += 1

	cpeer.close()
	speer.close()
	set_multiplayer(null, client_root.get_path())
	set_multiplayer(null, server_root.get_path())
	server_root.queue_free()
	client_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_points_mob_kill_once")
	return fail


func _test_points_kill_late_join() -> int:
	## A dedicated server credits mob_0, frees it, then a joiner arrives.
	## The joiner must already have the map when the kill snapshot arrives:
	## that list used to be the first reliable packet of the join. It must
	## also get its player, the host's total and every remaining mob.
	## Respawning the mob set while the joiner is connected must leave it in
	## the match with the new ids, and a second joiner must get the map
	## before the snapshot too.
	print("-- test_points_kill_late_join")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL points_kill_late_join found no free UDP port")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	if scene.setup_server(root.get_node("MapGen").params, port, false) != OK:
		printerr("FAIL points_kill_late_join server did not listen")
		scene.queue_free()
		return 1
	var points: Points = scene.get_node("Points")
	var mob: Mob = scene.get_node_or_null("World/Mobs/mob_0")
	if mob == null:
		printerr("FAIL points_kill_late_join no mob_0")
		_close_scene(scene)
		return 1
	while mob.hp > 1:
		mob.take_hit(1)
		mob.state = Mob.State.IDLE
	mob.take_hit(1)
	var paid := points.total_of(1)
	if paid <= 0:
		printerr("FAIL points_kill_late_join host total %s after killing mob_0" % paid)
		fail += 1
	mob.queue_free()
	await process_frame
	await process_frame
	var server_mobs := _mob_names(scene)
	if server_mobs.has("mob_0"):
		printerr("FAIL points_kill_late_join mob_0 still on the server after it died")
		fail += 1
	var dir := OS.get_user_data_dir().path_join("kill_join_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var pids: Array[int] = []
	var start_joiner := func(i: int) -> String:
		var out := dir.path_join("p%d.json" % i)
		pids.append(OS.create_process(OS.get_executable_path(), [
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/late_join_probe.gd", "--",
			"--port=%d" % port, "--out=" + out,
		]))
		return out
	var read := func(path: String) -> Dictionary:
		var text := FileAccess.get_file_as_string(path)
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var wait := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	var joined := func(path: String) -> bool:
		var s: Dictionary = read.call(path)
		return s.get("origin") != null and s.get("players", {}).has(s.get("id"))
	if fail == 0:
		var first: String = start_joiner.call(1)
		if not await wait.call(func() -> bool:
			var s: Dictionary = read.call(first)
			return joined.call(first) and s.get("host_points") == paid \
					and s.get("mobs") == server_mobs, 8000):
			printerr("FAIL points_kill_late_join first joiner did not get the map, the kill total and the mobs: %s"
					% read.call(first))
			fail += 1
		elif read.call(first).get("points_before_map"):
			printerr("FAIL points_kill_late_join kill snapshot arrived before the map: %s" % read.call(first))
			fail += 1
		else:
			scene.spawn_mobs()
			await process_frame
			await process_frame
			server_mobs = _mob_names(scene)
			if server_mobs.is_empty() or not points.total_of(1) == paid:
				printerr("FAIL points_kill_late_join after respawn mobs %s host total %s"
						% [server_mobs, points.total_of(1)])
				fail += 1
			elif not await wait.call(func() -> bool:
				var s: Dictionary = read.call(first)
				return joined.call(first) and s.get("mobs") == server_mobs \
						and s.get("host_points") == paid, 8000):
				printerr("FAIL points_kill_late_join joiner lost the match or the new mobs after respawn: %s server %s"
						% [read.call(first), server_mobs])
				fail += 1
			elif read.call(first).get("points_before_map"):
				printerr("FAIL points_kill_late_join kill snapshot arrived before the map: %s" % read.call(first))
				fail += 1
			else:
				var second: String = start_joiner.call(2)
				if not await wait.call(func() -> bool:
					var s: Dictionary = read.call(second)
					return joined.call(second) and s.get("mobs") == server_mobs \
							and s.get("host_points") == paid, 8000):
					printerr("FAIL points_kill_late_join late joiner after the respawn did not get the map and mobs: %s"
							% read.call(second))
					fail += 1
				elif read.call(second).get("points_before_map"):
					printerr("FAIL points_kill_late_join late joiner kill snapshot arrived before the map: %s"
							% read.call(second))
					fail += 1
				elif points.award_kill(1, "mob_0", 8) and points.award_kill(1, "mob_0", 8):
					printerr("FAIL points_kill_late_join respawned mob_0 paid twice")
					fail += 1
				elif points.total_of(1) != paid + 8:
					printerr("FAIL points_kill_late_join host total %s after the new mob_0, want %s"
							% [points.total_of(1), paid + 8])
					fail += 1
				elif not await wait.call(func() -> bool:
					return read.call(second).get("host_points") == paid + 8 \
							and read.call(first).get("host_points") == paid + 8, 8000):
					printerr("FAIL points_kill_late_join peers did not see the new mob_0 once: first %s second %s"
							% [read.call(first).get("host_points"), read.call(second).get("host_points")])
					fail += 1
	for out in [dir.path_join("p1.json"), dir.path_join("p2.json")]:
		if FileAccess.file_exists(out):
			FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	await wait.call(func() -> bool:
		for pid in pids:
			if OS.is_process_running(pid):
				return false
		return true, 5000)
	for pid in pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_close_scene(scene)
	_remove_dir(dir)
	if fail == 0:
		print("PASS test_points_kill_late_join")
	return fail


func _mob_names(scene: Node) -> Array:
	var names: Array = []
	for child in scene.get_node("World/Mobs").get_children():
		names.append(str(child.name))
	names.sort()
	return names


func _close_scene(scene: Node) -> void:
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
