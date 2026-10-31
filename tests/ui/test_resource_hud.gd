extends "res://tests/helpers/test_helpers.gd"
## Resource HUD in the main scene.


func _test_resource_hud_in_scene() -> int:
	## In the real main scene, the local player's spawn shows the wood counter
	## centred at the top at the hearts' scale, starting at 0, and wood added
	## to the inventory updates it.
	print("-- test_resource_hud_in_scene")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.add_player(scene.multiplayer.get_unique_id())
	await process_frame
	var hud: ResourceHud = scene.get_node("CanvasLayer1/ResourceHud")
	var hearts: Control = scene.get_node("CanvasLayer1/HeartsHud")
	var menu_rect: Rect2 = scene.get_node("CanvasLayer1/InGameMenu").menu_button.get_global_rect()
	hud.follow_hearts()
	var hud_rect := hud.get_global_rect()
	var mid: float = scene.get_viewport().get_visible_rect().get_center().x
	if not hud.visible or hud.label.text != "0" or hud.scale != hearts.scale \
			or absf(hud_rect.get_center().x - mid) > 1.0 or hud_rect.intersects(menu_rect):
		printerr("FAIL resource_hud_in_scene: counter visible %s text '%s' at %s x%s"
				% [hud.visible, hud.label.text, hud_rect, hud.scale])
		fail += 1
	var inventory: Inventory = scene.get_node("Inventory")
	if inventory.add(Inventory.WOOD, 3) != 3 or inventory.count_of(Inventory.WOOD) != 3 or hud.label.text != "3":
		printerr("FAIL resource_hud_in_scene: counter '%s' after 3 wood" % hud.label.text)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_resource_hud_in_scene")
	return fail
