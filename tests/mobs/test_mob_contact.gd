extends "res://tests/helpers/test_helpers.gd"
## Mob contact damage.


func _test_mob_contact() -> int:
	## Touching a mob costs a living player CONTACT_DAMAGE half-hearts; the
	## player's invulnerability spaces out repeat hits; the mob pauses after a
	## hit; dead players take no damage and are not chased.
	print("-- test_mob_contact")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	scene.spawn_mobs()
	var mobs: Array = scene.get_node("World/Mobs").mobs()
	var player := _contact_player(scene.get_node("World"))
	var health: PlayerHealth = player.get_node("Health")
	var dt := 1.0 / 45.0
	var fail := 0
	if mobs.is_empty():
		printerr("FAIL mob_contact no mobs on seed 42")
		scene.queue_free()
		return 1
	var mob: Mob = mobs[0]
	var full := health.max_health
	# Out of reach: no damage.
	player.position = mob.position + Vector2(mob.contact_box().size.x + 8, 0)
	mob.think(dt)
	if health.health != full:
		printerr("FAIL mob_contact hurt a player %s px away" % mob.position.distance_to(player.position))
		fail += 1
	# Touching: one hit, then the mob stands still for HIT_PAUSE.
	player.position = mob.position
	mob.think(dt)
	if health.health != full - Mob.CONTACT_DAMAGE:
		printerr("FAIL mob_contact touch left health at %s of %s" % [health.health, full])
		fail += 1
	player.position = mob.position + Vector2(0, 40)
	var at := mob.position
	for tick in range(int(Mob.HIT_PAUSE / dt) - 2):
		mob.think(dt)
	if mob.position != at:
		printerr("FAIL mob_contact mob moved during its hit pause")
		fail += 1
	# Still touching while invulnerable: no second hit until it runs out.
	player.position = mob.position
	for tick in range(int(health.invulnerable_time * 0.5 / dt)):
		health.advance(dt)
		mob.think(dt)
		player.position = mob.position
	if health.health != full - Mob.CONTACT_DAMAGE:
		printerr("FAIL mob_contact hit again during invulnerability (health %s)" % health.health)
		fail += 1
	for tick in range(int(health.invulnerable_time / dt) + 2):
		health.advance(dt)
		mob.think(dt)
		player.position = mob.position
	if health.health != full - 2 * Mob.CONTACT_DAMAGE:
		printerr("FAIL mob_contact no second hit after invulnerability (health %s)" % health.health)
		fail += 1
	# Dead: no damage, no chase.
	health.set_health_now(0)
	player.position = mob.position + Vector2(0, -2)
	mob.target = null
	mob.state = Mob.State.IDLE
	mob._pause = 0.0
	mob._calm = 0.0
	mob.think(dt)
	if health.health != 0 or mob.state == Mob.State.CHASE:
		printerr("FAIL mob_contact a dead player was hurt or chased (state %s)" % mob.state)
		fail += 1
	if fail == 0:
		print("PASS test_mob_contact (%s %s)" % [mob.name, mob.mob_type])
	scene.queue_free()
	return fail


func _test_mob_contact_two_players() -> int:
	## A client of a dedicated server parks its player on a mob; the server
	## lands the hit and the client's own PlayerHealth copy drops.
	print("-- test_mob_contact_two_players")
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL mob_contact_two_players found no free UDP port")
		return 1
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("FAIL mob_contact_two_players could not start the server process")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
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
	if player and scene.world_params and not mobs_node.mobs().is_empty():
		mob = mobs_node.mobs()[0]
	if mob == null:
		printerr("FAIL mob_contact_two_players no player or mobs on the client")
		fail += 1
	else:
		var health: PlayerHealth = player.get_node("Health")
		var full := health.max_health
		deadline = Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < deadline and health.health == full:
			player.position = mob.position
			player.velocity = Vector2.ZERO
			await process_frame
		if health.health != full - Mob.CONTACT_DAMAGE:
			printerr("FAIL mob_contact_two_players client health %s of %s after touching %s" % [health.health, full, mob.name])
			fail += 1
	OS.kill(pid)
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	if fail == 0:
		print("PASS test_mob_contact_two_players (%s)" % mob.name)
	return fail
