extends "res://tests/helpers/test_helpers.gd"
## Players hitting mobs with the sword.


func _test_mob_sword() -> int:
	## A swing over a mob costs it 1 HP once per swing and plays the hurt row;
	## a sword resting on it outside a swing does nothing; the last hit plays
	## the hurt row, then the puff, then frees the mob.
	print("-- test_mob_sword")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	scene.spawn_mobs()
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = "1"
	scene.get_node("World").add_child(player)
	player.health.max_health = 1000  # contact damage is not under test here
	player.health.set_health_now(1000)
	for t in MobCatalog.names():
		if MobCatalog.stat(t, "hp") < 2:
			printerr("FAIL mob_sword %s has %s HP" % [t, MobCatalog.stat(t, "hp")])
			fail += 1
	var mob: Mob = null
	for m in scene.get_node("World/Mobs").mobs():
		if m.hp == 2:
			mob = m
			break
	if mob == null:
		printerr("FAIL mob_sword no 2 HP mob on seed 42")
		scene.queue_free()
		return 1
	var label := "%s %s" % [mob.name, mob.mob_type]
	# Sword resting on the mob, no swing.
	for i in 10:
		_sword_on(player, mob)
		await physics_frame
	if mob.hp != 2 or mob.state == Mob.State.HURT:
		printerr("FAIL mob_sword %s hurt without a swing (hp %s)" % [label, mob.hp])
		fail += 1
	# One swing, held on the mob for the whole swing: one hit.
	player.attack_animation()
	var saw_hurt := false
	while player.isAttacking:
		_sword_on(player, mob)
		await physics_frame
		saw_hurt = saw_hurt or (mob.state == Mob.State.HURT and mob.anim_name() == "hurt")
	for i in int(Mob.HURT_TIME * 60) + 10:
		_sword_on(player, mob)
		await physics_frame
	if mob.hp != 1 or not saw_hurt:
		printerr("FAIL mob_sword %s after one swing: hp %s, hurt shown %s" % [label, mob.hp, saw_hurt])
		fail += 1
	if mob.state == Mob.State.HURT:
		printerr("FAIL mob_sword %s stayed hurt past HURT_TIME" % label)
		fail += 1
	# Second swing: dies, hurt row, then the puff, then gone.
	player.attack_animation()
	var saw_dying := false
	var saw_puff := false
	var deadline := Time.get_ticks_msec() + 5000
	while is_instance_valid(mob) and Time.get_ticks_msec() < deadline:
		_sword_on(player, mob)
		await process_frame
		if not is_instance_valid(mob):
			break
		saw_dying = saw_dying or mob.state == Mob.State.DYING
		saw_puff = saw_puff or (mob.puff.visible and not mob.sprite.visible)
	if is_instance_valid(mob):
		printerr("FAIL mob_sword %s not freed after the last hit (hp %s, state %s)" % [label, mob.hp, mob.state])
		fail += 1
	elif not saw_dying or not saw_puff:
		printerr("FAIL mob_sword %s died without the hurt row and puff (%s, %s)" % [label, saw_dying, saw_puff])
		fail += 1
	if fail == 0:
		print("PASS test_mob_sword (%s)" % label)
	scene.queue_free()
	return fail


