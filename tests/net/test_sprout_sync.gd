extends "res://tests/helpers/test_helpers.gd"
## Tree sprouts in multiplayer (#361): the host decides them and sends one
## apply_sprout_cells per sprout pass (several past SPROUTS_PER_MESSAGE), a
## client applies it only from the host and then shows the host's map, and a
## peer that joins later gets the sprouts in the join cut list. In-process,
## with the MultiplayerAPI stand-in of test_regrow_batch.gd, except
## test_sprout_sync_two_players, which runs real peers in their own
## processes.

const Batch := preload("res://tests/net/test_regrow_batch.gd")
const Sprouts := preload("res://tests/mechanics/trees/test_tree_sprouts.gd")
const PROBE := "res://tests/cut_sync_probe.gd"


func _sprout_scene(api: MultiplayerAPI) -> Dictionary:
	## A main scene on the map of Sprouts.deficit_world (a guard post built
	## alone on chopped trees), then `api` set, with a player named after
	## its id standing on the guard post's anchor and a 5 s regrow delay,
	## so each sprout pass sprouts every missing tree.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var d := Sprouts.deficit_world(world, Sprouts.guard_post())
	set_multiplayer(api, scene.get_path())
	if not d.is_empty():
		scene.world_params = d["params"]
		var player = load("res://Player/character_body_2d.tscn").instantiate()
		player.name = str(api.get_unique_id())
		player.position = world.to_global(world.map_to_local(d["anchor"] + Vector2i(0, 3)))
		scene.get_node("World").add_child(player)
	world.regrow_delay = 5.0
	world.play_time = 100.0
	return {"scene": scene, "world": world, "interaction": scene.get_node("World/Interaction"), "d": d}


func _drop(s: Dictionary) -> void:
	## The player goes first, while the stand-in is still set, so the default
	## multiplayer never sees its synchronizer leave.
	for node in s["scene"].get_node("World").get_children():
		if node is CharacterBody2D:
			node.free()
	set_multiplayer(null, s["scene"].get_path())
	s["scene"].queue_free()
	await process_frame


func _window_cells(world, window: Rect2i) -> Dictionary:
	var out := {}
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			out[Vector2i(x, y)] = world.predict_cell(Vector2i(x, y))
	return out


func _host_pass(label: String) -> Dictionary:
	## A host with a peer connected runs one sprout pass (TreeSprouts.due,
	## called until its area is counted and the pass is done). Returns {host, api, rpcs, cells};
	## FAIL lines name `label`.
	var api := Batch.FakeApi.new()
	var host := _sprout_scene(api)
	var out := {"host": host, "api": api, "rpcs": [], "cells": []}
	if host["d"].is_empty() or host["world"].tree_sprouts() == null:
		printerr("FAIL %s: no area short of trees, or the map has no tree sprouts" % label)
		return out
	var sprouts = host["world"].tree_sprouts()
	for i in 200:
		if sprouts.passes._next_pass > 0.0 and not sprouts.passes.busy():
			break
		sprouts.due()
	out["rpcs"] = api.sent.filter(func(r: Array) -> bool: return str(r[1]) == "apply_sprout_cells")
	if out["rpcs"].size() == 1 and out["rpcs"][0][2].size() == 1:
		out["cells"] = out["rpcs"][0][2][0]
	return out


func _test_sprout_sync_one_rpc() -> int:
	## The host's sprout pass goes out as one apply_sprout_cells for every
	## peer listing each sprouted cell; the client sprouts nothing itself,
	## refuses that message from another peer, and once it applies the
	## host's it predicts and draws the area as the host does.
	print("-- test_sprout_sync_one_rpc")
	var fail := 0
	var h := _host_pass("sprout_sync_one_rpc")
	var host: Dictionary = h["host"]
	var cells: Array = h["cells"]
	var missing: int = 0 if host["d"].is_empty() else host["d"]["target"] - (host["d"]["before"] - host["d"]["lost"].size())
	if h["rpcs"].size() != 1 or h["rpcs"][0][0] != 0 or cells.size() != missing or missing < 1:
		printerr("FAIL sprout_sync_one_rpc: %d trees missing, sent %s" % [missing, h["rpcs"]])
		await _drop(host)
		return 1
	var window: Rect2i = host["d"]["window"]
	var want := _window_cells(host["world"], window)
	await _drop(host)
	var api := Batch.FakeApi.new()
	api.id = 2
	var client := _sprout_scene(api)
	var world = client["world"]
	var step := Vector2i(world.chunk_width, world.chunk_height)
	for cy in range(-1, 2):
		for cx in range(-1, 2):
			world.generate_chunk(world.map_to_local(window.get_center() + step * Vector2i(cx, cy)))
	if not world.tree_sprouts().due().is_empty():
		printerr("FAIL sprout_sync_one_rpc: the client sprouted trees on its own")
		fail += 1
	for from in [3, 0]:
		api.sender = from
		client["interaction"].apply_sprout_cells(cells)
		if world.tree_sprouts().size() != 0:
			printerr("FAIL sprout_sync_one_rpc: a message from peer %d sprouted trees" % from)
			fail += 1
			world.tree_sprouts().clear()
	api.sender = 1
	client["interaction"].callv(h["rpcs"][0][1], h["rpcs"][0][2])
	var got := _window_cells(world, window)
	if got != want:
		var diff: Array = want.keys().filter(func(c: Vector2i) -> bool: return got[c] != want[c])
		printerr("FAIL sprout_sync_one_rpc: %d cells differ from the host, e.g. %s" % [diff.size(), diff.slice(0, 3)])
		fail += 1
	for cell: Vector2i in cells:
		if world.get_cell_atlas_coords(1, cell) != want[cell][1]:
			printerr("FAIL sprout_sync_one_rpc: %s draws %s on the client, the host has %s"
					% [cell, world.get_cell_atlas_coords(1, cell), want[cell][1]])
			fail += 1
			break
	await _drop(client)
	if fail == 0:
		print("PASS test_sprout_sync_one_rpc (%d sprouts in 1 RPC)" % cells.size())
	return fail


