extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## Shared pieces for the dedicated cut-and-hit pair. The server is not a
## listen host: nothing here clicks Host. The three drives live under
## drives/dedicated_play/ so verify-drive does not start one of them alone.

const JOIN_BUTTON := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinButton"
const PORT := 9786
const JOIN_TIMEOUT_S := 45.0


func players() -> Array:
	var names: Array[String] = []
	if current_scene == null:
		return names
	for child in current_scene.get_node("World").get_children():
		if str(child.name).is_valid_int():
			names.append(str(child.name))
	names.sort()
	return names


func other_players() -> int:
	var mine := str(get_multiplayer().get_unique_id())
	var n := 0
	for id in players():
		if id != mine and id != "1":
			n += 1
	return n


func join_dedicated(who: String) -> bool:
	if change_scene_to_file(MAIN) != OK:
		return _fail("cannot load " + MAIN)
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(JOIN_BUTTON), START_TIMEOUT_S):
		return _fail("no " + JOIN_BUTTON)
	print("VERIFY_READY pid=%d scene=%s" % [OS.get_process_id(), MAIN])
	step("join")
	await click(JOIN_BUTTON)
	if not await wait_until(func() -> bool:
			return hero() != null and current_scene.world_params != null and other_players() >= 1, JOIN_TIMEOUT_S):
		return _fail("%s did not see the other client" % who)
	if players().has("1"):
		return _fail("%s sees a local server player 1" % who)
	print("dedicated_play: %s players=%s" % [who, ",".join(players())])
	return true


func nearest_plant() -> Vector2i:
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var origin: Vector2i = map.local_to_map(map.to_local(hero().global_position))
	for r in range(1, 15):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := origin + Vector2i(dx, dy)
				var type = InteractableCatalog.type_at(map.predict_cell(cell)[1])
				if type != null and (type.id == "tree" or type.id == "bush"):
					return cell
	return Vector2i(999999, 999999)


func plant_drawn(cell: Vector2i) -> bool:
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	return map.get_cell_atlas_coords(1, cell) != Vector2i(-1, -1)


func wood() -> int:
	return current_scene.get_node("Inventory").count_of(Inventory.WOOD)


func mobs_by_distance() -> Array:
	var ranked: Array = current_scene.get_node("World/Mobs").mobs()
	var me := hero()
	ranked.sort_custom(func(a: Mob, b: Mob) -> bool:
		return me.global_position.distance_to(a.global_position) < me.global_position.distance_to(b.global_position))
	return ranked
