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
	await _snapshot_run_zoom("run-off")
	var button: RunControl = current_scene.get_node(RUN_BUTTON) as RunControl
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
			await _snapshot_run_zoom("run-on")
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


func _snapshot_run_zoom(label: String) -> void:
	var dir := OS.get_environment("VERIFY_EVIDENCE_DIR")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var pad := 6
	var vp := current_scene.get_viewport()
	var img_size := root.get_texture().get_size()
	var vis := vp.get_visible_rect().size
	var scale := Vector2(img_size.x / vis.x, img_size.y / vis.y)
	var run := current_scene.get_node(RUN_BUTTON) as Control
	var region := _scaled_pixels(run.get_global_rect(), scale, pad)
	var attack := current_scene.get_node("CanvasLayer1/TouchScreenButton") as TouchScreenButton
	if attack != null and attack.texture_normal != null:
		var atk_rect := Rect2(attack.global_position, attack.texture_normal.get_size() * attack.scale)
		region = region.merge(_scaled_pixels(atk_rect, scale, pad))
	region = region.intersection(Rect2i(Vector2i.ZERO, img_size))
	if region.size.x < 1 or region.size.y < 1:
		printerr("drive: run zoom skipped empty %s (run %s img %s)"
				% [region, run.get_global_rect(), img_size])
		return
	var img := root.get_texture().get_image()
	var crop := img.get_region(region)
	var zoom := crop.duplicate()
	zoom.resize(region.size.x * 8, region.size.y * 8, Image.INTERPOLATE_NEAREST)
	var path := dir.path_join("%s.png" % label.validate_filename())
	if zoom.save_png(path) == OK:
		print("drive: run zoom %s (%s)" % [path.get_file(), region])


func _scaled_pixels(rect: Rect2, scale: Vector2, pad: int) -> Rect2i:
	var grown := rect.grow(pad)
	var pos := grown.position * scale
	var end := grown.end * scale
	return Rect2i(int(pos.x), int(pos.y), int(end.x - pos.x), int(end.y - pos.y))


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