func _test_sprout_sync_split() -> int:
	## A sprout pass bigger than Interaction.SPROUTS_PER_MESSAGE goes out in
	## several apply_sprout_cells, each at most that many cells, to every
	## peer, together listing every cell once in order: 1201 cells in
	## 500, 500 and 201.
	print("-- test_sprout_sync_split")
	var api := Batch.FakeApi.new()
	var host := _sprout_scene(api)
	var cells: Array[Vector2i] = []
	for i in 1201:
		cells.append(Vector2i(i % 40, i / 40))
	api.sent.clear()
	host["interaction"]._on_trees_sprouted(cells)
	var rpcs: Array = api.sent.filter(func(r: Array) -> bool: return str(r[1]) == "apply_sprout_cells")
	var sizes: Array = rpcs.map(func(r: Array) -> int: return r[2][0].size())
	var listed: Array[Vector2i] = []
	for r in rpcs:
		listed.append_array(r[2][0])
	await _drop(host)
	if sizes != [500, 500, 201] or listed != cells or rpcs.any(func(r: Array) -> bool: return r[0] != 0):
		printerr("FAIL sprout_sync_split: 1201 cells went out in messages of %s to peers %s, all listed in order: %s"
				% [sizes, rpcs.map(func(r: Array) -> int: return r[0]), listed == cells])
		return 1
	print("PASS test_sprout_sync_split (1201 cells in %d messages of %s)" % [rpcs.size(), sizes])
	return 0


func _test_sprout_sync_late_join() -> int:
	## A peer that joins after the host's sprout pass gets the sprouts in the
	## join messages (receive_map_params and receive_join_cuts) and holds the
	## host's map and the host's cut and sprout list.
	print("-- test_sprout_sync_late_join")
	var fail := 0
	var h := _host_pass("sprout_sync_late_join")
	var host: Dictionary = h["host"]
	if h["cells"].is_empty():
		printerr("FAIL sprout_sync_late_join: the host sprouted nothing")
		await _drop(host)
		return 1
	var window: Rect2i = host["d"]["window"]
	var want := _window_cells(host["world"], window)
	var want_changes: Dictionary = host["world"].cut_changes()
	h["api"].sent.clear()
	host["scene"]._sync_map_params_to_peer(2)
	var msgs: Array = h["api"].sent.filter(func(r: Array) -> bool: return r[0] == 2)
	await _drop(host)
	# A fresh scene joins and applies the messages in order.
	var api := Batch.FakeApi.new()
	api.id = 2
	api.sender = 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	set_multiplayer(api, scene.get_path())
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	for m in msgs:
		if scene.has_method(m[1]):
			scene.callv(m[1], m[2])
	var got := _window_cells(world, window)
	if msgs.is_empty() or got != want or world.cut_changes() != want_changes:
		printerr("FAIL sprout_sync_late_join: %d join messages; the joiner's area matches the host: %s; its list %s, the host's %s"
				% [msgs.size(), got == want, world.cut_changes(), want_changes])
		fail += 1
	set_multiplayer(null, scene.get_path())
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sprout_sync_late_join (%d sprouts in %d join message(s))" % [h["cells"].size(), msgs.size()])
	return fail


