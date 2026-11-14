extends SceneTree
## One-shot capture of debug/building_block_pieces.tscn for docs/screenshots.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err := change_scene_to_file("res://debug/building_block_pieces.tscn")
	if err != OK:
		push_error("scene load failed: %s" % err)
		quit(1)
		return
	for _i in 12:
		await process_frame
	var vp := root.get_viewport()
	vp.size = Vector2i(420, 220)
	for _i in 4:
		await process_frame
	var tex := vp.get_texture()
	if tex == null:
		push_error("viewport texture missing")
		quit(1)
		return
	var img := tex.get_image()
	if img == null or img.save_png("res://docs/screenshots/building_block_pieces.png") != OK:
		push_error("save failed")
		quit(1)
		return
	print("Wrote docs/screenshots/building_block_pieces.png")
	quit(0)