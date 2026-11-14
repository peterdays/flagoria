extends "res://tests/helpers/test_helpers.gd"
## Points from owned flag towers (FlagsHeldPoints, #275). Each test places
## guard_post towers for the host and calls FlagsHeldPoints.tick by hand, so
## nothing waits on INTERVAL.


func _setup(label: String, n_towers: int) -> Dictionary:
	## Land score is the live total. These tests exercise the flags-held
	## fallback, so they turn land score off and the caller turns it back on.
	## {scene, world, held, points, ids} with `n_towers` host-owned
	## guard_posts near the origin, or {} after a FAIL line.
	LandScore.enabled = false
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var held: FlagsHeldPoints = scene.get_node_or_null("FlagsHeldPoints")
	var points: Points = scene.get_node_or_null("Points")
	if held == null or points == null:
		printerr("FAIL %s: FlagsHeldPoints or Points missing" % label)
		scene.queue_free()
		return {}
	var world = scene.get_node("World/worldMap")
	var s: Structure = StructurePlacer.load_named("guard_post")
	var ids: Array = []
	for sv in [11, 42, 99]:
		world.apply_map_params(_spawn_params(sv, 0.0))
		world.generate_chunk(Vector2(0, 0))
		ids.clear()
		for cell: Vector2i in world.get_used_cells(0):
			if ids.size() >= n_towers:
				break
			var cells: Array = StructurePlacer.footprint(s, cell).keys()
			if not cells.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
				continue
			var id: int = world.place_structure(s, cell, 1)
			if id > 0:
				ids.append(id)
		if ids.size() >= n_towers:
			return {"scene": scene, "world": world, "held": held, "points": points, "ids": ids}
	printerr("FAIL %s: could not place %s guard_posts near the origin on seeds 11, 42, 99" % [label, n_towers])
	scene.queue_free()
	return {}


func _test_flags_held_awards_per_tower() -> int:
	## Two host-owned flag towers pay FLAGS_HELD_POINTS each on every tick
	## (reason flags_held). Three ticks award 2 × 3. Handing one tower to the
	## mobs stops that tower's points on further ticks. Time cost: ~0.2 s.
	print("-- test_flags_held_awards_per_tower")
	var t := _setup("flags_held_awards_per_tower", 2)
	if t.is_empty():
		LandScore.enabled = true
		return 1
	var fail := 0
	var seen: Array = []
	t["points"].total_changed.connect(func(peer_id: int, total: int, amount: int, reason: String) -> void:
		seen.append([peer_id, total, amount, reason]))
	for i in 3:
		var paid: int = t["held"].tick()
		if paid != 2:
			printerr("FAIL flags_held_awards_per_tower: tick %s paid %s towers, want 2" % [i + 1, paid])
			fail += 1
	var per: int = Points.FLAGS_HELD_POINTS
	var want_total: int = 2 * 3 * per
	if t["points"].total_of(1) != want_total:
		printerr("FAIL flags_held_awards_per_tower: total %s, want %s" % [t["points"].total_of(1), want_total])
		fail += 1
	if seen.size() != 6:
		printerr("FAIL flags_held_awards_per_tower: %s awards, want 6 (2 towers × 3 ticks)" % seen.size())
		fail += 1
	elif not seen.all(func(e): return e[0] == 1 and e[2] == per and e[3] == "flags_held"):
		printerr("FAIL flags_held_awards_per_tower: awards %s, want peer 1 / %s / flags_held" % [seen, per])
		fail += 1
	t["world"]._structures.set_owner(t["ids"][0], StructurePlacer.OWNER_MOBS)
	seen.clear()
	var paid_after: int = t["held"].tick()
	if paid_after != 1 or t["points"].total_of(1) != want_total + per:
		printerr("FAIL flags_held_awards_per_tower: after losing a tower paid %s total %s, want 1 and %s"
				% [paid_after, t["points"].total_of(1), want_total + per])
		fail += 1
	if seen != [[1, want_total + per, per, "flags_held"]]:
		printerr("FAIL flags_held_awards_per_tower: after loss awards %s" % [seen])
		fail += 1
	t["scene"].queue_free()
	LandScore.enabled = true
	if fail == 0:
		print("PASS test_flags_held_awards_per_tower")
	return fail


func _test_flags_held_skips_non_players() -> int:
	## Neutral and mob-owned towers never pay. Time cost: ~0.15 s.
	print("-- test_flags_held_skips_non_players")
	var t := _setup("flags_held_skips_non_players", 2)
	if t.is_empty():
		LandScore.enabled = true
		return 1
	var fail := 0
	t["world"]._structures.set_owner(t["ids"][0], StructurePlacer.OWNER_NEUTRAL)
	t["world"]._structures.set_owner(t["ids"][1], StructurePlacer.OWNER_MOBS)
	var paid: int = t["held"].tick()
	if paid != 0 or t["points"].total_of(1) != 0:
		printerr("FAIL flags_held_skips_non_players: paid %s total %s" % [paid, t["points"].total_of(1)])
		fail += 1
	t["scene"].queue_free()
	LandScore.enabled = true
	if fail == 0:
		print("PASS test_flags_held_skips_non_players")
	return fail


func _test_flags_held_off_in_multiplayer() -> int:
	## A connecting client pays no held-flag points. The host does, and Points
	## replicates the totals (#497, test_tower_place_two_players). Back offline
	## this peer awards again. Time cost: ~0.15 s.
	print("-- test_flags_held_off_in_multiplayer")
	var t := _setup("flags_held_off_in_multiplayer", 1)
	if t.is_empty():
		LandScore.enabled = true
		return 1
	var fail := 0
	var path: NodePath = t["held"].get_path()
	var api := SceneMultiplayer.new()
	set_multiplayer(api, path)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", _free_udp_port())
	api.multiplayer_peer = peer
	var paid: int = t["held"].tick()
	if paid != 0 or t["points"].total_of(1) != 0:
		printerr("FAIL flags_held_off_in_multiplayer: paid %s total %s while multiplayer on"
				% [paid, t["points"].total_of(1)])
		fail += 1
	peer.close()
	set_multiplayer(null, path)
	paid = t["held"].tick()
	if paid != 1 or t["points"].total_of(1) != Points.FLAGS_HELD_POINTS:
		printerr("FAIL flags_held_off_in_multiplayer: offline again paid %s total %s"
				% [paid, t["points"].total_of(1)])
		fail += 1
	t["scene"].queue_free()
	LandScore.enabled = true
	if fail == 0:
		print("PASS test_flags_held_off_in_multiplayer")
	return fail