func _sprout_keys(data: Dictionary) -> Dictionary:
	## Cell key -> {entry, cell state} for each sprout in a probe's report.
	var out := {}
	var cuts: Dictionary = data.get("cuts", {})
	for chunk in cuts:
		for key in cuts[chunk]:
			if cuts[chunk][key].has("sprout"):
				out[key] = [cuts[chunk][key]["sprout"], data.get("cells", {}).get(key, {}).get("predict")]
	return out


func _test_sprout_sync_two_players() -> int:
	## A host and peers in their own processes (tests/cut_sync_probe.gd).
	## The host loads a save whose trees near the spawn are cut and builds a
	## guard post on them, so its area is short of trees. With sprouting off
	## (regrow delay 0) a client joins; then the host turns it on, sprouts,
	## and the client shows the same sprouts. A peer joining afterwards gets
	## them too, and no peer logs an error.
	print("-- test_sprout_sync_two_players")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var found := {}
	var params: MapGenParams
	for sv in [11, 42, 99, 7, 3]:
		params = Sprouts._static_params(sv)
		params.ensure_seeds()
		scene._apply_params_to_world(params)
		var spawn: Vector2i = world.resolve_player_spawn()
		for r in range(4, 30, 2):
			for dy in range(-r, r + 1, 2):
				for dx in range(-r, r + 1, 2):
					if found.is_empty() and maxi(absi(dx), absi(dy)) == r:
						found = Sprouts._try_anchor(world, Sprouts.guard_post(), spawn + Vector2i(dx, dy), false, spawn)
		if not found.is_empty():
			break
	scene.queue_free()
	await process_frame
	var port := _free_udp_port()
	if found.is_empty() or port == 0:
		printerr("FAIL sprout_sync_two_players: no guard post spot near a spawn (%s) or no free UDP port" % found)
		return 1
	var dir := OS.get_user_data_dir().path_join("sprout_sync_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var world_save := WorldSave.new(params)
	for cell: Vector2i in found["lost"]:
		world_save.object_changes.get_or_add(WorldSave.chunk_key(cell), {})[WorldSave.cell_key(cell)] = {"cut": "tree", "age": 0.0}
	var saved := MapSave.save_world(world_save, "test_sprout_sync_%d_%d" % [OS.get_process_id(), port])
	var outs: Array[String] = []
	var pids: Array[int] = []
	var launch := func(extra: Array) -> void:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE, "--", "--port=%d" % port, "--out=" + outs[-1]]
		args.append_array(extra)
		pids.append(OS.create_process(OS.get_executable_path(), args))
	var read := func(i: int) -> Dictionary:
		var text := FileAccess.get_file_as_string(outs[i]) if FileAccess.file_exists(outs[i]) else ""
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	var like_host := func(i: int) -> bool:
		var host: Dictionary = _sprout_keys(read.call(0))
		return read.call(i).get("ready", false) and not host.is_empty() and _sprout_keys(read.call(i)) == host

	var fail := 0
	launch.call(["--host", "--regrow=0", "--save=" + ProjectSettings.globalize_path(saved["path"]),
			"--place=guard_post@%s" % WorldSave.cell_key(found["anchor"])])
	launch.call(["--regrow=0"])
	if saved["error"] != "" or not await wait_for.call(func() -> bool:
			return read.call(0).get("ready", false) and read.call(1).get("ready", false), 40000):
		printerr("FAIL sprout_sync_two_players: host %s, client %s (save %s)" % [read.call(0), read.call(1), saved["error"]])
		fail += 1
	elif not _sprout_keys(read.call(0)).is_empty():
		printerr("FAIL sprout_sync_two_players: the host sprouted with sprouting off: %s" % read.call(0)["cuts"])
		fail += 1
	else:
		FileAccess.open(outs[0] + ".regrow", FileAccess.WRITE).store_string("5")
		if not await wait_for.call(func() -> bool: return like_host.call(1), 20000):
			printerr("FAIL sprout_sync_two_players: host sprouts %s, client %s"
					% [_sprout_keys(read.call(0)), _sprout_keys(read.call(1))])
			fail += 1
		else:
			launch.call(["--regrow=0"])
			if not await wait_for.call(func() -> bool: return like_host.call(2), 30000):
				printerr("FAIL sprout_sync_two_players: host sprouts %s, late joiner %s"
						% [_sprout_keys(read.call(0)), _sprout_keys(read.call(2))])
				fail += 1
	for i in outs.size():
		if not read.call(i).get("errors", []).is_empty():
			printerr("FAIL sprout_sync_two_players: peer %d logged errors: %s" % [i, read.call(i)["errors"]])
			fail += 1
	var sprouted: int = _sprout_keys(read.call(0)).size()
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
	DirAccess.remove_absolute(saved["path"])
	if fail == 0:
		print("PASS test_sprout_sync_two_players (%d sprouts on host, client and late joiner)" % sprouted)
	return fail
