extends "res://tests/helpers/test_helpers.gd"
## The host's cut request limit (#355): request_cut beyond a peer's
## CutRateLimit bucket is dropped, a drag-sized burst and nonstop dragging
## while walking at top speed all go through, and each peer has its own
## bucket. In-process, with a MultiplayerAPI stand-in that records RPCs and
## sets the sender, so no network peer is opened.

const LIMIT_PATH := "res://Scripts/mechanics/interact/cut_rate_limit.gd"
const EMPTY := Vector2i(100000, 100000)  ## a cell with no plant and out of reach


class FakePeer:
	extends MultiplayerPeerExtension
	## Always connected, so Interaction.multiplayer_on sees a session.

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED


class FakeApi:
	extends MultiplayerAPIExtension
	## A host (id 1) with clients 2 and 3, whose RPCs are recorded instead of
	## sent; `sender` is what get_remote_sender_id reports.
	var sender := 0
	var sent: Array = []  ## one [peer, method, args] for each RPC
	var peer := FakePeer.new()

	func _get_multiplayer_peer() -> MultiplayerPeer:
		return peer

	func _get_unique_id() -> int:
		return 1

	func _get_peer_ids() -> PackedInt32Array:
		return PackedInt32Array([2, 3])

	func _get_remote_sender_id() -> int:
		return sender

	func _rpc(to: int, _object: Object, method: StringName, args: Array) -> Error:
		sent.append([to, method, args])
		return OK

	func _poll() -> Error:
		return OK


func _limit_script() -> GDScript:
	return load(LIMIT_PATH) if ResourceLoader.exists(LIMIT_PATH) else null


func _host_scene(api: FakeApi) -> Dictionary:
	## A host main scene with the stand-in, on the first of a few seeds with
	## two plants near the origin, and a cutter node for peers 2 and 3 on
	## them. The limit's clock is pinned at `now[0]` s, when there is a limit.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	set_multiplayer(api, scene.get_path())
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var cells: Array[Vector2i] = []
	for s in [11, 42, 7, 1, 99]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		cells.clear()
		var used: Array = world.get_used_cells(1)
		used.sort()
		for cell in used:
			if cells.size() < 2 and world.choppable(cell) != null:
				cells.append(cell)
		if cells.size() == 2:
			break
	var interaction = scene.get_node("World/Interaction")
	var now := [0.0]
	var limit = interaction.get("cut_limit")
	if limit != null:
		limit.clock = func() -> float: return now[0]
	for i in cells.size():
		var cutter := Node2D.new()
		cutter.name = str(i + 2)
		scene.get_node("World").add_child(cutter)
		cutter.global_position = interaction.cell_center(cells[i])
	return {"scene": scene, "world": world, "interaction": interaction, "cells": cells, "now": now}


func _drop_scene(s: Dictionary) -> void:
	set_multiplayer(null, s["scene"].get_path())
	s["scene"].queue_free()
	await process_frame


func _cut_by(api: FakeApi, s: Dictionary, peer: int, cell: Vector2i) -> bool:
	## `peer` asks the host to cut `cell`; true when the plant was cut and
	## the peer was sent its yields.
	api.sent.clear()
	api.sender = peer
	s["interaction"].request_cut(cell)
	var yields := api.sent.filter(func(r: Array) -> bool: return r[0] == peer and str(r[1]) == "receive_yields")
	return s["world"].choppable(cell) == null and yields.size() == 1


func _spam(api: FakeApi, s: Dictionary, peer: int, count: int) -> void:
	api.sender = peer
	for i in count:
		s["interaction"].request_cut(EMPTY)


func _test_cut_rate_burst_dropped() -> int:
	## Peer 2 spends its whole bucket (BURST requests in one instant): its
	## next request for a plant in reach is dropped, with no stump and no
	## yields. 1 / RATE s later it has a token again and the plant is cut.
	print("-- test_cut_rate_burst_dropped")
	var script := _limit_script()
	var burst := int(script.BURST) if script else 162
	var api := FakeApi.new()
	var s := _host_scene(api)
	var cells: Array[Vector2i] = s["cells"]
	var fail := 0
	if cells.size() < 2:
		printerr("FAIL cut_rate_burst_dropped: no seed has 2 plants near the origin")
		await _drop_scene(s)
		return 1
	_spam(api, s, 2, burst)
	if _cut_by(api, s, 2, cells[0]) or s["world"].choppable(cells[0]) == null:
		printerr("FAIL cut_rate_burst_dropped: after %d requests in one instant, peer 2's next request cut %s" % [burst, cells[0]])
		fail += 1
	if script:
		s["now"][0] += 1.0 / script.RATE
	if not _cut_by(api, s, 2, cells[0]):
		printerr("FAIL cut_rate_burst_dropped: 1 / RATE s later peer 2 could not cut %s" % cells[0])
		fail += 1
	await _drop_scene(s)
	if fail == 0:
		print("PASS test_cut_rate_burst_dropped (%d requests, then 1 dropped)" % burst)
	return fail


