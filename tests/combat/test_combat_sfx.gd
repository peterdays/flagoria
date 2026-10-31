extends "res://tests/helpers/test_helpers.gd"
## Player combat and health sounds (Scripts/combat_sfx.gd).


func _test_combat_sfx() -> int:
	## Each combat event plays once per call on this peer; a repeat inside the
	## cooldown is dropped; player hooks fire swing, hit+hurt, and sting on 0 HP.
	print("-- test_combat_sfx")
	var fail := 0
	var sfx := CombatSfx.new()
	root.add_child(sfx)
	for event in ["swing", "hit", "hurt", "sting"]:
		if not sfx.play_event(event) or sfx.plays[event] != 1:
			printerr("FAIL combat_sfx: %s did not play once" % event)
			fail += 1
		if sfx.play_event(event) or sfx.plays[event] != 1:
			printerr("FAIL combat_sfx: %s played again inside cooldown" % event)
			fail += 1
	if sfx.play_event("unknown"):
		printerr("FAIL combat_sfx: unknown event played")
		fail += 1
	sfx.queue_free()

	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = "2"
	scene.get_node("World").add_child(player)
	var c: CombatSfx = player.combat_sfx
	player.attack_animation()
	player.health.take_damage(1)
	if c.plays["swing"] != 1 or c.plays["hit"] != 1 or c.plays["hurt"] != 1 or c.plays["sting"] != 0:
		printerr("FAIL combat_sfx: attack + damage plays %s" % c.plays)
		fail += 1
	# A hit from another player's sword: hit and hurt once each; at half a heart it is a kill.
	c._last_ms.clear()
	player.health.set_health_now(1)
	var other = load("res://Player/character_body_2d.tscn").instantiate()
	other.name = "3"
	scene.get_node("World").add_child(other)
	other.attack_animation()  # only a swinging sword hits
	player._on_hurt_box_area_entered(other.get_node("weapon/sword"))
	if c.plays["hit"] != 2 or c.plays["hurt"] != 2 or c.plays["sting"] != 1:
		printerr("FAIL combat_sfx: kill hit plays %s" % c.plays)
		fail += 1
	# Damage at 0 HP loses nothing: no hurt and no second sting.
	c._last_ms.clear()
	player.health.take_damage(1)
	if player.health.health != 0 or c.plays["hurt"] != 2 or c.plays["sting"] != 1:
		printerr("FAIL combat_sfx: damage at 0 HP plays %s" % c.plays)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_combat_sfx")
	return fail
