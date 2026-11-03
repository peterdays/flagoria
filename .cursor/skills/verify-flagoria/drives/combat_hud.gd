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
	done(ok)


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