func _test_cut_rate_per_peer() -> int:
	## Peer 2 spends its whole bucket; peer 3 can still cut a plant in its
	## reach in the same instant.
	print("-- test_cut_rate_per_peer")
	var script := _limit_script()
	var api := FakeApi.new()
	var s := _host_scene(api)
	var cells: Array[Vector2i] = s["cells"]
	var fail := 0
	if cells.size() < 2:
		printerr("FAIL cut_rate_per_peer: no seed has 2 plants near the origin")
		await _drop_scene(s)
		return 1
	_spam(api, s, 2, int(script.BURST) if script else 162)
	if not _cut_by(api, s, 3, cells[1]):
		printerr("FAIL cut_rate_per_peer: peer 3 could not cut %s after peer 2 spent its requests" % cells[1])
		fail += 1
	await _drop_scene(s)
	if fail == 0:
		print("PASS test_cut_rate_per_peer")
	return fail


func _test_cut_rate_drag_burst() -> int:
	## The biggest legitimate drag (DRAG_CELLS requests in one instant, the
	## last one for a real plant) all goes through on the host.
	print("-- test_cut_rate_drag_burst")
	var script := _limit_script()
	if script == null:
		printerr("FAIL cut_rate_drag_burst: no %s" % LIMIT_PATH)
		return 1
	var api := FakeApi.new()
	var s := _host_scene(api)
	var cells: Array[Vector2i] = s["cells"]
	var fail := 0
	_spam(api, s, 2, int(script.DRAG_CELLS) - 1)
	if cells.is_empty() or not _cut_by(api, s, 2, cells[0]):
		printerr("FAIL cut_rate_drag_burst: request %d of a drag-sized burst did not cut %s" % [script.DRAG_CELLS, cells])
		fail += 1
	await _drop_scene(s)
	if fail == 0:
		print("PASS test_cut_rate_drag_burst (%d requests)" % script.DRAG_CELLS)
	return fail


func _in_reach(pos: Vector2, tile: float, reach: float) -> Dictionary:
	## Every cell whose centre is within `reach` of `pos`, on `tile` px cells.
	var out := {}
	var lo := Vector2i(floori((pos.x - reach) / tile), floori((pos.y - reach) / tile))
	var hi := Vector2i(floori((pos.x + reach) / tile), floori((pos.y + reach) / tile))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if pos.distance_to((Vector2(x, y) + Vector2(0.5, 0.5)) * tile) <= reach:
				out[Vector2i(x, y)] = true
	return out


func _test_cut_rate_numbers() -> int:
	## The limit's figures match the game: TILE is the tile set's cell size,
	## DRAG_CELLS is the most cell centres within Interaction.REACH of a point
	## (recounted over 1/4 px offsets), and a player dragging every frame
	## while walking 10 s at top speed (straight and diagonal) through a
	## plant on every cell is never refused.
	print("-- test_cut_rate_numbers")
	var script := _limit_script()
	if script == null:
		printerr("FAIL cut_rate_numbers: no %s" % LIMIT_PATH)
		return 1
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	var tiles: TileSet = scene.get_node("World/worldMap").tile_set
	scene.free()
	var tile := float(script.TILE)
	if Vector2(tiles.tile_size) != Vector2(tile, tile):
		printerr("FAIL cut_rate_numbers: tiles are %s px, the limit assumes %s" % [tiles.tile_size, tile])
		fail += 1
	var most := 0
	for a in 64:
		for b in 64:
			most = maxi(most, _in_reach(Vector2(a, b) * tile / 64.0, tile, Interaction.REACH).size())
	if most != script.DRAG_CELLS:
		printerr("FAIL cut_rate_numbers: at most %d cells are in reach, DRAG_CELLS is %d" % [most, script.DRAG_CELLS])
		fail += 1
	var speed := float(preload("res://Scripts/player.gd").MAX_SPEED)
	for dir in [Vector2.RIGHT, Vector2(1, 1).normalized(), Vector2(2, 1).normalized()]:
		var limit = script.new()
		var now := [0.0]
		limit.clock = func() -> float: return now[0]
		var asked := {}
		var refused := 0
		var start := Vector2(3.0, 5.0)
		for frame in 601:
			now[0] = frame / 60.0
			for cell in _in_reach(start + dir * speed * now[0], tile, Interaction.REACH):
				if not asked.has(cell):
					asked[cell] = true
					refused += int(not limit.allow(2))
		if refused > 0:
			printerr("FAIL cut_rate_numbers: walking %s at %d px/s, %d of %d requests were refused" % [dir, speed, refused, asked.size()])
			fail += 1
	if fail == 0:
		print("PASS test_cut_rate_numbers (%d cells in reach, burst %d, %.1f/s)" % [most, script.BURST, script.RATE])
	return fail
