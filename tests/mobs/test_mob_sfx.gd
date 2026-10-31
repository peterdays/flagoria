extends "res://tests/helpers/test_helpers.gd"
## Mob sounds (Scripts/mob_sfx.gd).


func _test_mob_sfx_clips() -> int:
	## Every mob type has every MobSfx event, each mapped to clips that load
	## and are not empty, with a volume, a cooldown and a per-mob offset. Each
	## mob's sound players use the SFX bus and fade out with distance.
	print("-- test_mob_sfx_clips")
	var fail := 0
	for t in MobCatalog.names():
		if not MobSfx.SOUNDS.has(t) or not MobSfx.MOB_VOLUME_DB.has(t):
			printerr("FAIL mob_sfx_clips: %s has no sounds or no volume offset" % t)
			fail += 1
			continue
		for event in MobSfx.EVENTS:
			var clips: Array = MobSfx.SOUNDS[t].get(event, [])
			if clips.is_empty():
				printerr("FAIL mob_sfx_clips: %s has no %s clips" % [t, event])
				fail += 1
			for clip in clips:
				var wav := clip as AudioStreamWAV
				if wav == null or wav.get_length() <= 0.05 or not ResourceLoader.exists(wav.resource_path):
					printerr("FAIL mob_sfx_clips: %s %s clip %s missing or empty" % [t, event, clip])
					fail += 1
				elif not wav.resource_path.get_file().begins_with("%s_%s_" % [t, event]):
					printerr("FAIL mob_sfx_clips: %s %s maps to %s" % [t, event, wav.resource_path])
					fail += 1
	# The crab clips are 1-3.6 dB quieter than the others; its offset makes up some of it.
	if not (MobSfx.MOB_VOLUME_DB.get(MobCatalog.CRAB, 0.0) >= 1.0 and MobSfx.MOB_VOLUME_DB.get(MobCatalog.CRAB, 0.0) <= 3.6):
		printerr("FAIL mob_sfx_clips: crab offset %s dB, want 1..3.6" % MobSfx.MOB_VOLUME_DB.get(MobCatalog.CRAB))
		fail += 1
	for t in MobSfx.SOUNDS:
		if not MobCatalog.TYPES.has(t):
			printerr("FAIL mob_sfx_clips: sounds for unknown mob %s" % t)
			fail += 1
	for event in MobSfx.EVENTS:
		if not MobSfx.VOLUME_DB.has(event) or not MobSfx.COOLDOWN.has(event) or not MobSfx.new().plays.has(event):
			printerr("FAIL mob_sfx_clips: %s lacks a volume, cooldown or counter" % event)
			fail += 1
	for t in MobCatalog.names():
		var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
		mob.setup(t, Vector2.ZERO, 1)
		root.add_child(mob)
		for event in MobSfx.EVENTS:
			var p: AudioStreamPlayer2D = mob.sfx.get_node(event)
			var want: float = MobSfx.VOLUME_DB[event] + MobSfx.MOB_VOLUME_DB[t]
			if p.bus != &"SFX" or not is_equal_approx(p.volume_db, want) or p.max_distance != MobSfx.MAX_DISTANCE:
				printerr("FAIL mob_sfx_clips: %s %s on %s at %s dB, max %s" % [t, event, p.bus, p.volume_db, p.max_distance])
				fail += 1
		mob.free()
	if fail == 0:
		print("PASS test_mob_sfx_clips")
	return fail


