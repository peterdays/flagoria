extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## launch: --seed 49
## Walk, then latch the Run button and walk the same way again. The second
## stretch is farther. Snapshots: before-run (button up), after-run (latched).
## Start with bin/launch.sh drives/run_control.gd --seed 49.

const RUN_BUTTON := "CanvasLayer1/RunButton"
## Short enough to stay on the open ground next to the spawn, long enough
## that twice the walk acceleration is a longer stretch.
const MEASURE_FRAMES := 12
const TRY_ORDER := ["ui_left", "ui_right", "ui_up", "ui_down"]


func run() -> void:
	if not await start_game():
		return
	_phone_portrait()
	await snapshot("before-run")
	var button: Node = current_scene.get_node(RUN_BUTTON)
	for action in TRY_ORDER:
		step("walk")
		var walked := await _burst(action, MEASURE_FRAMES)
		step("run")
		await click(RUN_BUTTON)
		if not button.running():
			printerr("run control: tap did not latch")
			done(false)
			return
		var ran := await _burst(action, MEASURE_FRAMES)
		print("run control: %s walked %.1f px, ran %.1f px" % [action, walked, ran])
		if walked > 1.5 and ran > walked * 1.4:
			await snapshot("after-run")
			await click(RUN_BUTTON)
			done(not button.running())
			return
		await click(RUN_BUTTON)
		if button.running():
			printerr("run control: tap did not turn run off")
			done(false)
			return
	printerr("run control: no direction was faster while running")
	done(false)


func _phone_portrait() -> void:
	var win := current_scene.get_window()
	win.size = Vector2i(360, 640)
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	await process_frame


func _burst(action: String, frames: int) -> float:
	var start := hero().position
	await hold(action, frames)
	return hero().position.distance_to(start)
