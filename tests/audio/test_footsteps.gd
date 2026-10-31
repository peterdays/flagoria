extends "res://tests/helpers/test_helpers.gd"
## Terrain footsteps.


func _test_footsteps() -> int:
	## Footsteps: none while idle or on a teleport; walking at top speed in
	## simulated 60 Hz frames plays exactly one step per STEP_DISTANCE on every
	## surface, and no step starts before the previous clip (real length / pitch)
	## has ended. Surfaces are chosen by TileCatalog name.
	print("-- test_footsteps")
	var fail := 0
	var speed: float = load("res://Scripts/player.gd").MAX_SPEED
	var longest := 0.0
	for surface in Footsteps.SOUNDS:
		for clip in Footsteps.SOUNDS[surface]:
			longest = maxf(longest, clip.get_length())
	var stride_s := Footsteps.STEP_DISTANCE / speed
	if stride_s < longest / Footsteps.PITCH_MIN:
		printerr("FAIL footsteps: stride %.3f s shorter than longest clip %.3f s" % [stride_s, longest / Footsteps.PITCH_MIN])
		fail += 1

	var steps := Footsteps.new()
	root.add_child(steps)
	for i in range(120):
		steps.advance(Vector2(10, 10))
	if steps.steps_played != 0:
		printerr("FAIL footsteps: %d steps while idle" % steps.steps_played)
		fail += 1
	steps.advance(Vector2(500, 10))
	if steps.steps_played != 0:
		printerr("FAIL footsteps: step on teleport")
		fail += 1

	var dt := 1.0 / 60.0
	var strides := 10
	var x := 500.0
	for surface in ["grass", "sand", "swamp"]:
		steps.surface_override = surface
		var before: int = steps.steps_played
		var t := 0.0
		var clip_end := -1.0
		var walked := 0.0
		# Walk just short of the 11th stride so float rounding cannot add one.
		while walked + speed * dt <= strides * Footsteps.STEP_DISTANCE + Footsteps.STEP_DISTANCE * 0.5:
			var count: int = steps.steps_played
			x += speed * dt
			walked += speed * dt
			t += dt
			steps.advance(Vector2(x, 10))
			if steps.steps_played != count:
				if t < clip_end:
					printerr("FAIL footsteps: %s step at %.3f s before clip end %.3f s" % [surface, t, clip_end])
					fail += 1
				clip_end = t + steps.stream.get_length() / steps.pitch_scale
				if steps.last_surface != surface:
					printerr("FAIL footsteps: played %s want %s" % [steps.last_surface, surface])
					fail += 1
		var got: int = steps.steps_played - before
		if got != strides:
			printerr("FAIL footsteps: %s %d steps over %d px, want %d" % [surface, got, int(walked), strides])
			fail += 1
		# Reset the stride counter between surfaces with a stop + teleport.
		x += 1000.0
		steps.advance(Vector2(x, 10))

	var after_walk: int = steps.steps_played
	for i in range(120):
		steps.advance(Vector2(x, 10))
	if steps.steps_played != after_walk:
		printerr("FAIL footsteps: steps continued after stopping")
		fail += 1
	if steps.volume_db > -8.0 or steps.volume_db < -12.0:
		printerr("FAIL footsteps: volume %s dB outside -12..-8" % steps.volume_db)
		fail += 1
	var cases := {
		TileCatalog.SAND: "sand", TileCatalog.SWAMP: "swamp", TileCatalog.SWAMP_SPECIAL: "swamp",
		TileCatalog.GRASS_C: "grass", TileCatalog.WATER: "grass", Vector2i(-1, -1): "grass",
	}
	for atlas in cases:
		var got := Footsteps.surface_for_atlas(atlas)
		if got != cases[atlas]:
			printerr("FAIL footsteps: surface for %s is %s want %s" % [atlas, got, cases[atlas]])
			fail += 1
	steps.queue_free()
	if fail == 0:
		print("PASS test_footsteps")
	return fail