func _test_mob_sfx_events() -> int:
	## Each mob event plays once per event on this peer from the real hooks:
	## notice on a new chase (not the chase straight after a hit), attack when
	## a contact hit lands, hurt per sword hit, hurt and death on the last
	## hit. A peer that only receives the synced values (state, attacks)
	## plays the same, and nothing for values in the spawn packet. Hidden
	## mobs play nothing. Idle is rare, randomised per mob and only while
	## idling or wandering.
	print("-- test_mob_sfx_events")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world: TileMap = scene.get_node("World/worldMap")
	world.apply_map_params(_spawn_params(42, 0.003))
	world.generate_chunk(Vector2.ZERO)
	var mobs_node: Node = scene.get_node("World/Mobs")
	var add_mob := func(type: String, n: String) -> Mob:
		var m: Mob = load("res://Mobs/mob.tscn").instantiate()
		m.name = n
		m.setup(type, Vector2.ZERO, 7)
		mobs_node.add_child(m)
		m.set_physics_process(false)  # this test drives the behaviour
		m.sfx.idle_enabled = false
		return m
	var want := func(m: Mob, label: String, expect: Dictionary) -> int:
		var got := {}
		for e in MobSfx.EVENTS:
			got[e] = m.sfx.plays[e]
			m.sfx._last_ms.clear()  # steps are not about cooldowns
		for e in MobSfx.EVENTS:
			if got[e] != expect.get(e, 0):
				printerr("FAIL mob_sfx_events %s %s: plays %s, want %s" % [m.mob_type, label, got, expect])
				return 1
		return 0

	for t in MobCatalog.names():
		var mob: Mob = add_mob.call(t, "server_" + t)
		var player = load("res://Player/character_body_2d.tscn").instantiate()
		player.name = "1"
		player.position = Vector2(400, 400)
		scene.get_node("World").add_child(player)
		player.health.max_health = 1000
		player.health.set_health_now(1000)
		# The same events as the server's behaviour sets them.
		var history: Array = []  # [state, attacks] after each step, for the client copy
		var expect := {}
		var step := func(label: String, adds: Dictionary) -> void:
			for e in adds:
				expect[e] = expect.get(e, 0) + adds[e]
			fail += want.call(mob, label, expect)
			history.append([mob.state, mob.attacks, label, expect.duplicate()])
		mob.state = Mob.State.WALK
		step.call("walk", {})
		mob.state = Mob.State.CHASE
		step.call("chase", {"notice": 1})
		player.position = mob.position
		mob._touch_players()
		step.call("contact", {"attack": 1})
		mob._touch_players()  # player still invulnerable: no hit, no sound
		step.call("contact_blocked", {})
		mob.hp = 2
		mob.take_hit()
		step.call("hit", {"hurt": 1})
		mob.take_hit()  # ignored during HURT
		step.call("hit_during_hurt", {})
		mob.state = Mob.State.IDLE
		step.call("hurt_over", {})
		mob.state = Mob.State.CHASE
		step.call("chase_after_hit", {})
		mob.state = Mob.State.IDLE  # gave up
		step.call("give_up", {})
		mob.state = Mob.State.CHASE
		step.call("chase_again", {"notice": 1})
		mob.take_hit()
		step.call("last_hit", {"hurt": 1, "death": 1})
		player.position = Vector2(400, 400)
		player.free()

		# A late peer: the spawn packet sets state and attacks before ready.
		var late: Mob = load("res://Mobs/mob.tscn").instantiate()
		late.setup(t, Vector2.ZERO, 7)
		late.state = Mob.State.CHASE
		late.attacks = 3
		mobs_node.add_child(late)
		late.set_physics_process(false)
		fail += want.call(late, "spawn_packet", {})
		late.free()
		# A peer that receives each synced change: same plays as the server.
		var client: Mob = add_mob.call(t, "client_" + t)
		for entry in history:
			client.set("state", entry[0])
			client.set("attacks", entry[1])
			fail += want.call(client, "synced " + entry[2], entry[3])
		client.free()
		# Coalesced sync: the client sees HURT -> CHASE with no IDLE between.
		var coalesced: Mob = add_mob.call(t, "coalesced_" + t)
		coalesced.set("state", Mob.State.WALK)
		coalesced.set("state", Mob.State.HURT)
		coalesced.set("state", Mob.State.CHASE)
		fail += want.call(coalesced, "hurt_then_chase", {"hurt": 1})
		coalesced.free()
		# Hidden (uncharted ground on this peer): silent.
		var hidden: Mob = add_mob.call(t, "hidden_" + t)
		hidden.visible = false
		hidden.state = Mob.State.WALK
		hidden.state = Mob.State.CHASE
		hidden.attacks += 1
		hidden.take_hit()
		hidden.sfx.idle_enabled = true
		hidden.state = Mob.State.IDLE
		hidden.sfx.idle_left = 0.0
		hidden.sfx._process(0.1)
		fail += want.call(hidden, "hidden", {})
		hidden.free()
		mob.free()

	# Idle: on a random timer per mob, only while idling or wandering.
	var a: Mob = add_mob.call(MobCatalog.SLIME, "idle_a")
	var b: Mob = add_mob.call(MobCatalog.SLIME, "idle_b")
	if is_equal_approx(a.sfx.idle_left, b.sfx.idle_left):
		printerr("FAIL mob_sfx_events idle timers match: %s" % a.sfx.idle_left)
		fail += 1
	for i in 200:
		var d: float = a.sfx.next_idle_delay()
		if d < MobSfx.IDLE_INTERVAL.x or d > MobSfx.IDLE_INTERVAL.y:
			printerr("FAIL mob_sfx_events idle delay %s outside %s" % [d, MobSfx.IDLE_INTERVAL])
			fail += 1
			break
	a.sfx.idle_enabled = true
	a.state = Mob.State.CHASE
	a.sfx.idle_left = 0.05
	a.sfx._process(0.1)
	fail += want.call(a, "idle_while_chasing", {"notice": 1})
	a.state = Mob.State.IDLE
	a.sfx._process(0.04)
	fail += want.call(a, "idle_early", {"notice": 1})
	a.sfx._process(0.02)
	fail += want.call(a, "idle_due", {"notice": 1, "idle": 1})
	if a.sfx.idle_left < MobSfx.IDLE_INTERVAL.x:
		printerr("FAIL mob_sfx_events next idle in %s s" % a.sfx.idle_left)
		fail += 1
	# A minute of idling: a few idle sounds, never more than the interval allows.
	a.state = Mob.State.WALK
	for i in 600:
		a.sfx._process(0.1)
		a.sfx._last_ms.clear()
	var idles: int = a.sfx.plays["idle"] - 1
	if idles < 2 or idles > 5:
		printerr("FAIL mob_sfx_events %s idle sounds in 60 s, want 2..5" % idles)
		fail += 1

	# The hooks reach every peer only if both values are synced on change.
	var cfg: SceneReplicationConfig = a.get_node("MultiplayerSynchronizer").replication_config
	for prop in [NodePath(".:state"), NodePath(".:attacks")]:
		if not cfg.has_property(prop) or cfg.property_get_replication_mode(prop) != SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE or not cfg.property_get_spawn(prop):
			printerr("FAIL mob_sfx_events %s is not synced on change and at spawn" % prop)
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_mob_sfx_events")
	return fail
