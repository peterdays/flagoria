extends "res://.cursor/skills/verify-flagoria/drives/dedicated_play/play_common.gd"
## Client B of the dedicated pair. Joins before A, then waits until the plant
## A chops is gone and until a mob A hits is dying. Start this after the
## server and before play_client_a.gd.

const OBSERVE_S := 70.0


func run() -> void:
	if not await join_dedicated("client-b"):
		return
	await snapshot("joined")
	step("see-cut")
	var map: TileMap = current_scene.get_node(WORLD_MAP)
	var removed := await wait_until(func() -> bool:
		var cuts: Dictionary = map.cut_changes()
		for chunk in cuts:
			for key in cuts[chunk]:
				var cell = WorldSave.parse_cell(key)
				if cell != null and map.get_cell_atlas_coords(1, cell) == Vector2i(-1, -1):
					return true
		return false, OBSERVE_S)
	print("dedicated_play: client-b removed=%s wood=%s" % [removed, wood()])
	await snapshot("after-cut")
	if not removed:
		_fail("did not see the plant removed")
		return
	step("see-hit")
	var seen := {}
	var saw_hurt := false
	var saw_dying := false
	var missing_after_hurt := false
	var end := Time.get_ticks_msec() + int(OBSERVE_S * 1000.0)
	while Time.get_ticks_msec() < end and not saw_dying and not missing_after_hurt:
		var now := {}
		for mob in current_scene.get_node("World/Mobs").mobs():
			now[str(mob.name)] = true
			saw_hurt = saw_hurt or mob.state == Mob.State.HURT
			saw_dying = saw_dying or mob.state == Mob.State.DYING
			seen[str(mob.name)] = mob.state
		for name in seen.keys():
			if not now.has(name) and (seen[name] == Mob.State.HURT or seen[name] == Mob.State.DYING):
				missing_after_hurt = true
		await process_frame
	var dead := saw_dying or missing_after_hurt
	print("dedicated_play: client-b hurt=%s dying=%s dead=%s" % [saw_hurt, saw_dying, dead])
	await snapshot("after-hit")
	done(removed and saw_hurt and dead)
