extends RefCounted
## Shared test helpers, and the base script of every `tests/**/test_*.gd` file:
##     extends "res://tests/helpers/test_helpers.gd"
## The runner (tests/run_tests.gd) sets `tree` before a test runs. The
## SceneTree members tests use (`root`, `process_frame`, `physics_frame`,
## `paused`, `create_timer()`, `set_multiplayer()`) forward to it, so a test
## reads the same here as it did in the runner.

var tree: SceneTree

var root: Window:
	get:
		return tree.root

var process_frame: Signal:
	get:
		return tree.process_frame

var physics_frame: Signal:
	get:
		return tree.physics_frame

var paused: bool:
	get:
		return tree.paused
	set(value):
		tree.paused = value


func create_timer(time_sec: float, process_always := true, process_in_physics := false,
		ignore_time_scale := false) -> SceneTreeTimer:
	return tree.create_timer(time_sec, process_always, process_in_physics, ignore_time_scale)


func set_multiplayer(api: MultiplayerAPI, root_path: NodePath = ^"") -> void:
	tree.set_multiplayer(api, root_path)


func _pre_biome_defaults() -> MapGenParams:
	## Default params with biomes off. New worlds have biomes on; tests that pin
	## exact cells or compare against pre-biome maps start from this instead.
	var params := MapGenParams.make_defaults()
	params.biome_frequency = 0.0
	return params


func _spawn_params(seed_value: int, biome_frequency: float) -> MapGenParams:
	var params = _pre_biome_defaults()
	params.altitude_seed = seed_value
	params.moisture_seed = seed_value
	params.temperature_seed = seed_value
	params.items_seed = seed_value
	params.biome_seed = seed_value
	params.biome_frequency = biome_frequency
	return params


