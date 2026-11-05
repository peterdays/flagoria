extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## Combat and HUD drive: the HUD a new hero sees, a plain swing, an aimed
## touch swing off the four-way axes, and the in-game menu blocking an aim.
## Start it with `bin/launch.sh drives/combat_hud.gd` (any seed).

const HEARTS := "CanvasLayer1/HeartsHud"
const SCORE := "CanvasLayer1/ScoreHud"
const ATTACK_BUTTON := "CanvasLayer1/TouchScreenButton"
const RESUME_BUTTON := "CanvasLayer1/InGameMenu/Pause/Panel/Margin/VBox/Resume"
const FULL_HEALTH := 6  ## half-hearts (Scripts/player_health.gd)
## The aimed swing: a drag this far from the button's centre (viewport px,
## past the 8 px dead zone) at this angle. -60 degrees is 30 degrees right of
## Up, so the hero faces Up and the swing turns +30 degrees.
const DRAG_PX := 30.0
const DRAG_DEG := -60.0
const EXPECT_TURN_DEG := 30.0
const SWING_TIMEOUT_S := 2.0


func run() -> void:
	if not await start_game():
		return
	var ok := true
	step("hud")
	var hearts := current_scene.get_node(HEARTS)
	var score: Label = current_scene.get_node(SCORE)
	print("combat_hud: hearts %d/%d, score '%s'" % [hearts.current, hearts.maximum, score.text])
	ok = ok and hearts.current == FULL_HEALTH and hearts.maximum == FULL_HEALTH and score.text == "0 pts"
	await snapshot("start")

	step("swing")
	var facing: String = hero().lastAnimDirection
	await tap("attack")
	var swung := await wait_until(func() -> bool: return hero().isAttacking, SWING_TIMEOUT_S)
	print("combat_hud: plain swing %s, facing %s -> %s" % [swung, facing, hero().lastAnimDirection])
	ok = ok and swung and hero().lastAnimDirection == facing
	await wait_until(func() -> bool: return not hero().isAttacking, SWING_TIMEOUT_S)

	step("aim")
	var aim: Node = hero().get_node("AttackAim")
	var offset := Vector2.from_angle(deg_to_rad(DRAG_DEG)) * DRAG_PX
	await touch_drag(offset, func() -> void:
		print("combat_hud: aiming %s toward %s at %.0f deg" % [aim.aiming, aim.aim_direction(), rad_to_deg(aim.aim_angle())])
		ok = ok and aim.aiming and aim.aim_direction() == "Up")
	swung = await wait_until(func() -> bool: return hero().isAttacking, SWING_TIMEOUT_S)
	var turn := rad_to_deg(hero().swing_turn)
	print("combat_hud: aimed swing %s, facing %s, turn %.0f deg" % [swung, hero().lastAnimDirection, turn])
	ok = ok and swung and hero().lastAnimDirection == "Up" and absf(turn - EXPECT_TURN_DEG) < 1.0
	await snapshot("aimed-swing")
	await wait_until(func() -> bool: return not hero().isAttacking, SWING_TIMEOUT_S)

	step("menu")
	await click(MENU_BUTTON)
	var panel: Control = current_scene.get_node(MENU_PANEL)
	var opened := await wait_until(func() -> bool: return panel.is_visible_in_tree(), 5.0)
	await touch_drag(offset, func() -> void:
		print("combat_hud: menu open %s, aiming %s" % [opened, aim.aiming])
		ok = ok and opened and not aim.aiming)
	for i in range(10):
		await physics_frame
	print("combat_hud: swing under the menu %s" % hero().isAttacking)
	ok = ok and not hero().isAttacking
	await snapshot("menu-open")
	await click(RESUME_BUTTON)
	await process_frame
	print("combat_hud: menu closed %s" % (not panel.is_visible_in_tree()))
	ok = ok and not panel.is_visible_in_tree()
	step("sword-los")
	ok = ok and await _sword_los_shots()

	done(ok)


## Paint a closed pad east of the hero with a palisade, then an open gate;
## place a slime past each; snapshot the blocked swing and the clear gap.
## Headless tests cover the hit/miss; these shots are the player-facing proof (#339).
func _sword_los_shots() -> bool:
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var mobs_root: Node = current_scene.get_node("World/Mobs")
	var h := hero()
	var stand: Vector2i = map.local_to_map(map.to_local(h.global_position))
	var mid: Vector2i = stand + Vector2i(4, 0)
	# Clean grass pad so no leftover trees/walls sit on the ray.
	for x in range(mid.x - 2, mid.x + 3):
		for y in range(mid.y - 2, mid.y + 3):
			var c := Vector2i(x, y)
			map.set_cell(0, c, TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
			map.erase_cell(1, c)
	map.set_cell(1, mid, TileCatalog.SOURCE_ID, TileCatalog.PALISADE_H)
	var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
	mob.mob_type = "slime" if "slime" in MobCatalog.names() else MobCatalog.names()[0]
	mobs_root.add_child(mob)
	mob.hp = 99
	var mid_c: Vector2 = map.to_global(map.map_to_local(mid))
	h.global_position = mid_c + Vector2(-10, 3)
	mob.position = mid_c + Vector2(10, -MobCatalog.HURTBOX_Y)
	for i in 6:
		await physics_frame
	var hp0: int = mob.hp
	h.attack_animation("Right", 0.0)
	await wait_until(func() -> bool: return not h.isAttacking, SWING_TIMEOUT_S)
	for i in 3:
		await physics_frame
	var blocked := mob.hp == hp0
	print("combat_hud: wall LOS blocked=%s (hp %s -> %s)" % [blocked, hp0, mob.hp])
	await snapshot("wall-blocks")

	map.erase_cell(1, mid)
	for i in 2:
		await physics_frame
	# V-open: posts on the north/south edges, gap east-west — same Right swing
	# geometry as the closed wall shot above.
	map.set_cell(1, mid, TileCatalog.SOURCE_ID, TileCatalog.PALISADE_GATE_V_OPEN)
	h.global_position = mid_c + Vector2(-10, 3)
	mob.position = mid_c + Vector2(10, -MobCatalog.HURTBOX_Y)
	mob.hp = 99
	while mob.state == Mob.State.HURT:
		await physics_frame
	for i in 6:
		await physics_frame
	hp0 = mob.hp
	h.attack_animation("Right", 0.0)
	await wait_until(func() -> bool: return not h.isAttacking, SWING_TIMEOUT_S)
	for i in 3:
		await physics_frame
	var through := mob.hp < hp0
	print("combat_hud: open-gate LOS hit=%s (hp %s -> %s)" % [through, hp0, mob.hp])
	await snapshot("open-gate-hits")
	mob.queue_free()
	return blocked and through


## A finger lands on the attack button's centre, drags `offset` (viewport px)
## away, `while_held` runs, and the finger lifts there.
func touch_drag(offset: Vector2, while_held: Callable) -> void:
	var button = current_scene.get_node(ATTACK_BUTTON)
	var center: Vector2 = button.aim_center()
	var to_win := root.get_final_transform()
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = to_win * center
	var drag := InputEventScreenDrag.new()
	drag.position = to_win * (center + offset)
	var lift := InputEventScreenTouch.new()
	lift.position = drag.position
	for e in [press, drag]:
		Input.parse_input_event(e)
		await process_frame
		await process_frame
	while_held.call()
	Input.parse_input_event(lift)
	await process_frame
	await process_frame
