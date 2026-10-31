extends "res://tests/helpers/test_helpers.gd"
## Background music.


func _test_music_player() -> int:
	## Music loops on the Music bus, asking for the playing track does not
	## restart it, a new track replaces the old one (crossfade), and reloading
	## the main menu does not start a second copy.
	print("-- test_music_player")
	var fail := 0
	var music = root.get_node("MusicPlayer")
	music.stop(0.0)
	for p in music.players():
		if p.bus != &"Music":
			printerr("FAIL music: %s plays on %s, not Music" % [p.name, p.bus])
			fail += 1
	var starts: int = music.starts
	music.play(music.MENU_TRACK, 0.0)
	if music.current_track() != music.MENU_TRACK or music.starts != starts + 1:
		printerr("FAIL music: menu track not playing (%s)" % music.current_track())
		fail += 1
	var first: AudioStreamPlayer = null
	for p in music.players():
		if p.playing:
			first = p
	if first == null or not first.stream.loop:
		printerr("FAIL music: menu track is not set to loop")
		fail += 1
	await create_timer(0.2).timeout
	var pos := first.get_playback_position() if first else 0.0
	music.play(music.MENU_TRACK)
	if music.starts != starts + 1 or not first.playing or first.get_playback_position() < pos:
		printerr("FAIL music: same track restarted")
		fail += 1

	music.play(music.GAME_TRACK, 0.3)
	var playing := 0
	for p in music.players():
		playing += 1 if p.playing else 0
	if music.current_track() != music.GAME_TRACK or playing != 2:
		printerr("FAIL music: crossfade should play both tracks briefly, %d playing" % playing)
		fail += 1
	await create_timer(0.6).timeout
	playing = 0
	for p in music.players():
		playing += 1 if p.playing else 0
	if playing != 1 or first.playing:
		printerr("FAIL music: after the crossfade %d players play, old one playing=%s" % [playing, first.playing])
		fail += 1

	# The main menu asks for the menu track; a second menu does not double it.
	music.stop(0.0)
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var after_first: int = music.starts
	var again = load("res://flagoria_main.tscn").instantiate()
	again.name = "FlagoriaAgain"
	root.add_child(again)
	playing = 0
	for p in music.players():
		playing += 1 if p.playing else 0
	if music.current_track() != music.MENU_TRACK or music.starts != after_first or playing != 1:
		printerr("FAIL music: menu reload starts=%d->%d playing=%d" % [after_first, music.starts, playing])
		fail += 1
	again.queue_free()
	scene.queue_free()
	music.stop(0.0)
	await process_frame
	if fail == 0:
		print("PASS test_music_player")
	return fail