func _spawn_session(mode: String, joiners: int) -> int:
	## One session of tests/late_join_probe.gd peers (see test_spawn_late_join):
	## a server in mode ("dedicated" or "host") and joiners clients.
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL spawn_late_join %s found no free UDP port" % mode)
		return 1
	# A fresh folder: a .stop file left by an earlier run would stop a peer
	# at once, and its old JSON would read as this run's.
	var dir := OS.get_user_data_dir().path_join("late_join_%s_%d_%d" % [mode, OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var pids: Array[int] = []
	var outs: Array[String] = []
	var start := func(extra: Array) -> void:
		var out := dir.path_join("p%d.json" % outs.size())
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://tests/late_join_probe.gd", "--", "--port=%d" % port, "--out=" + out]
		args.append_array(extra)
		pids.append(OS.create_process(OS.get_executable_path(), args))
		outs.append(out)
	var read := func(i: int) -> Dictionary:
		var text := FileAccess.get_file_as_string(outs[i])
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	var pause := func(ms: int) -> void:
		await wait_for.call(func() -> bool: return false, ms)

	var tile_map: Script = load("res://Scripts/TileMap.gd")
	# A spot is a cell centre, and the 8 x 10 body reaches 2 px into the cell
	# above: with a wall there, physics pushes the player about 2 px down.
	var settle := 3.0
	# Where each peer's own player stands (in its own view) against want_of's
	# spot for it, give or take settle; then no overlaps, all near the spawn,
	# and every peer sees every player where its owner has it.
	var check := func(stage: String, want_of: Callable) -> int:
		var bad := 0
		var at := {}
		var server: Dictionary = read.call(0)
		var origin := Vector2(server["origin"][0], server["origin"][1])
		for i in outs.size():
			var s: Dictionary = read.call(i)
			var me = s.get("players", {}).get(s.get("id"))
			if me == null:
				continue  # the dedicated server has no player
			var pos := Vector2(me["pos"][0], me["pos"][1])
			at[s["id"]] = pos
			var want = want_of.call(s, server)
			if want == null or pos.distance_to(Vector2(want[0], want[1])) > settle:
				printerr("FAIL spawn_late_join %s %s: peer %s stands at %s, the server's spot is %s" % [mode, stage, s["id"], pos, want])
				bad += 1
			if pos.distance_to(origin) > tile_map.SPAWN_RADIUS + settle:
				printerr("FAIL spawn_late_join %s %s: peer %s at %s is %s px from the spawn %s" % [mode, stage, s["id"], pos, pos.distance_to(origin), origin])
				bad += 1
		var ids := at.keys()
		if ids.size() != joiners + (1 if mode == "host" else 0):
			printerr("FAIL spawn_late_join %s %s: %s players, want %s" % [mode, stage, ids.size(), joiners])
			bad += 1
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				if (at[ids[i]] as Vector2).distance_to(at[ids[j]]) < tile_map.SPAWN_CLEARANCE - settle:
					printerr("FAIL spawn_late_join %s %s: peers %s at %s and %s at %s overlap" % [mode, stage, ids[i], at[ids[i]], ids[j], at[ids[j]]])
					bad += 1
		for i in outs.size():
			var s: Dictionary = read.call(i)
			for id in ids:
				var seen = s.get("players", {}).get(id)
				if seen == null or not Vector2(seen["pos"][0], seen["pos"][1]).is_equal_approx(at[id]):
					printerr("FAIL spawn_late_join %s %s: peer %s sees %s at %s, its owner has %s" % [mode, stage, s.get("id"), id, seen, at[id]])
					bad += 1
		if bad == 0:
			print("PASS spawn_late_join %s %s %s" % [mode, stage, at])
		return bad

	var fail := 0
	start.call(["--" + mode])
	if not await wait_for.call(func() -> bool: return read.call(0).get("origin") != null, 30000):
		printerr("FAIL spawn_late_join %s server did not start" % mode)
		fail += 1
	# One joiner at a time, each once the one before has its player and the map.
	for i in joiners:
		if fail > 0:
			break
		start.call([])
		var n := outs.size() - 1
		var joined := func() -> bool:
			var s: Dictionary = read.call(n)
			return s.get("origin") != null and s.get("players", {}).has(s.get("id")) \
					and read.call(0).get("picked", {}).has(s.get("id"))
		if not await wait_for.call(joined, 30000):
			printerr("FAIL spawn_late_join %s joiner %s did not get its player and the map: %s, server %s"
					% [mode, n, read.call(n), read.call(0)])
			fail += 1
		await pause.call(300)
	if fail == 0:
		await pause.call(1000)
		fail += check.call("join", func(s: Dictionary, server: Dictionary) -> Variant:
			return server["picked"].get(s["id"]))
	if fail == 0:
		FileAccess.open(outs[0] + ".kill", FileAccess.WRITE).close()
		var all_respawned := func() -> bool:
			for i in outs.size():
				var s: Dictionary = read.call(i)
				if s.get("players", {}).has(s.get("id")) and s.get("respawned_at") == null:
					return false
				for p in s.get("players", {}).values():
					if p["respawns"] < 1:
						return false
			return true
		if not await wait_for.call(all_respawned, 15000):
			printerr("FAIL spawn_late_join %s the batch did not respawn on every peer" % mode)
			fail += 1
		else:
			# The spots the server sent in one batch: each clear of the rest
			# and near the spawn. Then each player stands on its spot, as
			# after joining (see test_respawn_teleport_ghosts).
			var server: Dictionary = read.call(0)
			var origin := Vector2(server["origin"][0], server["origin"][1])
			var spots := {}
			for i in outs.size():
				var s: Dictionary = read.call(i)
				if s.get("respawned_at") != null:
					spots[s["id"]] = Vector2(s["respawned_at"][0], s["respawned_at"][1])
			var ids := spots.keys()
			var bad := 0
			if ids.size() != joiners + (1 if mode == "host" else 0):
				printerr("FAIL spawn_late_join %s respawn: %s players respawned, want %s" % [mode, ids.size(), joiners])
				bad += 1
			for i in ids.size():
				if (spots[ids[i]] as Vector2).distance_to(origin) > tile_map.SPAWN_RADIUS:
					printerr("FAIL spawn_late_join %s respawn: %s sent to %s, past the radius" % [mode, ids[i], spots[ids[i]]])
					bad += 1
				for j in range(i + 1, ids.size()):
					if (spots[ids[i]] as Vector2).distance_to(spots[ids[j]]) < tile_map.SPAWN_CLEARANCE:
						printerr("FAIL spawn_late_join %s respawn: %s and %s sent to %s and %s" % [mode, ids[i], ids[j], spots[ids[i]], spots[ids[j]]])
						bad += 1
			if bad == 0:
				print("PASS spawn_late_join %s respawn %s" % [mode, spots])
			fail += bad
			await pause.call(1000)
			fail += check.call("respawn landing", func(s: Dictionary, _server: Dictionary) -> Variant:
				return s.get("respawned_at"))

	for out in outs:
		FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	await wait_for.call(func() -> bool:
		for pid in pids:
			if OS.is_process_running(pid):
				return false
		return true, 10000)
	for pid in pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_remove_dir(dir)
	return fail


func _remove_dir(dir: String) -> void:
	## Quiet when dir does not exist (the first clean-up of a fresh session).
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _body_rect(player: Node) -> Rect2:
	## The player's body collision box in world space.
	var shape_node: CollisionShape2D = player.body_shape
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	return Rect2(player.position + shape_node.position - size / 2.0, size)


func _respawn_follow_case(label: String, death: Vector2, spawn: Vector2, walk: Vector2,
		drop_ms: int, prior: int = 0) -> int:
	## One respawn of a client-owned player over a UDP proxy (60 ms each way).
	## After the owner respawns it walks `walk` per physics frame; packets from
	## the owner are dropped for `drop_ms` from that moment. The server's copy
	## must follow the owner, not stay at the spawn. With `prior` > 0 the owner
	## has respawned that many times before the server's copy existed (as for
	## a peer that joined later), and that copy must never show the death spot.
	var fail := 0
	await process_frame
	var port := _free_udp_port()
	var proxy_port := _free_udp_port()
	if port == 0 or proxy_port == 0 or port == proxy_port:
		printerr("FAIL respawn_hold %s found no free UDP ports" % label)
		return 1
	var server_root := Node.new()
	server_root.name = "HoldServer"
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
	const DELAY_MS := 60
	var listen := UDPServer.new()
	listen.listen(proxy_port, "127.0.0.1")
	var upstream := PacketPeerUDP.new()
	upstream.connect_to_host("127.0.0.1", port)
	var link := {"down": null, "up_q": [], "down_q": [], "drop_until": 0}
	var pump := func() -> void:
		var now := Time.get_ticks_msec()
		listen.poll()
		if listen.is_connection_available():
			link.down = listen.take_connection()
		if link.down:
			while link.down.get_available_packet_count() > 0:
				var packet: PackedByteArray = link.down.get_packet()
				if now >= link.drop_until:
					link.up_q.append([now + DELAY_MS, packet])
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
		printerr("FAIL respawn_hold %s client did not connect" % label)
		fail += 1
	else:
		var player_scene := load("res://Player/character_body_2d.tscn")
		var id := str(cpeer.get_unique_id())
		var s_copy = player_scene.instantiate()
		s_copy.name = id
		s_copy.position = death
		s_world.add_child(s_copy)
		var owner_copy = player_scene.instantiate()
		owner_copy.name = id
		owner_copy.position = death
		scene.get_node("World").add_child(owner_copy)
		owner_copy.set_physics_process(false)  # the test moves the owner
		for i in prior:
			owner_copy.health._do_respawn(death, i + 1)  # unseen by the server's copy
		s_copy.health.respawn_count = prior  # the server numbered those respawns
		var shown_death := []
		var watch := func() -> void:
			var at: Vector2 = s_copy.position
			if prior > 0 and shown_death.is_empty() and at.distance_to(death) < at.distance_to(spawn):
				shown_death.append(at)
		s_copy.health.respawn_delay = 1000.0
		for i in 20:
			await physics_frame
		s_copy.health.take_damage(s_copy.health.max_health)
		var until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until and not owner_copy.health.is_dead():
			await physics_frame
		for i in 10:
			await physics_frame
		s_copy.health._do_respawn.rpc(spawn, s_copy.health.respawn_count + 1)
		# Drop from now until drop_ms after the respawn reaches the owner.
		link.drop_until = Time.get_ticks_msec() + DELAY_MS + drop_ms if drop_ms > 0 else 0
		until = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until and owner_copy.health.is_dead():
			watch.call()
			await physics_frame
		var started := Time.get_ticks_msec()
		while Time.get_ticks_msec() - started < 450:
			watch.call()
			owner_copy.position += walk
			await physics_frame
		if not shown_death.is_empty():
			printerr("FAIL respawn_hold %s: server copy showed the death spot after the respawn (%s)"
					% [label, shown_death[0]])
			fail += 1
		var gap: float = s_copy.position.distance_to(owner_copy.position)
		if gap > 40.0:
			printerr("FAIL respawn_hold %s: server copy at %s, %d px behind the owner at %s"
					% [label, s_copy.position, gap, owner_copy.position])
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
	return fail


func _walls_from_rows(rows: Array, family: String = WallSolver.STONE) -> Dictionary:
	## '#' wall, 'g' closed gate, 'o' open gate; every other character is empty.
	var walls := {}
	for y in rows.size():
		for x in rows[y].length():
			var c: String = rows[y][x]
			if c in ["#", "g", "o"]:
				walls[Vector2i(x, y)] = {"family": family, "gate": c != "#", "open": c == "o"}
	return walls


func _structure_errors(text: String) -> Array[String]:
	var result := Structure.parse(text)
	if (result["structure"] == null) == result["errors"].is_empty():
		return ["parse returned both a structure and errors, or neither"]
	return result["errors"]


func _archipelago_land_masses(world, half: int) -> int:
	## 4-connected land components in [-half, half)^2 using the chunk altitude.
	var land := {}
	for x in range(-half, half):
		for y in range(-half, half):
			var cell := Vector2i(x, y)
			var alt: float = world.archipelago_altitude(cell, world.island_altitude(cell, world.altitude.get_noise_2d(x, y)))
			if alt > world.water_max_alt:
				land[cell] = true
	var masses := 0
	var seen := {}
	for start in land.keys():
		if seen.has(start):
			continue
		masses += 1
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + step
				if land.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
	return masses


func _biome_terrain_params(arch: bool) -> MapGenParams:
	var p := _pre_biome_defaults()
	p.altitude_seed = 2
	p.moisture_seed = 7
	p.temperature_seed = 12
	p.items_seed = 17
	p.biome_seed = 31
	p.chunk_width = 96
	p.chunk_height = 96
	if arch:
		p.archipelago_spacing = 64
		p.archipelago_island_radius = 16
		p.archipelago_jitter = 0.35
		p.island_falloff = 2.0
	return p


func _chunk_digest(world, centre: Vector2i, w: int) -> String:
	## sha256 over layer 0, 1 and 2 atlas coords of a w x w square at centre.
	var parts := PackedStringArray()
	for x in range(centre.x - w / 2, centre.x + w / 2):
		for y in range(centre.y - w / 2, centre.y + w / 2):
			var c := Vector2i(x, y)
			parts.append("%s%s%s" % [world.get_cell_atlas_coords(0, c), world.get_cell_atlas_coords(1, c), world.get_cell_atlas_coords(2, c)])
	return ";".join(parts).sha256_text()


func _tap_sequence(pos: Vector2, steps: Array) -> void:
	## Pushes one tap at pos as the given mix of mouse and touch events.
	## "input_touch_*" goes through Input, which adds the emulated mouse
	## events itself, in the order a phone build gets them.
	for step in steps:
		if step.begins_with("input_touch"):
			var t := InputEventScreenTouch.new()
			t.pressed = step.ends_with("down")
			t.position = root.get_final_transform() * pos  # window pixels
			Input.parse_input_event(t)
			Input.flush_buffered_events()
			continue
		var ev: InputEvent
		if step.begins_with("mouse"):
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = step.ends_with("down")
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT if mb.pressed else 0
			mb.position = pos
			mb.global_position = pos
			ev = mb
		else:
			var st := InputEventScreenTouch.new()
			st.index = 0
			st.pressed = step.ends_with("down")
			st.position = pos
			ev = st
		root.push_input(ev, true)


func _free_udp_port() -> int:
	## A random UDP port that ENet can bind right now, or 0. The range is
	## 20000-59999, or FLAGORIA_TEST_PORTS ("LO-HI") when set, so runs in
	## parallel (tools/stress_netcode.py) each pick from their own block.
	## Fixed ports fail when another run or service holds them.
	var lo := 20000
	var hi := 59999
	var pair := OS.get_environment("FLAGORIA_TEST_PORTS").split("-")
	if pair.size() == 2 and pair[0].is_valid_int() and pair[1].is_valid_int():
		lo = pair[0].to_int()
		hi = pair[1].to_int()
	for attempt in range(50):
		var port := randi_range(lo, hi)
		var probe := ENetMultiplayerPeer.new()
		var err := probe.create_server(port)
		probe.close()
		if err == OK:
			return port
	return 0


func _client_connected(smp: SceneMultiplayer, cpeer: ENetMultiplayerPeer) -> bool:
	## Waits up to 10 s for the server to admit the client and the client to
	## see itself connected. A single frame counts for at most 250 ms of that
	## budget, so a pause of the whole process or machine (a VM snapshot, a
	## long scheduler stall) does not use the budget up while ENet, which
	## rides out pauses shorter than its 30 s peer timeout, is still
	## mid-handshake.
	var waited := 0
	var last := Time.get_ticks_msec()
	while (smp.get_peers().is_empty()
			or cpeer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED):
		if waited >= 10000:
			return false
		await process_frame
		var now := Time.get_ticks_msec()
		waited += mini(now - last, 250)
		last = now
	return true


func _chase_spot(world, mob: Mob, tiles: int) -> Variant:
	## A point `tiles` away from `mob` in a straight line of its home ground, or null.
	var home: int = MobCatalog.stat(mob.mob_type, "home")
	var start: Vector2i = world.local_to_map(mob.position)
	for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var ok := true
		for k in range(-1, tiles + 1):
			if not MobSpawner.is_home_cell(world, start + d * k, home):
				ok = false
				break
		if ok:
			return world.map_to_local(start) + Vector2(d * tiles * 16)
	return null


func _contact_player(world_root: Node) -> CharacterBody2D:
	## A bare player body with its own PlayerHealth, enough for mob contact.
	var body := CharacterBody2D.new()
	var health := PlayerHealth.new()
	health.name = "Health"
	body.add_child(health)
	world_root.add_child(body)
	return body


func _sword_on(player: Node2D, mob: Mob) -> void:
	## Move `player` so its sword's hitbox sits on `mob`'s HurtBox.
	var blade: Node2D = player.get_node("weapon/sword/CollisionShape2D")
	player.position += mob.hurt_box.global_position - blade.global_position
	player.velocity = Vector2.ZERO


func _ui_plays_since(ui, before: Dictionary) -> Dictionary:
	## Events that played since `before` (a copy of ui.plays), with counts.
	var delta := {}
	for event in ui.plays:
		if ui.plays[event] != before[event]:
			delta[event] = ui.plays[event] - before[event]
	return delta
