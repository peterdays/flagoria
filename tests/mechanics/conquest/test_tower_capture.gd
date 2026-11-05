extends "res://tests/helpers/test_helpers.gd"
## Flag towers change hands (TowerCapture, #274). Each test places one
## guard_post for the host (peer 1) and calls TowerCapture.tick by hand, so
## nothing depends on frame timing. DT is exact in binary: 40 ticks are
## exactly CAPTURE_TIME.

const DT := 0.125
const TICKS := 40  # CAPTURE_TIME / DT


func _tower(label: String) -> Dictionary:
	## {scene, world, capture, id, flag (cell), centre (px)} with a host-owned
	## guard_post on clear land near the origin, or {} after a FAIL line.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var s: Structure = StructurePlacer.load_named("guard_post")
	for sv in [11, 42, 99]:
		world.apply_map_params(_spawn_params(sv, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell: Vector2i in world.get_used_cells(0):
			var cells: Array = StructurePlacer.footprint(s, cell).keys()
			if cells.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
				var id: int = world.place_structure(s, cell, 1)
				var flag: Vector2i = world._structures.towers()[id][0]
				return {"scene": scene, "world": world, "capture": scene.get_node("World/TowerCapture"),
					"id": id, "flag": flag, "centre": world.to_global(world.map_to_local(flag))}
	printerr("FAIL %s: no clear guard_post spot near the origin on seeds 11, 42, 99" % label)
	scene.queue_free()
	return {}


func _player(t: Dictionary, peer: int, offset: Vector2) -> CharacterBody2D:
	## A bare living player body for `peer`, `offset` px from the flag centre.
	var body := _contact_player(t["scene"].get_node("World"))
	body.name = str(peer)
	body.global_position = t["centre"] + offset
	return body


func _mob(t: Dictionary, offset: Vector2) -> Mob:
	var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
	mob.setup(MobCatalog.SLIME, t["centre"] + offset, 1)
	t["scene"].get_node("World/Mobs").add_child(mob)
	return mob


func _ticks(t: Dictionary, n: int) -> void:
	for i in n:
		t["capture"].tick(DT)


func _owner(t: Dictionary) -> int:
	return t["world"].placed_structures()[t["id"]]["owner"]


func _progress(t: Dictionary) -> float:
	return t["capture"].progress.get(t["id"], {"progress": 0.0})["progress"]


func _flag_drawn(t: Dictionary) -> Vector2i:
	return t["world"].get_cell_atlas_coords(1, t["flag"])


func _test_tower_capture_completes() -> int:
	## One other side alone inside the area (edge of the 32 px circle) takes
	## the tower in exactly CAPTURE_TIME: not one tick sooner, then the owner
	## is that peer and the flag is redrawn red. Outside the circle nothing
	## starts. Time cost: ~0.15 s.
	print("-- test_tower_capture_completes")
	var t := _tower("tower_capture_completes")
	if t.is_empty():
		return 1
	var fail := 0
	var p := _player(t, 2, Vector2(TowerCapture.CAPTURE_RADIUS + 2, 0))
	_ticks(t, 4)
	if _progress(t) != 0.0:
		printerr("FAIL tower_capture_completes: progress %s from outside the area" % _progress(t))
		fail += 1
	p.global_position = t["centre"] + Vector2(0, TowerCapture.CAPTURE_RADIUS - 1)
	_ticks(t, TICKS - 1)
	if _owner(t) != 1 or _progress(t) != TowerCapture.CAPTURE_TIME - DT:
		printerr("FAIL tower_capture_completes: after %s s owner %s progress %s" % [(TICKS - 1) * DT, _owner(t), _progress(t)])
		fail += 1
	_ticks(t, 1)
	if _owner(t) != 2 or _flag_drawn(t) != TileCatalog.PROP_FLAG_RED or t["capture"].progress.has(t["id"]):
		printerr("FAIL tower_capture_completes: after 5 s owner %s flag %s progress %s" % [_owner(t), _flag_drawn(t), t["capture"].progress])
		fail += 1
	t["scene"].queue_free()
	return fail


func _test_tower_capture_defender_pauses() -> int:
	## A living defender (the owner's side) inside pauses the progress, even
	## with the attacker still in. Time cost: ~0.15 s.
	print("-- test_tower_capture_defender_pauses")
	var t := _tower("tower_capture_defender_pauses")
	if t.is_empty():
		return 1
	var fail := 0
	_player(t, 2, Vector2(8, 0))
	_ticks(t, 16)
	_player(t, 1, Vector2(-8, 0))
	_ticks(t, TICKS)
	if _owner(t) != 1 or _progress(t) != 16 * DT:
		printerr("FAIL tower_capture_defender_pauses: owner %s progress %s, want 1 and %s" % [_owner(t), _progress(t), 16 * DT])
		fail += 1
	t["scene"].queue_free()
	return fail


func _test_tower_capture_drains_when_empty() -> int:
	## Progress drains at the capture rate once the area is empty, down to 0
	## (the entry goes). A different side first drains the old side's
	## progress, then builds its own. Time cost: ~0.15 s.
	print("-- test_tower_capture_drains_when_empty")
	var t := _tower("tower_capture_drains_when_empty")
	if t.is_empty():
		return 1
	var fail := 0
	var p := _player(t, 2, Vector2(8, 0))
	_ticks(t, 16)
	p.global_position = t["centre"] + Vector2(200, 0)
	_ticks(t, 8)
	if _progress(t) != 8 * DT:
		printerr("FAIL tower_capture_drains_when_empty: progress %s after 1 s empty, want %s" % [_progress(t), 8 * DT])
		fail += 1
	_ticks(t, 9)
	if t["capture"].progress.has(t["id"]):
		printerr("FAIL tower_capture_drains_when_empty: progress left %s" % t["capture"].progress)
		fail += 1
	p.global_position = t["centre"]
	_ticks(t, 8)
	p.global_position = t["centre"] + Vector2(200, 0)
	var q := _player(t, 3, Vector2(0, 8))
	_ticks(t, 4)
	if t["capture"].progress[t["id"]]["side"] != 2 or _progress(t) != 4 * DT:
		printerr("FAIL tower_capture_drains_when_empty: other side %s at %s, want 2's progress drained to %s" % [
			t["capture"].progress[t["id"]]["side"], _progress(t), 4 * DT])
		fail += 1
	_ticks(t, 6)
	if t["capture"].progress[t["id"]]["side"] != 3 or _progress(t) != 2 * DT:
		printerr("FAIL tower_capture_drains_when_empty: side 3 at %s, want its own %s" % [_progress(t), 2 * DT])
		fail += 1
	q.queue_free()
	t["scene"].queue_free()
	return fail


func _test_tower_capture_contested() -> int:
	## Two other sides inside (two peers, or a peer and a mob) freeze the
	## progress. Time cost: ~0.15 s.
	print("-- test_tower_capture_contested")
	var t := _tower("tower_capture_contested")
	if t.is_empty():
		return 1
	var fail := 0
	_player(t, 2, Vector2(8, 0))
	_ticks(t, 8)
	var q := _player(t, 3, Vector2(-8, 0))
	_ticks(t, TICKS)
	if _progress(t) != 8 * DT or _owner(t) != 1:
		printerr("FAIL tower_capture_contested: two peers left progress %s owner %s" % [_progress(t), _owner(t)])
		fail += 1
	q.free()
	_mob(t, Vector2(0, -8))
	_ticks(t, TICKS)
	if _progress(t) != 8 * DT or _owner(t) != 1:
		printerr("FAIL tower_capture_contested: peer and mob left progress %s owner %s" % [_progress(t), _owner(t)])
		fail += 1
	t["scene"].queue_free()
	return fail


func _test_tower_capture_dead_players() -> int:
	## A dead player inside counts for no side: it neither captures nor
	## defends. Time cost: ~0.15 s.
	print("-- test_tower_capture_dead_players")
	var t := _tower("tower_capture_dead_players")
	if t.is_empty():
		return 1
	var fail := 0
	var p := _player(t, 2, Vector2(8, 0))
	p.get_node("Health").health = 0
	_ticks(t, TICKS)
	if _progress(t) != 0.0 or _owner(t) != 1:
		printerr("FAIL tower_capture_dead_players: dead attacker made progress %s owner %s" % [_progress(t), _owner(t)])
		fail += 1
	p.get_node("Health").health = p.get_node("Health").max_health
	var d := _player(t, 1, Vector2(-8, 0))
	d.get_node("Health").health = 0
	_ticks(t, 8)
	if _progress(t) != 8 * DT:
		printerr("FAIL tower_capture_dead_players: a dead defender paused it at %s" % _progress(t))
		fail += 1
	t["scene"].queue_free()
	return fail


func _test_tower_capture_mob() -> int:
	## A mob standing in the area takes the tower for the mobs (purple flag);
	## a dying mob does not count. Time cost: ~0.15 s.
	print("-- test_tower_capture_mob")
	var t := _tower("tower_capture_mob")
	if t.is_empty():
		return 1
	var fail := 0
	var mob := _mob(t, Vector2(0, 8))
	mob.state = Mob.State.DYING
	_ticks(t, 8)
	if _progress(t) != 0.0:
		printerr("FAIL tower_capture_mob: a dying mob made progress %s" % _progress(t))
		fail += 1
	mob.state = Mob.State.IDLE
	_ticks(t, TICKS)
	if _owner(t) != StructurePlacer.OWNER_MOBS or _flag_drawn(t) != TileCatalog.PROP_FLAG_MOBS:
		printerr("FAIL tower_capture_mob: owner %s flag %s" % [_owner(t), _flag_drawn(t)])
		fail += 1
	t["scene"].queue_free()
	return fail


func _test_tower_capture_changes_owner_and_flag_only() -> int:
	## A capture changes the placement's owner and its flag cell, nothing
	## else: every other footprint cell on every layer, the name and the
	## anchor stay; predict_cell gives the new flag. The new owner is kept
	## where placements are copied today (to_sync -> replace_from_host, the
	## list a joining peer gets); saving placements to disk is #42.
	## Time cost: ~0.15 s.
	print("-- test_tower_capture_changes_owner_and_flag_only")
	var t := _tower("tower_capture_changes_owner_and_flag_only")
	if t.is_empty():
		return 1
	var fail := 0
	var world = t["world"]
	var before: Dictionary = world.placed_structures()[t["id"]]
	var anchor: Vector2i = before["anchor"]
	var cells := {}
	for c: Vector2i in StructurePlacer.footprint(StructurePlacer.load_named("guard_post"), anchor):
		cells[c] = [world.get_cell_atlas_coords(0, c), world.get_cell_atlas_coords(1, c),
			world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, c)]
	_mob(t, Vector2(0, 8))
	_ticks(t, TICKS)
	var after: Dictionary = world.placed_structures()[t["id"]]
	if after["owner"] != StructurePlacer.OWNER_MOBS or after["name"] != before["name"] or after["anchor"] != anchor:
		printerr("FAIL tower_capture_changes_owner_and_flag_only: placement %s, was %s" % [after, before])
		fail += 1
	for c: Vector2i in cells:
		var now := [world.get_cell_atlas_coords(0, c), world.get_cell_atlas_coords(1, c),
			world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, c)]
		var want: Array = cells[c].duplicate()
		if c == t["flag"]:
			want[1] = TileCatalog.PROP_FLAG_MOBS
		if now != want:
			printerr("FAIL tower_capture_changes_owner_and_flag_only: %s now %s, want %s" % [c, now, want])
			fail += 1
	if world.predict_cell(t["flag"])[1] != TileCatalog.PROP_FLAG_MOBS:
		printerr("FAIL tower_capture_changes_owner_and_flag_only: predict_cell gives %s" % [world.predict_cell(t["flag"])])
		fail += 1
	var list: Array = world.structures_for_sync()
	world.replace_structures(list)
	var flag_after: Vector2i = world._structures.towers()[t["id"]][0]
	if world.placed_structures()[t["id"]]["owner"] != StructurePlacer.OWNER_MOBS \
			or world._structures.object_at(flag_after) != TileCatalog.PROP_FLAG_MOBS:
		printerr("FAIL tower_capture_changes_owner_and_flag_only: after replace_structures %s" % [world.placed_structures()])
		fail += 1
	t["scene"].queue_free()
	return fail


func _test_tower_capture_off_in_multiplayer() -> int:
	## While multiplayer is on (here a connecting client) no tower moves;
	## live capture sync is #278. Back offline it runs again. Time cost: ~0.15 s.
	print("-- test_tower_capture_off_in_multiplayer")
	var t := _tower("tower_capture_off_in_multiplayer")
	if t.is_empty():
		return 1
	var fail := 0
	_player(t, 2, Vector2(8, 0))
	var path: NodePath = t["capture"].get_path()
	var api := SceneMultiplayer.new()
	set_multiplayer(api, path)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", _free_udp_port())
	api.multiplayer_peer = peer
	_ticks(t, TICKS)
	if _progress(t) != 0.0 or _owner(t) != 1:
		printerr("FAIL tower_capture_off_in_multiplayer: progress %s owner %s" % [_progress(t), _owner(t)])
		fail += 1
	peer.close()
	set_multiplayer(null, path)
	_ticks(t, 1)
	if _progress(t) != DT:
		printerr("FAIL tower_capture_off_in_multiplayer: offline again progress %s" % _progress(t))
		fail += 1
	t["scene"].queue_free()
	return fail
