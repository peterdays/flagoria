extends "res://tests/helpers/test_helpers.gd"
## The sword's reach (#334): 30 px from the aim cone's apex, the same
## length as the cone, and hits land there but not beyond.

const REACH := AimConeStyle.SWORD_REACH  ## px from AttackAim.ORIGIN to the hitbox's farthest corner, the longest swing (Up)
const REACH_MIN := 27.0  ## the shortest swing's reach (Down, ~27.4 px; 18.9 px before #334)
const ANGLES := [0.0, 90.0, 180.0, -90.0, 30.0, -60.0, 115.0, 160.0]  ## aim angles, degrees


func _corners(player) -> Array:
	## The sword hitbox's corners, from the cone's apex, in the player's space.
	var shape: CollisionShape2D = player.sword_shape
	var half: Vector2 = shape.shape.size / 2.0
	var out := []
	for c in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		out.append(player.to_local(shape.global_transform * c) - AttackAim.ORIGIN)
	return out


func _swing_at(player, angle: float) -> void:
	## A swing at `angle` (radians), as an aimed release sends it.
	player.attack_animation(AttackAim.direction_name(Vector2.from_angle(angle)), angle)


func _test_sword_reach() -> int:
	## The cone is drawn at the sword's reach. Over a whole swing the hitbox
	## reaches 30 px at most (21.5 px before #334) and at least REACH_MIN at
	## every aim angle, never past the cone's length; mid-swing the whole
	## hitbox is inside the cone drawn for that aim.
	print("-- test_sword_reach")
	var fail := 0
	await process_frame
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	await process_frame
	var cone_range: float = AttackAim.new().style.range
	if cone_range != REACH:
		printerr("FAIL sword_reach the cone is %s px, the sword reaches %s px" % [cone_range, REACH])
		fail += 1
	var longest := 0.0
	var reaches := []
	for deg in ANGLES:
		var angle := deg_to_rad(deg)
		_swing_at(player, angle)
		var far := 0.0
		for i in 20:  # the swing's 0.2 s, short of its end
			player.animations.seek(0.01 * i, true)
			for c in _corners(player):
				far = maxf(far, c.length())
		longest = maxf(longest, far)
		reaches.append("%s deg %.1f" % [deg, far])
		if far < REACH_MIN or far > cone_range:
			printerr("FAIL sword_reach %s deg reaches %.1f px, want %s-%s within the %s px cone"
					% [deg, far, REACH_MIN, REACH, cone_range])
			fail += 1
		player.animations.seek(0.1, true)
		for c in _corners(player):
			if c.length() > cone_range or absf(angle_difference(angle, c.angle())) > AttackAim.ARC / 2.0:
				printerr("FAIL sword_reach %s deg mid-swing corner %s is outside the cone" % [deg, c])
				fail += 1
		while player.isAttacking:
			await process_frame
	if absf(longest - REACH) > 0.5:
		printerr("FAIL sword_reach the longest swing reaches %.1f px, want ~%s" % [longest, REACH])
		fail += 1
	player.queue_free()
	if fail == 0:
		print("PASS test_sword_reach (cone %s px; reach %s)" % [cone_range, ", ".join(reaches)])
	return fail


func _test_sword_reach_mob() -> int:
	## A mob whose hurt box starts 24 px out along the aim (past the old
	## 21.5 px reach) is hit by one swing; one starting 30 px out (past the
	## new reach) is not. Off-axis aims included.
	print("-- test_sword_reach_mob")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	scene.spawn_mobs()
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = "1"
	scene.get_node("World").add_child(player)
	player.set_physics_process(false)
	player.health.max_health = 1000  # contact damage is not under test here
	player.health.set_health_now(1000)
	var mobs: Array = scene.get_node("World/Mobs").mobs()
	if mobs.is_empty():
		printerr("FAIL sword_reach_mob no mob on seed 42")
		scene.queue_free()
		return 1
	var mob: Mob = mobs[0]
	var half: Vector2 = MobCatalog.stat(mob.mob_type, "hurtbox") / 2.0
	var apex: Vector2 = player.to_global(AttackAim.ORIGIN)
	var place := func(angle: float, near: float) -> void:
		# The hurt box's centre on the aim ray, its near edge `near` px out.
		var u := Vector2.from_angle(angle)
		var t := minf(half.x / maxf(absf(u.x), 0.0001), half.y / maxf(absf(u.y), 0.0001))
		mob.position += apex + u * (near + t) - mob.hurt_box.global_position
	for deg in [30.0, 115.0]:
		for near in [24.0, 30.0]:
			var angle := deg_to_rad(deg)
			mob.hp = 99
			while mob.state == Mob.State.HURT:  # out of the last hit's hurt window
				place.call(angle, near)
				await physics_frame
			for i in 4:
				place.call(angle, near)
				await physics_frame
			_swing_at(player, angle)
			while player.isAttacking:
				place.call(angle, near)
				await physics_frame
			for i in 3:
				place.call(angle, near)
				await physics_frame
			var hit := mob.hp < 99
			if hit != (near < REACH):
				printerr("FAIL sword_reach_mob %s deg, hurt box %s px out: hit %s" % [deg, near, hit])
				fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_sword_reach_mob (%s)" % mob.mob_type)
	return fail
