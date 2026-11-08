extends "res://.cursor/skills/verify-flagoria/drives/dedicated_play/play_common.gd"
## Client A of the dedicated pair. Joins localhost:9786, chops the nearest
## plant in the spawn chunk, then walks to the nearest mob and swings until
## it dies. Start the server, then client B, then this drive.

const CHOP_S := 12.0
const FIGHT_S := 25.0


func run() -> void:
	if not await join_dedicated("client-a"):
		return
	await snapshot("joined")
	step("cut")
	if not await wait_until(func() -> bool: return _remember_plant(), 10.0):
		_fail("no drawn plant near the spawn")
		return
	var before := wood()
	await toggle_mode()
	var it: Node = current_scene.get_node(INTERACTION)
	if not await wait_until(func() -> bool: return it.mode == 1, 2.0):
		_fail("mode button did not reach interact")
		return
	await tap_cell(_plant)
	if not await wait_until(func() -> bool: return wood() > before, CHOP_S):
		await tap_cell(_plant)
	if not await wait_until(func() -> bool: return wood() > before, CHOP_S):
		_fail("chop did not yield wood at %s" % _plant)
		return
	print("dedicated_play: client-a cut %s wood %s -> %s" % [_plant, before, wood()])
	await snapshot("after-cut")
	step("hit")
	await toggle_mode()
	var killed := false
	var label := ""
	for mob in mobs_by_distance():
		if not is_instance_valid(mob):
			continue
		label = "%s %s" % [mob.name, mob.mob_type]
		if await _fight(mob):
			killed = true
			break
		print("dedicated_play: client-a could not reach %s" % label)
	print("dedicated_play: client-a hit %s killed=%s" % [label, killed])
	await snapshot("after-hit")
	done(wood() > before and killed)


var _plant := Vector2i(999999, 999999)


func _remember_plant() -> bool:
	_plant = nearest_plant()
	return _plant != Vector2i(999999, 999999) and plant_drawn(_plant)


func _fight(mob: Mob) -> bool:
	if not await _walk_near(mob):
		return false
	var end := Time.get_ticks_msec() + int(FIGHT_S * 1000.0)
	var saw_hurt := false
	var saw_dying := false
	while is_instance_valid(mob) and Time.get_ticks_msec() < end and mob.state != Mob.State.DYING:
		if hero().global_position.distance_to(mob.global_position) > 40.0:
			if not await _walk_near(mob):
				if saw_hurt:
					continue
				break
		await _face(mob)
		await tap("attack")
		var swing := Time.get_ticks_msec() + 700
		while is_instance_valid(mob) and Time.get_ticks_msec() < swing:
			saw_hurt = saw_hurt or mob.state == Mob.State.HURT
			saw_dying = saw_dying or mob.state == Mob.State.DYING
			await physics_frame
	var dead := not is_instance_valid(mob) or (is_instance_valid(mob) and mob.state == Mob.State.DYING)
	print("dedicated_play: client-a %s hurt=%s dying=%s dead=%s" % [mob.name if is_instance_valid(mob) else "gone", saw_hurt, saw_dying, dead])
	return saw_hurt and dead


func _face(mob: Mob) -> void:
	if not is_instance_valid(mob) or hero() == null:
		return
	var delta := mob.global_position - hero().global_position
	var action := "ui_right"
	if absf(delta.x) >= absf(delta.y):
		action = "ui_right" if delta.x > 0.0 else "ui_left"
	else:
		action = "ui_down" if delta.y > 0.0 else "ui_up"
	await hold(action, 2)


func _walk_near(mob: Mob) -> bool:
	## Follow clear ground toward the mob. A straight line stops on bushes.
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var path := _path_to(map, mob)
	if path.is_empty():
		print("dedicated_play: client-a no path to %s" % mob.name)
		return hero().global_position.distance_to(mob.global_position) <= 36.0
	for cell in path:
		if not is_instance_valid(mob):
			return false
		var end := Time.get_ticks_msec() + 1500
		while Time.get_ticks_msec() < end:
			var here: Vector2i = map.local_to_map(map.to_local(hero().global_position))
			if here == cell or hero().global_position.distance_to(map.map_to_local(cell)) < 10.0:
				break
			var delta := map.map_to_local(cell) - hero().global_position
			var action := "ui_right"
			if absf(delta.x) >= absf(delta.y):
				action = "ui_right" if delta.x > 0.0 else "ui_left"
			else:
				action = "ui_down" if delta.y > 0.0 else "ui_up"
			await hold(action, 2)
		if map.local_to_map(map.to_local(hero().global_position)) != cell \
				and hero().global_position.distance_to(map.map_to_local(cell)) >= 10.0:
			return false
	return is_instance_valid(mob) and hero().global_position.distance_to(mob.global_position) <= 48.0


func _path_to(map: TileMap, mob: Mob) -> Array[Vector2i]:
	var start: Vector2i = map.local_to_map(map.to_local(hero().global_position))
	var goal: Vector2i = map.local_to_map(map.to_local(mob.global_position))
	var prev := {}
	var q: Array[Vector2i] = [start]
	prev[start] = start
	var head := 0
	var stand := start
	var found := false
	while head < q.size() and q.size() < 400:
		var cur: Vector2i = q[head]
		head += 1
		if maxi(absi(cur.x - goal.x), absi(cur.y - goal.y)) <= 1 and cur != goal:
			stand = cur
			found = true
			break
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nxt: Vector2i = cur + step
			if prev.has(nxt):
				continue
			if nxt != start and not map.is_clear_ground(nxt):
				continue
			prev[nxt] = cur
			q.append(nxt)
	if not found:
		return []
	var path: Array[Vector2i] = []
	var at := stand
	while at != start:
		path.append(at)
		at = prev[at]
	path.reverse()
	return path