func _test_mob_sword_two_players() -> int:
	## A client of a dedicated server swings at a mob until it dies; the host
	## decides the hits, and the client sees the hurt and dying states, then
	## the mob is removed on the client, and the client is paid the mob's
	## kill points once.
	print("-- test_mob_sword_two_players")
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL mob_sword_two_players found no free UDP port")
		return 1
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("FAIL mob_sword_two_players could not start the server process")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var mobs_node: MobSpawner = scene.get_node("World/Mobs")
	var kills: Array = []  # [peer, amount] of each mob_kill award seen on the client
	scene.get_node("Points").total_changed.connect(
			func(peer_id: int, _total: int, amount: int, reason: String) -> void:
				if reason == "mob_kill":
					kills.append([peer_id, amount]))
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
	if player and scene.world_params and not mobs_node.mobs().is_empty():
		mob = mobs_node.mobs()[0]
	var label := str(mob.name) if mob else ""
	var mob_type := mob.mob_type if mob else ""
	if mob == null:
		printerr("FAIL mob_sword_two_players no player or mobs on the client")
		fail += 1
	else:
		var seen := {}
		var next_swing := 0
		deadline = Time.get_ticks_msec() + 20000
		while is_instance_valid(mob) and Time.get_ticks_msec() < deadline:
			_sword_on(player, mob)
			seen[mob.state] = true
			if Time.get_ticks_msec() >= next_swing and not player.isAttacking:
				player.attack_animation.rpc()
				next_swing = Time.get_ticks_msec() + 600
			await process_frame
		if is_instance_valid(mob):
			printerr("FAIL mob_sword_two_players %s still alive on the client (state %s)" % [label, mob.state])
			fail += 1
		elif not seen.has(Mob.State.HURT) or not seen.has(Mob.State.DYING):
			printerr("FAIL mob_sword_two_players %s states seen on the client: %s" % [label, seen.keys()])
			fail += 1
		var want := [[scene.multiplayer.get_unique_id(), Points.MOB_KILL_POINTS[mob_type]]]
		deadline = Time.get_ticks_msec() + 3000
		while kills.size() < want.size() and Time.get_ticks_msec() < deadline:
			await process_frame
		for i in 30:  # a second award would arrive with these frames
			await process_frame
		if kills != want:
			printerr("FAIL mob_sword_two_players %s kill awards on the client %s, want %s" % [label, kills, want])
			fail += 1
	OS.kill(pid)
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	if fail == 0:
		print("PASS test_mob_sword_two_players (%s)" % label)
	return fail


func _test_mob_sword_two_attackers() -> int:
	## Two players' swings in one mob hurt window: the second swing is not
	## used up while the mob is hurt, and lands once the window ends. Also
	## checks the contact box comes from the player scene's body shape.
	print("-- test_mob_sword_two_attackers")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	scene.spawn_mobs()
	var players: Array = []
	for n in ["1", "2"]:
		var p = load("res://Player/character_body_2d.tscn").instantiate()
		p.name = n
		scene.get_node("World").add_child(p)
		p.set_physics_process(false)  # positions are set by the test
		p.health.max_health = 1000  # contact damage is not under test here
		p.health.set_health_now(1000)
		players.append(p)
	var a = players[0]
	var b = players[1]
	var shape: CollisionShape2D = a.get_node("CollisionShape2D")
	var size: Vector2 = shape.shape.size
	var want := Rect2(a.position + shape.position - size * 0.5, size)
	if Mob.player_box(a) != want or Mob.player_box(_contact_player(scene.get_node("World"))).size != size:
		printerr("FAIL mob_sword_two_attackers player box %s, want %s from the scene" % [Mob.player_box(a), want])
		fail += 1
	var mob: Mob = null
	for m in scene.get_node("World/Mobs").mobs():
		if m.hp == 2:
			mob = m
			break
	if mob == null:
		printerr("FAIL mob_sword_two_attackers no 2 HP mob on seed 42")
		scene.queue_free()
		return 1
	var label := "%s %s" % [mob.name, mob.mob_type]
	# A swing held on: the sword's shape on, sword_active() true, as mid-attack.
	var swing := func(p, on: bool) -> void:
		p.isAttacking = on
		p.sword_shape.disabled = not on
	# a's swing lands: the mob is hurt and a moves away.
	swing.call(a, true)
	var frames := 0
	while mob.state != Mob.State.HURT and frames < 30:
		_sword_on(a, mob)
		await physics_frame
		frames += 1
	swing.call(a, false)
	a.position = mob.position + Vector2(200, 0)
	if mob.hp != 1 or mob.state != Mob.State.HURT:
		printerr("FAIL mob_sword_two_attackers %s first swing: hp %s, state %s" % [label, mob.hp, mob.state])
		fail += 1
	# b swings into the hurt window and holds past its end: one hit, after the window.
	swing.call(b, true)
	for i in int(Mob.HURT_TIME * Engine.physics_ticks_per_second) + 15:
		if not is_instance_valid(mob):
			break
		_sword_on(b, mob)
		await physics_frame
	swing.call(b, false)
	if not is_instance_valid(mob) or mob.hp != 0 or mob.state != Mob.State.DYING:
		printerr("FAIL mob_sword_two_attackers %s second player's swing was used up in the hurt window (hp %s)"
				% [label, mob.hp if is_instance_valid(mob) else "freed"])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_mob_sword_two_attackers (%s)" % label)
	return fail
