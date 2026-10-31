extends "res://tests/helpers/test_helpers.gd"
## Sword hits during the swing.


func _test_sword_only_hits_mid_swing() -> int:
	## Two real players on the spawn point with physics running: an idle sword
	## overlap deals no damage, a swing still hits, a player respawning beside
	## the other deals no damage, and a dead body does not block movement.
	print("-- test_sword_only_hits_mid_swing")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world: Node = scene.get_node("World")
	var a = load("res://Player/character_body_2d.tscn").instantiate()
	a.name = "2"
	world.add_child(a)
	var b = load("res://Player/character_body_2d.tscn").instantiate()
	b.name = "3"
	world.add_child(b)
	var spawn: Vector2 = a.spawn_position()
	a.position = spawn
	b.position = spawn
	var settle := func() -> void:
		for i in 4:
			await physics_frame

	# Idle swords overlapping the other player's hurt box: no damage either way.
	await settle.call()
	if a.health.health != 6 or b.health.health != 6:
		printerr("FAIL sword_mid_swing idle overlap hurt: a %s, b %s" % [a.health.health, b.health.health])
		fail += 1
	# A swing still hits the player standing there, once.
	a.attack_animation()
	await settle.call()
	if b.health.health != 5 or a.health.health != 6:
		printerr("FAIL sword_mid_swing swing: b %s (want 5), a %s" % [b.health.health, a.health.health])
		fail += 1
	var until := Time.get_ticks_msec() + 3000
	while a.isAttacking and Time.get_ticks_msec() < until:
		await process_frame
	await settle.call()
	if a.isAttacking or not a.sword_shape.disabled:
		printerr("FAIL sword_mid_swing sword still active after the swing")
		fail += 1
	b.health.set_health_now(6)

	# A dead body does not block: b moving into a collides with a only while a
	# is alive. A spare physics layer keeps map tiles out of this check.
	const BODY_LAYER := 1 << 9
	a.collision_layer = BODY_LAYER
	b.collision_mask = BODY_LAYER
	b.position = spawn + Vector2(24, 0)
	await settle.call()
	var hit_alive: KinematicCollision2D = b.move_and_collide(Vector2(-24, 0), true)
	if hit_alive == null or hit_alive.get_collider() != a:
		printerr("FAIL sword_mid_swing live body did not block (%s)" % [hit_alive.get_collider() if hit_alive else null])
		fail += 1
	a.health.take_damage(6)
	await settle.call()
	var hit_dead: KinematicCollision2D = b.move_and_collide(Vector2(-24, 0), true)
	if not a.health.is_dead() or (hit_dead != null and hit_dead.get_collider() == a):
		printerr("FAIL sword_mid_swing dead body still blocks (dead=%s)" % a.health.is_dead())
		fail += 1
	a.isAttacking = true  # a swing in progress when the player died
	if a.sword_active():
		printerr("FAIL sword_mid_swing a dead player's sword is active")
		fail += 1
	a.isAttacking = false
	a.collision_layer = 1
	b.collision_mask = 1

	# Respawn while the other player stands on the spawn: a lands on the free
	# spot next to it (sword in reach), takes no free hit, and blocks again.
	b.position = spawn
	a.position = spawn + Vector2(300, 0)
	await settle.call()
	a.health.advance(a.health.respawn_delay + 0.01)
	await settle.call()
	var next_to: float = a.position.distance_to(spawn)
	if a.health.is_dead() or next_to < world.get_node("worldMap").SPAWN_CLEARANCE \
			or next_to > world.get_node("worldMap").SPAWN_RADIUS or b.health.health != 6:
		printerr("FAIL sword_mid_swing respawn hit: b %s, a at %s (spawn %s)" % [b.health.health, a.position, spawn])
		fail += 1
	if a.body_shape.disabled:
		printerr("FAIL sword_mid_swing body collision still off after respawn")
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_sword_only_hits_mid_swing")
	return fail
