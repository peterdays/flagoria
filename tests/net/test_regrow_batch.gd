extends "res://tests/helpers/test_helpers.gd"
## Regrowth sync messages (#353): one RPC per regrowth tick, and a client
## applies one only when the host (peer 1) sent it. In-process, with a
## MultiplayerAPI stand-in that records RPCs and sets the sender, so no
## network peer is opened.

const CELLS := 4  ## stumps that come due in the same tick


class FakePeer:
	extends MultiplayerPeerExtension
	## Always connected, so Interaction.multiplayer_on sees a session.

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED


class FakeApi:
	extends MultiplayerAPIExtension
	## A host (id 1) with one client, or a client (id 2), whose RPCs are
	## recorded instead of sent; `sender` is what get_remote_sender_id reports.
	var id := 1
	var sender := 0
	var sent: Array = []  ## [peer, method, args] per RPC
	var peer := FakePeer.new()

	func _get_multiplayer_peer() -> MultiplayerPeer:
		return peer

	func _get_unique_id() -> int:
		return id

	func _get_peer_ids() -> PackedInt32Array:
		return PackedInt32Array([2] if id == 1 else [1])

	func _get_remote_sender_id() -> int:
		return sender

	func _rpc(to: int, _object: Object, method: StringName, args: Array) -> Error:
		sent.append([to, method, args])
		return OK

	func _poll() -> Error:
		return OK


func _regrow_scene(api: FakeApi) -> Dictionary:
	## A main scene with the multiplayer stand-in, on the first of a few seeds
	## with CELLS plants (trees or bushes) near the origin, cut at play time
	## 100 with a 30 s delay.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	set_multiplayer(api, scene.get_path())
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var cells: Array[Vector2i] = []
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		cells.clear()
		var used: Array = world.get_used_cells(1)
		used.sort()
		for cell in used:
			if cells.size() < CELLS and world.choppable(cell) != null:
				cells.append(cell)
		if cells.size() == CELLS:
			break
	var atlases := {}
	for cell in cells:
		atlases[cell] = world.get_cell_atlas_coords(1, cell)
	world.regrow_delay = 30.0
	world.play_time = 100.0
	for cell in cells:
		world.cut_choppable(cell)
	return {"scene": scene, "world": world, "interaction": scene.get_node("World/Interaction"),
			"cells": cells, "atlases": atlases}


func _drop_scene(s: Dictionary) -> void:
	set_multiplayer(null, s["scene"].get_path())
	s["scene"].queue_free()
	await process_frame


func _regrow_rpcs(api: FakeApi) -> Array:
	return api.sent.filter(func(r: Array) -> bool: return str(r[1]).begins_with("apply_regrow"))


func _test_regrow_one_rpc_per_tick() -> int:
	## A host with a peer connected: CELLS stumps that come due in the same
	## regrow_due tick go out as one regrowth RPC listing all of them. A
	## client that applies that RPC shows the same plants as the host.
	print("-- test_regrow_one_rpc_per_tick")
	var fail := 0
	var host_api := FakeApi.new()
	var host := _regrow_scene(host_api)
	var cells: Array[Vector2i] = host["cells"]
	if cells.size() < CELLS:
		printerr("FAIL regrow_one_rpc_per_tick: no seed has %d plants near the origin (found %d)" % [CELLS, cells.size()])
		await _drop_scene(host)
		return 1
	host["world"].play_time = 131.0
	var regrew: int = host["world"].regrow_due()
	var rpcs := _regrow_rpcs(host_api)
	if regrew != CELLS or rpcs.size() != 1:
		printerr("FAIL regrow_one_rpc_per_tick: %d stumps regrew in one tick, sent %d regrowth RPCs, want 1: %s"
				% [regrew, rpcs.size(), rpcs])
		fail += 1
	var listed: Array = rpcs[0][2][0] if rpcs.size() == 1 and rpcs[0][2].size() == 1 and rpcs[0][2][0] is Array else []
	if rpcs.size() == 1 and (rpcs[0][0] != 0 or listed.size() != CELLS
			or not cells.all(func(c: Vector2i) -> bool: return listed.has(c))):
		printerr("FAIL regrow_one_rpc_per_tick: the RPC %s does not list %s for every peer" % [rpcs[0], cells])
		fail += 1
	host_api.sent.clear()
	host["world"].play_time = 200.0
	if host["world"].regrow_due() != 0 or not _regrow_rpcs(host_api).is_empty():
		printerr("FAIL regrow_one_rpc_per_tick: a tick with nothing due sent %s" % [host_api.sent])
		fail += 1
	var host_plants := {}
	for cell in cells:
		host_plants[cell] = host["world"].get_cell_atlas_coords(1, cell)
	await _drop_scene(host)

	# A client that holds the same stumps applies the host's one message.
	if listed.size() == CELLS:
		var client_api := FakeApi.new()
		client_api.id = 2
		client_api.sender = 1
		var client := _regrow_scene(client_api)
		var interaction = client["interaction"]
		if interaction.has_method(rpcs[0][1]):
			interaction.callv(rpcs[0][1], rpcs[0][2])
		for cell in cells:
			var here: Vector2i = client["world"].get_cell_atlas_coords(1, cell)
			if here != host_plants[cell] or here != client["atlases"][cell] or client["world"].choppable(cell) == null:
				printerr("FAIL regrow_one_rpc_per_tick: %s is %s on the client, %s on the host" % [cell, here, host_plants[cell]])
				fail += 1
		await _drop_scene(client)
	if fail == 0:
		print("PASS test_regrow_one_rpc_per_tick (%d cells, 1 RPC)" % CELLS)
	return fail


func _test_regrow_refuses_non_host() -> int:
	## A client applies a regrowth message only when its sender is the host
	## (peer 1): from peer 3 (another client) the stumps stay, from peer 1
	## they regrow.
	print("-- test_regrow_refuses_non_host")
	var fail := 0
	var api := FakeApi.new()
	api.id = 2
	var s := _regrow_scene(api)
	var interaction = s["interaction"]
	var world = s["world"]
	var cells: Array[Vector2i] = s["cells"]
	if not interaction.has_method("apply_regrow_cells"):
		printerr("FAIL regrow_refuses_non_host: Interaction has no apply_regrow_cells handler")
		await _drop_scene(s)
		return 1
	for from in [3, 0]:
		api.sender = from
		interaction.apply_regrow_cells(cells)
		for cell in cells:
			if world.choppable(cell) != null:
				printerr("FAIL regrow_refuses_non_host: a message from peer %d regrew %s" % [from, cell])
				fail += 1
				break
	api.sender = 1
	interaction.apply_regrow_cells(cells)
	for cell in cells:
		if world.choppable(cell) == null or world.get_cell_atlas_coords(1, cell) != s["atlases"][cell]:
			printerr("FAIL regrow_refuses_non_host: the host's message did not regrow %s" % cell)
			fail += 1
	await _drop_scene(s)
	if fail == 0:
		print("PASS test_regrow_refuses_non_host")
	return fail
