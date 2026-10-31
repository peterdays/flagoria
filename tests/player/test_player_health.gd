extends "res://tests/helpers/test_helpers.gd"
## Player health and regeneration (Scripts/player_health.gd).


func _test_player_regen() -> int:
	## The regen timer: every 5 s it heals half a heart, and skips players who
	## are dead or already full. Ticks are fired by hand through the scene's
	## own timeout connection, so the test does not wait 5 s per tick. Each
	## heal plays the regen tick for the local player only; a full or dead
	## player, set_health_now, and another peer's player play nothing.
	print("-- test_player_regen")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var me = load("res://Player/character_body_2d.tscn").instantiate()
	me.name = str(scene.multiplayer.get_unique_id())
	scene.get_node("World").add_child(me)
	var h: PlayerHealth = me.health
	var timer: Timer = me.get_node("regen_timer")
	# autostart reads false once the timer has started, so check that it runs.
	if timer.wait_time != 5.0 or timer.one_shot or timer.is_stopped():
		printerr("FAIL player_regen timer %s s, one_shot %s, running %s"
				% [timer.wait_time, timer.one_shot, not timer.is_stopped()])
		fail += 1
	if not timer.timeout.is_connected(me._on_regen_timer_timeout):
		printerr("FAIL player_regen timer timeout is not connected to the player")
		fail += 1
	var c: CombatSfx = me.combat_sfx
	# Hurt: one tick heals half a heart (1 point), the next another.
	h.set_health_now(3)
	if c.plays.get("regen", 0) != 0:
		printerr("FAIL player_regen set_health_now played the regen tick")
		fail += 1
	timer.timeout.emit()
	if h.health != 4 or c.plays.get("regen", 0) != 1:
		printerr("FAIL player_regen tick at 3 -> %s, regen plays %s, want 4 and 1" % [h.health, c.plays.get("regen", 0)])
		fail += 1
	c._last_ms.clear()  # ticks are 5 s apart in play, past the cooldown
	timer.timeout.emit()
	if h.health != 5 or c.plays.get("regen", 0) != 2:
		printerr("FAIL player_regen second tick -> %s, regen plays %s, want 5 and 2" % [h.health, c.plays.get("regen", 0)])
		fail += 1
	# Full: a tick changes nothing and plays nothing.
	c._last_ms.clear()
	h.set_health_now(h.max_health)
	timer.timeout.emit()
	if h.health != h.max_health or c.plays.get("regen", 0) != 2:
		printerr("FAIL player_regen full player -> %s, regen plays %s" % [h.health, c.plays.get("regen", 0)])
		fail += 1
	# Another peer's player heals on this peer too, but only its owner hears it.
	var other = load("res://Player/character_body_2d.tscn").instantiate()
	other.name = "2"
	scene.get_node("World").add_child(other)
	other.health.set_health_now(3)
	other.get_node("regen_timer").timeout.emit()
	if other.health.health != 4 or other.combat_sfx.plays.get("regen", 0) != 0:
		printerr("FAIL player_regen other peer's player -> %s, regen plays %s, want 4 and 0"
				% [other.health.health, other.combat_sfx.plays.get("regen", 0)])
		fail += 1
	# Dead: a tick does not heal (respawn restores health) and plays nothing.
	h.respawn_delay = 1000.0
	h.set_health_now(0)
	timer.timeout.emit()
	if h.health != 0 or not h.is_dead() or c.plays.get("regen", 0) != 2:
		printerr("FAIL player_regen dead player -> %s, regen plays %s" % [h.health, c.plays.get("regen", 0)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_player_regen")
	return fail


func _test_player_health() -> int:
	## Hearts: 3 hearts in half steps, damage, heal cap, invulnerability,
	## death and respawn at the spawn point, per-player health, and the HUD
	## row that follows the local player.
	print("-- test_player_health")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world: Node = scene.get_node("World")
	var me = load("res://Player/character_body_2d.tscn").instantiate()
	me.name = str(scene.multiplayer.get_unique_id())  # the local player binds the HUD
	world.add_child(me)
	var other = load("res://Player/character_body_2d.tscn").instantiate()
	other.name = "2"
	world.add_child(other)
	var h: PlayerHealth = me.health
	var hud: HeartsHud = scene.get_node("CanvasLayer1/HeartsHud")
	var deaths := [0]
	h.died.connect(func() -> void: deaths[0] += 1)

	if h.max_health != 6 or h.health != 6 or h.heart_count() != 3:
		printerr("FAIL player_health: start %s/%s, %s hearts" % [h.health, h.max_health, h.heart_count()])
		fail += 1
	if not hud.visible or hud.current != 6 or hud.maximum != 6 or not hud.size.is_equal_approx(Vector2(29, 9)):
		printerr("FAIL player_health: HUD visible=%s %s/%s size %s" % [hud.visible, hud.current, hud.maximum, hud.size])
		fail += 1
	# Half-heart step, then invulnerability blocks the next hit until it ends.
	if not h.take_damage(1) or h.health != 5 or not h.is_invulnerable():
		printerr("FAIL player_health: first hit -> %s, invulnerable=%s" % [h.health, h.is_invulnerable()])
		fail += 1
	if h.take_damage(1) or h.health != 5:
		printerr("FAIL player_health: hit during invulnerability -> %s" % h.health)
		fail += 1
	if hud.current != 5:
		printerr("FAIL player_health: HUD shows %s, want 5" % hud.current)
		fail += 1
	h.advance(h.invulnerable_time + 0.01)
	if h.is_invulnerable() or not h.take_damage(2) or h.health != 3:
		printerr("FAIL player_health: hit after invulnerability -> %s" % h.health)
		fail += 1
	if other.health.health != 6:
		printerr("FAIL player_health: other player's health changed to %s" % other.health.health)
		fail += 1
	# Heal clamps at max; zero or negative amounts do nothing.
	if h.take_damage(0) or h.heal(0) or h.heal(-1) or h.health != 3:
		printerr("FAIL player_health: zero/negative amounts changed health to %s" % h.health)
		fail += 1
	if not h.heal(10) or h.health != 6 or h.heal(1):
		printerr("FAIL player_health: heal cap -> %s" % h.health)
		fail += 1
	# HUD icons per heart slot for every half step.
	var icons := {6: "FFF", 5: "FFH", 4: "FFE", 3: "FHE", 2: "FEE", 1: "HEE", 0: "EEE"}
	for value in icons:
		var got := ""
		for slot in 3:
			var tex := HeartsHud.icon_for(slot, value)
			got += "F" if tex == HeartsHud.ICON_FULL else ("H" if tex == HeartsHud.ICON_HALF else "E")
		if got != icons[value]:
			printerr("FAIL player_health: icons at %s = %s, want %s" % [value, got, icons[value]])
			fail += 1
	for tex in [HeartsHud.ICON_FULL, HeartsHud.ICON_HALF, HeartsHud.ICON_EMPTY, HeartsHud.ICON_FLASH_0, HeartsHud.ICON_FLASH_1]:
		if tex.get_size() != Vector2(9, 9):
			printerr("FAIL player_health: heart icon %s is %s, want 9x9" % [tex.resource_path, tex.get_size()])
			fail += 1
	# Losing health flashes only the hearts that changed: flash 0, flash 1, then the new state.
	hud.set_process(false)
	hud.set_health(6, 6)
	hud.set_health(3, 6)
	var flash := func() -> String:
		var out := ""
		for slot in 3:
			var tex := hud.shown_icon(slot)
			out += {HeartsHud.ICON_FULL: "F", HeartsHud.ICON_HALF: "H", HeartsHud.ICON_EMPTY: "E", HeartsHud.ICON_FLASH_0: "0", HeartsHud.ICON_FLASH_1: "1"}[tex]
		return out
	var seen: Array[String] = [flash.call()]
	hud.advance(HeartsHud.FLASH_FRAME + 0.001)
	seen.append(flash.call())
	hud.advance(HeartsHud.FLASH_FRAME)
	seen.append(flash.call())
	hud.set_health(6, 6)  # healing does not flash
	seen.append(flash.call())
	if seen != ["F00", "F11", "FHE", "FFF"]:
		printerr("FAIL player_health: loss flash %s, want [F00, F11, FHE, FFF]" % [seen])
		fail += 1
	hud.set_process(true)
	if not hud.position.is_equal_approx(Vector2(HeartsHud.MARGIN, HeartsHud.MARGIN) * hud.scale.x):
		printerr("FAIL player_health: HUD at %s scale %s" % [hud.position, hud.scale])
		fail += 1
	# Death: health stops at 0, the player hides and cannot be hit or healed.
	h.set_health_now(1)
	if not h.take_damage(5) or h.health != 0 or not h.is_dead() or deaths[0] != 1:
		printerr("FAIL player_health: kill -> %s, dead=%s, deaths=%s" % [h.health, h.is_dead(), deaths[0]])
		fail += 1
	h.advance(h.respawn_delay * 0.5)  # still before respawn
	me._process(0.0)
	if me.sprite.visible or h.take_damage(1) or h.heal(1) or deaths[0] != 1:
		printerr("FAIL player_health: dead player visible=%s or changed" % me.sprite.visible)
		fail += 1
	# Respawn: full health, invulnerable, back at the spawn point.
	me.position = Vector2(5000, 5000)
	var spawn: Vector2 = me.spawn_position()
	h.advance(h.respawn_delay * 0.5 + 0.01)
	me._process(0.0)
	if h.health != 6 or h.is_dead() or not h.is_invulnerable() or not me.sprite.visible:
		printerr("FAIL player_health: respawn -> %s, invulnerable=%s" % [h.health, h.is_invulnerable()])
		fail += 1
	if me.position != spawn or spawn == Vector2(5000, 5000):
		printerr("FAIL player_health: respawned at %s, spawn %s" % [me.position, spawn])
		fail += 1
	if hud.current != 6:
		printerr("FAIL player_health: HUD after respawn %s" % hud.current)
		fail += 1
	# set_health_now(0) (tools, tests) leaves the same dead body as a kill.
	h.set_health_now(0)
	await physics_frame
	me._process(0.0)
	if not me.body_shape.disabled or not me.sword_shape.disabled or me.sprite.visible:
		printerr("FAIL player_health: set_health_now(0) body off %s, sword off %s, sprite %s"
				% [me.body_shape.disabled, me.sword_shape.disabled, me.sprite.visible])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_player_health")
	return fail


func _test_player_health_sync() -> int:
	## Two peers over ENet loopback, each with its own branch of the tree: the
	## server's health changes reach the client, a late copy asks for the
	## current value, and the client cannot change health itself.
	print("-- test_player_health_sync")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL player_health_sync found no free UDP port")
		return 1
	var server_root := Node.new()
	server_root.name = "HealthServer"
	var client_root := Node.new()
	client_root.name = "HealthClient"
	root.add_child(server_root)
	root.add_child(client_root)
	var smp := SceneMultiplayer.new()
	var cmp := SceneMultiplayer.new()
	set_multiplayer(smp, server_root.get_path())
	set_multiplayer(cmp, client_root.get_path())
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer

	var s_player := Node2D.new()
	s_player.name = "P"
	s_player.position = Vector2(32, 48)
	var s_health := PlayerHealth.new()
	s_health.name = "Health"
	s_player.add_child(s_health)
	server_root.add_child(s_player)
	s_health.take_damage(2)  # before the client exists

	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	cmp.multiplayer_peer = cpeer
	if not await _client_connected(smp, cpeer):
		printerr("FAIL player_health_sync client did not connect")
		fail += 1
	else:
		var c_player := Node2D.new()
		c_player.name = "P"
		var c_health := PlayerHealth.new()
		c_health.name = "Health"
		c_player.add_child(c_health)
		client_root.add_child(c_player)
		var c_damage := [0]
		var c_respawn := [Vector2.INF]
		c_health.damaged.connect(func(amount: int) -> void: c_damage[0] += amount)
		c_health.respawned.connect(func(at: Vector2) -> void: c_respawn[0] = at)

		var wait := func(cond: Callable) -> bool:
			var until := Time.get_ticks_msec() + 5000
			while Time.get_ticks_msec() < until and not cond.call():
				await process_frame
			return cond.call()

		if not await wait.call(func() -> bool: return c_health.health == 4):
			printerr("FAIL player_health_sync late copy has %s, server 4" % c_health.health)
			fail += 1
		if c_health.take_damage(1) or c_health.heal(1) or c_health.health != 4 or s_health.health != 4:
			printerr("FAIL player_health_sync client changed health (client %s, server %s)" % [c_health.health, s_health.health])
			fail += 1
		s_health.advance(s_health.invulnerable_time)
		s_health.take_damage(1)
		if not await wait.call(func() -> bool: return c_health.health == 3 and c_damage[0] == 1):
			printerr("FAIL player_health_sync hit: client %s, damaged %s" % [c_health.health, c_damage[0]])
			fail += 1
		if not c_health.is_invulnerable():
			printerr("FAIL player_health_sync client copy not invulnerable after the hit")
			fail += 1
		s_health.advance(s_health.invulnerable_time)
		s_health.take_damage(3)
		if not await wait.call(func() -> bool: return c_health.is_dead()):
			printerr("FAIL player_health_sync client did not see the death (%s)" % c_health.health)
			fail += 1
		c_health.advance(10.0)  # only the server counts down to respawn
		if not c_health.is_dead() or c_respawn[0] != Vector2.INF:
			printerr("FAIL player_health_sync client respawned on its own")
			fail += 1
		s_health.advance(s_health.respawn_delay)
		if not await wait.call(func() -> bool: return c_health.health == 6 and c_respawn[0] == Vector2(32, 48)):
			printerr("FAIL player_health_sync respawn: client %s at %s" % [c_health.health, c_respawn[0]])
			fail += 1

	cpeer.close()
	speer.close()
	set_multiplayer(null, client_root.get_path())
	set_multiplayer(null, server_root.get_path())
	server_root.queue_free()
	client_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_player_health_sync")
	return fail


func _test_player_health_join_while_dead() -> int:
	## A peer that joins while another player is dead sees that player dead:
	## hidden, with body and sword collision off, and no death sound replayed.
	## Its own hearts take the server's value from the state reply with no
	## loss flash. Server: bare PlayerHealth nodes; client: the real scenes.
	print("-- test_player_health_join_while_dead")
	var fail := 0
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL health_join_dead found no free UDP port")
		return 1
	var server_root := Node.new()
	server_root.name = "JoinDeadServer"
	root.add_child(server_root)
	var s_world := Node.new()
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
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	var me_id := str(cpeer.get_unique_id())
	# Before the client connects: player 5 is dead, the joiner's own player
	# is down to 4 (as if hit right after spawning).
	var server_health := func(player_name: String) -> PlayerHealth:
		var p := Node2D.new()
		p.name = player_name
		var h := PlayerHealth.new()
		h.name = "Health"
		h.respawn_delay = 1000.0  # stays dead for the whole test
		p.add_child(h)
		s_world.add_child(p)
		return h
	server_health.call("5").take_damage(6)
	server_health.call(me_id).take_damage(2)
	cmp.multiplayer_peer = cpeer
	if not await _client_connected(smp, cpeer):
		printerr("FAIL health_join_dead client did not connect")
		fail += 1
	else:
		# The joiner's copies of both players. The test has no synchronizer on
		# the server side, so the copies go without theirs.
		var world: Node = scene.get_node("World")
		var copy := func(player_name: String) -> CharacterBody2D:
			var p = load("res://Player/character_body_2d.tscn").instantiate()
			p.name = player_name
			p.get_node("MultiplayerSynchronizer").free()
			world.add_child(p)
			return p
		var dead = copy.call("5")
		var deaths := [0]
		dead.health.died.connect(func() -> void: deaths[0] += 1)
		var me = copy.call(me_id)
		me.set_physics_process(false)  # its animation RPCs have no server node here
		var hud: HeartsHud = scene.get_node("CanvasLayer1/HeartsHud")
		hud.set_process(false)  # a flash must still be up when checked
		var until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until and (dead.health.health != 0 or me.health.health != 4):
			await process_frame
		for i in 3:
			await physics_frame
		dead._process(0.0)
		if dead.health.health != 0 or not dead.health.is_dead():
			printerr("FAIL health_join_dead joiner sees %s for a dead player" % dead.health.health)
			fail += 1
		if not dead.body_shape.disabled or not dead.sword_shape.disabled or dead.sprite.visible or dead.weapon.visible:
			printerr("FAIL health_join_dead dead copy: body off %s, sword off %s, sprite %s, weapon %s"
					% [dead.body_shape.disabled, dead.sword_shape.disabled, dead.sprite.visible, dead.weapon.visible])
			fail += 1
		if deaths[0] != 0:
			printerr("FAIL health_join_dead join replayed the death (%s)" % deaths[0])
			fail += 1
		if me.health.health != 4 or hud.current != 4:
			printerr("FAIL health_join_dead own hearts %s, HUD %s, server 4" % [me.health.health, hud.current])
			fail += 1
		var flashing := false
		for slot in 3:
			flashing = flashing or hud.shown_icon(slot) in [HeartsHud.ICON_FLASH_0, HeartsHud.ICON_FLASH_1]
		if flashing:
			printerr("FAIL health_join_dead the join state reply flashed the HUD")
			fail += 1
		if me.body_shape.disabled:
			printerr("FAIL health_join_dead living joiner has no body collision")
			fail += 1
		hud.set_process(true)
	cpeer.close()
	speer.close()
	set_multiplayer(null, scene.get_path())
	set_multiplayer(null, server_root.get_path())
	scene.queue_free()
	server_root.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_player_health_join_while_dead")
	return fail
