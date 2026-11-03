extends "res://tests/helpers/test_helpers.gd"
## The cut list a joining peer gets (#354): split across messages of at most
## JOIN_CUTS_PER_MESSAGE cuts (flagoria_main.gd), the joiner still ends with
## every cut and its age, and it takes the extra parts only from the host.
## Each message stays under MESSAGE_BYTES encoded.
## In-process, with the MultiplayerAPI stand-in of test_regrow_batch.gd, so
## no network peer is opened.

const Batch := preload("res://tests/net/test_regrow_batch.gd")
const CUTS := 1200  ## host cuts: more than two messages' worth at the cap
const MESSAGE_BYTES := 64 * 1024  ## the most one join message may encode to


func _join_scene(api: MultiplayerAPI) -> Dictionary:
	## A main scene with the stand-in, on the seed-7 map, at play time 100.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	set_multiplayer(api, scene.get_path())
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	scene.world_params = _spawn_params(7, 0.0)
	world.apply_map_params(scene.world_params)
	world.play_time = 100.0
	return {"scene": scene, "world": world}


func _drop(s: Dictionary) -> void:
	set_multiplayer(null, s["scene"].get_path())
	s["scene"].queue_free()
	await process_frame


func _cut_many(world, count: int) -> int:
	## Cut `count` plants the map grows, nearest the origin first (undrawn:
	## the host decides cuts from predict_cell). Ages differ: cut i at play
	## time 100 - i % 50.
	var cut := 0
	var r := 0
	while cut < count and r < 200:
		for x in range(-r, r + 1):
			for y in ([-r, r] if absi(x) != r else range(-r, r + 1)):
				world.play_time = 100.0 - cut % 50
				if cut < count and world.cut_grown(Vector2i(x, y)) != null:
					cut += 1
		r += 1
	world.play_time = 100.0
	return cut


func _cut_count(changes: Dictionary) -> int:
	var n := 0
	for chunk in changes:
		n += (changes[chunk] as Dictionary).size()
	return n


func _cap(scene) -> int:
	return int(scene.get_script().get_script_constant_map().get("JOIN_CUTS_PER_MESSAGE", 0))


func _test_join_cuts_split() -> int:
	## A host holding CUTS cuts syncs a joining peer 2: every message carries
	## at most JOIN_CUTS_PER_MESSAGE cuts, together they list each cut once,
	## and a client that applies them in order holds exactly the host's cuts
	## with the host's ages.
	print("-- test_join_cuts_split")
	var fail := 0
	var host_api := Batch.FakeApi.new()
	var host := _join_scene(host_api)
	var cap := _cap(host["scene"])
	if _cut_many(host["world"], CUTS) != CUTS:
		printerr("FAIL join_cuts_split: found fewer than %d plants to cut" % CUTS)
		await _drop(host)
		return 1
	var want: Dictionary = host["world"].cut_changes()
	host["scene"]._sync_map_params_to_peer(2)
	var msgs: Array = host_api.sent.filter(func(r: Array) -> bool: return r[0] == 2)
	await _drop(host)
	var counts: Array[int] = []
	var biggest := 0
	for m in msgs:
		var args: Array = m[2]
		var cuts: Dictionary = args[2] if str(m[1]) == "receive_map_params" else args[0]
		counts.append(_cut_count(cuts))
		biggest = maxi(biggest, var_to_bytes(args).size())
	var total := counts.reduce(func(a: int, b: int) -> int: return a + b, 0) as int
	if msgs.is_empty() or str(msgs[0][1]) != "receive_map_params" or cap <= 0 or cap >= CUTS \
			or msgs.size() != ceili(CUTS / float(cap)) or counts.any(func(n: int) -> bool: return n > cap) \
			or total != CUTS or biggest > MESSAGE_BYTES:
		printerr("FAIL join_cuts_split: cap %d, %d messages %s carrying %s cuts (total %d of %d), biggest %d bytes (most %d)"
				% [cap, msgs.size(), msgs.map(func(m: Array) -> String: return str(m[1])), counts, total, CUTS,
				biggest, MESSAGE_BYTES])
		fail += 1
	# A client applies the messages in the order the reliable channel keeps.
	var client_api := Batch.FakeApi.new()
	client_api.id = 2
	client_api.sender = 1
	var client := _join_scene(client_api)
	for m in msgs:
		if client["scene"].has_method(m[1]):
			client["scene"].callv(m[1], m[2])
	var got: Dictionary = client["world"].cut_changes()
	if got != want:
		printerr("FAIL join_cuts_split: the client holds %d cuts, the host %d (or ages differ)"
				% [_cut_count(got), _cut_count(want)])
		fail += 1
	await _drop(client)
	if fail == 0:
		print("PASS test_join_cuts_split (%d cuts in %d messages of %s, biggest %d bytes)"
				% [CUTS, msgs.size(), counts, biggest])
	return fail


func _test_join_cuts_host_only() -> int:
	## A client adds the cuts of an extra join message only when its sender
	## is the host (peer 1): from peer 3 or a local call (sender 0) nothing
	## changes.
	print("-- test_join_cuts_host_only")
	var fail := 0
	var host := _join_scene(Batch.FakeApi.new())
	_cut_many(host["world"], 3)
	var cuts: Dictionary = host["world"].cut_changes()
	await _drop(host)
	var api := Batch.FakeApi.new()
	api.id = 2
	var s := _join_scene(api)
	if not s["scene"].has_method("receive_join_cuts"):
		printerr("FAIL join_cuts_host_only: the main scene has no receive_join_cuts handler")
		await _drop(s)
		return 1
	for from in [3, 0]:
		api.sender = from
		s["scene"].receive_join_cuts(cuts)
		if not s["world"].cut_changes().is_empty():
			printerr("FAIL join_cuts_host_only: a message from peer %d added %s" % [from, s["world"].cut_changes()])
			fail += 1
			s["world"].replace_cuts({})
	api.sender = 1
	s["scene"].receive_join_cuts(cuts)
	if s["world"].cut_changes() != cuts:
		printerr("FAIL join_cuts_host_only: the host's message gave %s, want %s" % [s["world"].cut_changes(), cuts])
		fail += 1
	await _drop(s)
	if fail == 0:
		print("PASS test_join_cuts_host_only")
	return fail
