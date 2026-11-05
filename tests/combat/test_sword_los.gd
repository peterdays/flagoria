extends "res://tests/helpers/test_helpers.gd"
## Sword line-of-sight: a solid cell between the swing origin and the mob
## blocks the hit (#339). Solid means the same terrain physics layer that
## blocks walking (walls, water, trees); an open gate's centre gap does not.


func _paint_pad(world, cells: Array) -> void:
	## Grass pad on layer 0 for every cell in `cells` and a one-cell border.
	## Freezes chunk redraw so paint survives; awaits are the caller's.
	world.set_process(false)
	world.clear()
	var seen := {}
	for c in cells:
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			seen[n] = true
			world.set_cell(0, n, TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)


func _setup() -> Dictionary:
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = "1"
	scene.get_node("World").add_child(player)
	player.set_physics_process(false)
	player.health.max_health = 1000
	player.health.set_health_now(1000)
	var mob_scene: PackedScene = load("res://Mobs/mob.tscn")
	var mob: Mob = mob_scene.instantiate()
	mob.mob_type = "slime" if "slime" in MobCatalog.names() else MobCatalog.names()[0]
	scene.get_node("World/Mobs").add_child(mob)
	mob.hp = 99
	return {"scene": scene, "world": world, "player": player, "mob": mob}


func _across_cell(world, player: Node2D, mob: Mob, mid: Vector2i) -> void:
	## Put the swing origin just west of `mid` and the hurt box just east, so
	## a horizontal ray through `mid`'s centre crosses that cell (~20 px).
	var mid_c: Vector2 = world.to_global(world.map_to_local(mid))
	# ORIGIN = player.global + (0, -3); put ORIGIN at mid_c + (-10, 0).
	player.global_position = mid_c + Vector2(-10, 3)
	# hurt_box.global = mob.position + (0, HURTBOX_Y); put hurt box at mid_c + (10, 0).
	mob.position = mid_c + Vector2(10, -MobCatalog.HURTBOX_Y)


func _across_diagonal(world, player: Node2D, mob: Mob, mid: Vector2i) -> void:
	## Same idea on the SE diagonal: origin NW of `mid`, hurt box SE of it.
	var mid_c: Vector2 = world.to_global(world.map_to_local(mid))
	player.global_position = mid_c + Vector2(-8, -8 + 3)
	mob.position = mid_c + Vector2(8, 8 - MobCatalog.HURTBOX_Y)


func _swing_right(player: Node2D) -> void:
	player.attack_animation("Right", 0.0)
	while player.isAttacking:
		await physics_frame
	for i in 3:
		await physics_frame


func _swing_toward(player: Node2D, from: Vector2, to: Vector2) -> void:
	var angle := (to - from).angle()
	var dir: String = AttackAim.direction_name(Vector2.from_angle(angle))
	player.attack_animation(dir, AttackAim.turn_to(dir, angle))
	while player.isAttacking:
		await physics_frame
	for i in 3:
		await physics_frame


func _test_sword_los_clear_hits() -> int:
	## No solid between the swing origin and the mob: one swing hits.
	## Time cost: ~0.3 s in verify (~2 s alone with --only=).
	print("-- test_sword_los_clear_hits")
	var s := _setup()
	var world = s["world"]
	var player: Node2D = s["player"]
	var mob: Mob = s["mob"]
	var mid := Vector2i(9, 8)
	_paint_pad(world, [mid])
	_across_cell(world, player, mob, mid)
	await physics_frame
	await physics_frame
	var hp0: int = mob.hp
	await _swing_right(player)
	var fail := 0
	if mob.hp >= hp0:
		printerr("FAIL sword_los_clear_hits: clear LOS did not hit (hp %s -> %s)" % [hp0, mob.hp])
		fail += 1
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sword_los_clear_hits")
	return fail


func _test_sword_los_wall_blocks() -> int:
	## A closed palisade cell between player and mob blocks the hit. Diagonal
	## too. Time cost: ~0.4 s in verify (~2.2 s alone with --only=).
	print("-- test_sword_los_wall_blocks")
	var s := _setup()
	var world = s["world"]
	var player: Node2D = s["player"]
	var mob: Mob = s["mob"]
	var fail := 0
	for case in [
		{"mid": Vector2i(9, 8), "diag": false, "label": "cardinal"},
		{"mid": Vector2i(9, 9), "diag": true, "label": "diagonal"},
	]:
		_paint_pad(world, [case["mid"]])
		world.set_cell(1, case["mid"], TileCatalog.SOURCE_ID, TileCatalog.PALISADE_H)
		if case["diag"]:
			_across_diagonal(world, player, mob, case["mid"])
		else:
			_across_cell(world, player, mob, case["mid"])
		mob.hp = 99
		while mob.state == Mob.State.HURT:
			await physics_frame
		await physics_frame
		await physics_frame
		if case["diag"]:
			await _swing_toward(player, player.to_global(AttackAim.ORIGIN), mob.hurt_box.global_position)
		else:
			await _swing_right(player)
		if mob.hp != 99:
			printerr("FAIL sword_los_wall_blocks %s: wall did not block (hp %s)" % [case["label"], mob.hp])
			fail += 1
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sword_los_wall_blocks")
	return fail


func _test_sword_los_open_gate_hits() -> int:
	## An open V-gate leaves an east-west gap: the ray through the opening still hits.
	## Time cost: ~0.3 s in verify (~2 s alone with --only=).
	print("-- test_sword_los_open_gate_hits")
	var s := _setup()
	var world = s["world"]
	var player: Node2D = s["player"]
	var mob: Mob = s["mob"]
	var mid := Vector2i(9, 8)
	_paint_pad(world, [mid])
	# V-open posts sit on the north/south edges; the gap runs east-west.
	world.set_cell(1, mid, TileCatalog.SOURCE_ID, TileCatalog.PALISADE_GATE_V_OPEN)
	_across_cell(world, player, mob, mid)
	await physics_frame
	await physics_frame
	var hp0: int = mob.hp
	await _swing_right(player)
	var fail := 0
	if mob.hp >= hp0:
		printerr("FAIL sword_los_open_gate_hits: open gate blocked the hit (hp %s -> %s)" % [hp0, mob.hp])
		fail += 1
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sword_los_open_gate_hits")
	return fail


func _test_sword_los_tree_blocks() -> int:
	## A tree with collision (same solid that blocks walking) between the
	## swing and the mob blocks the hit. Time cost: ~0.3 s in verify (~2 s
	## alone with --only=).
	print("-- test_sword_los_tree_blocks")
	var s := _setup()
	var world = s["world"]
	var player: Node2D = s["player"]
	var mob: Mob = s["mob"]
	var mid := Vector2i(9, 8)
	_paint_pad(world, [mid])
	world.set_cell(1, mid, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	_across_cell(world, player, mob, mid)
	await physics_frame
	await physics_frame
	mob.hp = 99
	await _swing_right(player)
	var fail := 0
	if mob.hp != 99:
		printerr("FAIL sword_los_tree_blocks: tree did not block (hp %s)" % mob.hp)
		fail += 1
	s["scene"].queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sword_los_tree_blocks")
	return fail
