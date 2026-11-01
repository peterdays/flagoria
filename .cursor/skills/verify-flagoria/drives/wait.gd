extends SceneTree
## The smallest drive: starts a game through the main menu, prints the ready
## line, then waits for bin/cleanup.sh to stop it. Start it with
## `bin/launch.sh drives/wait.gd`.

const MAIN := "res://flagoria_main.tscn"
const HOST_BUTTON := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/HostButton"
# Quits on its own after this long, in case cleanup is never run.
const MAX_WAIT_S := 600.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if change_scene_to_file(MAIN) != OK:
		printerr("drive wait: cannot load ", MAIN)
		quit(1)
		return
	if not await _frames_until(func() -> bool:
			return current_scene != null and current_scene.has_node(HOST_BUTTON)):
		printerr("drive wait: no ", HOST_BUTTON)
		quit(1)
		return
	current_scene.get_node(HOST_BUTTON).pressed.emit()
	var hero := "World/%d" % get_multiplayer().get_unique_id()
	if not await _frames_until(func() -> bool: return current_scene.has_node(hero)):
		printerr("drive wait: no local hero at ", hero)
		quit(1)
		return
	print("VERIFY_READY pid=%d scene=%s" % [OS.get_process_id(), MAIN])
	await create_timer(MAX_WAIT_S).timeout
	quit(0)


func _frames_until(done: Callable, frames := 600) -> bool:
	for i in range(frames):
		if done.call():
			return true
		await process_frame
	return false
