extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## The hero at the castle gate stands in front of the wall, head included.
## Landscape only: 1280x720, then 854x480.

const MAP := "World/worldMap"


func run() -> void:
	step("in-front")
	if not await start_game():
		return
	for _i in 5:
		await process_frame
	if not _in_front():
		done(false)
		return
	await snapshot("in-front")
	step("constrained")
	if not await _resize(854, 480):
		done(false)
		return
	if not _in_front():
		done(false)
		return
	await snapshot("in-front-constrained")
	done(true)


func _in_front() -> bool:
	var body := hero()
	var map: TileMap = current_scene.get_node(MAP)
	var front: int = map.get_layer_z_index(4) + 1
	print("hero_wall: z %s want %s cover %.2f window %s" % [
			body.z_index, front, body._wall_cover(map), DisplayServer.window_get_size()])
	if body.z_index != front:
		printerr("hero_wall: the hero is not drawn over the wall (z %s, want %s)" % [body.z_index, front])
		return false
	return true


func _resize(width: int, height: int) -> bool:
	root.size = Vector2i(width, height)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(width, height))
	for _i in 10:
		await process_frame
	var got := DisplayServer.window_get_size()
	print("hero_wall: window %s (asked %dx%d)" % [got, width, height])
	return got.x == width and got.y == height
