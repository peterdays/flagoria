extends SceneTree
## In-game audio check: drives the real player scene through a timeline
## (idle, walking on each surface, swing, damage, kill), records what the
## mixer actually outputs, and fails if a sound is not heard.
##
## Recording: an AudioEffectCapture on Master records the full mix after
## every bus volume, mute and effect (Master's own volume and mute are
## applied to the recording, since Godot applies them after bus effects). Each sound player in the scene also
## gets a probe bus (routed to the bus it already used) with its own
## capture, so a sound that is silent on its own (volume -80, empty stream)
## is caught even when another sound plays at the same time.
## Headless Godot uses the Dummy audio driver, which still mixes in real
## time, so this runs on CI without a sound card or display.
##
## Checks, per timeline step (see TIMELINE and docs/audio.md):
## - the event log (rising edge of `playing` on each sound player) has
##   exactly the expected sounds;
## - each logged sound is heard on its probe bus right after it starts;
## - the step's Master window is audible (RMS within RMS_RANGE_DB) when
##   sounds are expected, and silent (peak under SILENCE_DB) in the idle
##   tail after it;
## - nothing clips (Master peak under 0 dBFS).
##
## Usage:
##   godot --headless --audio-driver Dummy --path . --script res://tools/audio_check.gd \
##     [-- --out=res://artifacts/out/audio_check]
## Writes <out>.wav (Master mix), <out>_events.json and <out>.png
## (waveform with step windows and logged sounds). Exit 1 on any failure.

## Timeline. `expect` maps a sound name (file name without _NN.wav) to the
## exact number of times it must start in the step. Optional `sfx_volume`
## sets the SFX slider (0..1) for the step, `music_volume` the Music slider;
## `music` names a MusicPlayer track constant to play (without fade) for the
## step, stopped when the step ends; `audible: false` makes the step
## window a silence check (the sound starts but its bus is off). Every step is followed
## by IDLE_GAP seconds of idle whose last part must be silent.
const TIMELINE := [
	{"name": "idle", "action": "idle", "duration": 1.0, "expect": {}},
	{"name": "walk_grass", "action": "walk", "tile": "GRASS_A", "duration": 1.3, "expect": {"footstep_grass": 3}},
	{"name": "walk_sand", "action": "walk", "tile": "SAND", "duration": 1.3, "expect": {"footstep_sand": 3}},
	{"name": "walk_swamp", "action": "walk", "tile": "SWAMP", "duration": 1.3, "expect": {"footstep_swamp": 3}},
	{"name": "swing", "action": "swing", "duration": 0.6, "expect": {"sword_swing": 1}},
	{"name": "damage", "action": "damage", "duration": 0.6, "expect": {"hit_land": 1, "player_hurt": 1}},
	{"name": "kill", "action": "kill", "duration": 0.8, "expect": {"hit_land": 1, "player_hurt": 1, "hit_sting": 1}},
	# SFX slider at 0: the swing still starts, but nothing reaches Master.
	{"name": "swing_sfx_off", "action": "swing", "sfx_volume": 0.0, "audible": false, "duration": 0.6, "expect": {"sword_swing": 1}},
	{"name": "music", "action": "idle", "music": "GAME_TRACK", "duration": 2.0, "expect": {"4 - Village": 1}},
	# Music slider at 0: the track starts, but nothing reaches Master.
	{"name": "music_slider_off", "action": "idle", "music": "GAME_TRACK", "music_volume": 0.0, "audible": false, "duration": 1.0, "expect": {"4 - Village": 1}},
	# Music and SFX together must not clip.
	{"name": "music_with_swing", "action": "swing", "music": "GAME_TRACK", "duration": 1.0, "expect": {"4 - Village": 1, "sword_swing": 1}},
]
const IDLE_GAP := 0.9
## Only the tail of each idle gap must be silent (clips are under 0.5 s).
const SILENT_TAIL := 0.35
const SILENCE_DB := -60.0
const RMS_RANGE_DB := Vector2(-50.0, -6.0)
## A logged sound must reach this RMS on its probe bus within ONSET_WINDOW s.
const ONSET_DB := -50.0
const ONSET_WINDOW := 0.25
## Log times are only as fine as one mix chunk (about 0.1 s).
const ONSET_SLACK := 0.15
const WALK_SPEED := 130.0
const STRIP_ROW := 1000
const STRIP_LEN := 40

var _out := "res://artifacts/out/audio_check"
var _scene: Node
var _world: TileMap
var _walker: Node2D
var _attacker: Node2D
var _rate := 44100.0
var _master_cap: AudioEffectCapture
var _master := PackedVector2Array()
var _probes := {}  # node path -> {"cap": AudioEffectCapture, "data": PackedFloat32Array, "node": Node}
var _was_playing := {}
var _last_pos := {}
var _events: Array = []
var _windows: Array = []  # {"name", "start", "end", "kind"}
var _step := -1
var _step_start := 0.0
var _in_gap := false
var _strip_origin := {}
var _failures: Array[String] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	call_deferred("_setup")


func _setup() -> void:
	_rate = AudioServer.get_mix_rate()
	_scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(_scene)
	_world = _scene.get_node("World/worldMap")
	_world.set_process(false)  # no chunk regeneration over the painted strips
	# Default volumes, whatever this machine has saved; nothing is written.
	root.get_node("AudioSettings").reset_to_defaults()
	# The main menu starts its music; music steps play it when they need it.
	var music = root.get_node("MusicPlayer")
	music.stop(0.0)
	_paint_strips()
	_walker = _spawn_player("2", Vector2.ZERO)
	_attacker = _spawn_player("3", Vector2(12, 0))
	_walker.get_node("Camera2D").make_current()

	_master_cap = AudioEffectCapture.new()
	_master_cap.buffer_length = 1.0
	AudioServer.add_bus_effect(0, _master_cap)
	for player in [_walker, _attacker]:
		for node in _sound_players(player):
			_add_probe(node)
	for node in music.players():
		_add_probe(node)
	process_frame.connect(_tick)
	physics_frame.connect(_physics_tick)


func _physics_tick() -> void:
	## Walk at player top speed per physics tick, like real movement. The
	## sample clock below advances in mix-sized chunks and is too coarse.
	if _step >= 0 and not _in_gap and TIMELINE[_step]["action"] == "walk":
		_walker.global_position.x += WALK_SPEED / Engine.physics_ticks_per_second


func _spawn_player(peer_name: String, pos: Vector2) -> Node2D:
	var p: Node2D = load("res://Player/character_body_2d.tscn").instantiate()
	p.name = peer_name
	p.position = pos
	_scene.get_node("World").add_child(p)
	return p


func _paint_strips() -> void:
	## One horizontal strip per walk step, painted with that step's tile, so
	## footsteps use the real tile lookup.
	var row := STRIP_ROW
	for step in TIMELINE:
		if step["action"] != "walk":
			continue
		var tile: Dictionary = TileCatalog.TILES[step["tile"]]
		for x in range(STRIP_LEN):
			for dy in range(-1, 2):
				_world.set_cell(0, Vector2i(x, row + dy), tile["source_id"], tile["atlas"])
				for layer in range(1, _world.get_layers_count()):
					_world.erase_cell(layer, Vector2i(x, row + dy))
		_strip_origin[step["name"]] = _world.to_global(_world.map_to_local(Vector2i(0, row)))
		row += 6


func _sound_players(node: Node) -> Array:
	var found := []
	if node is AudioStreamPlayer2D or node is AudioStreamPlayer:
		found.append(node)
	for child in node.get_children():
		found.append_array(_sound_players(child))
	return found


func _add_probe(node: Node) -> void:
	## Probe bus between the sound player and the bus it already used.
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	var bus_name := "Probe_%d" % idx
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, node.bus)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 1.0
	AudioServer.add_bus_effect(idx, cap)
	node.bus = bus_name
	_probes[str(node.get_path())] = {"cap": cap, "data": PackedFloat32Array(), "node": node}


func _now() -> float:
	return _master.size() / _rate


func _tick() -> void:
	_drain()
	_log_starts()
	var t := _now()
	if _step == -1:
		_begin_step(0, t)
	var step: Dictionary = TIMELINE[_step]
	if not _in_gap:
		if t - _step_start >= step["duration"]:
			if step.has("music"):
				root.get_node("MusicPlayer").stop(0.0)
			var audible: bool = step.get("audible", true) and not step["expect"].is_empty()
			_windows.append({"name": step["name"], "start": _step_start, "end": t, "kind": "event" if audible else "silent"})
			_in_gap = true
			_step_start = t
	elif t - _step_start >= IDLE_GAP:
		_windows.append({"name": step["name"] + "_after", "start": t - SILENT_TAIL, "end": t, "kind": "silent"})
		if _step + 1 >= TIMELINE.size():
			process_frame.disconnect(_tick)
			physics_frame.disconnect(_physics_tick)
			_finish()
			return
		_begin_step(_step + 1, t)


func _begin_step(i: int, t: float) -> void:
	_step = i
	_step_start = t
	_in_gap = false
	var step: Dictionary = TIMELINE[i]
	var audio = root.get_node("AudioSettings")
	for bus in ["SFX", "Music"]:
		var v: float = step.get(bus.to_lower() + "_volume", audio.DEFAULTS[bus])
		if not is_equal_approx(audio.get_volume(bus), v):
			audio.set_volume(bus, v, false)
	if step.has("music"):
		var music = root.get_node("MusicPlayer")
		music.play(music.get(step["music"]), 0.0)
	# Attacker in earshot of the walker but out of sword reach, so a swing
	# alone does not land a hit; damage steps call the hit path directly.
	_attacker.global_position = _walker.global_position + Vector2(48, 0)
	match step["action"]:
		"walk":
			_walker.global_position = _strip_origin[step["name"]]
		"swing":
			_attacker.attack_animation()
		"damage":
			_walker.currentHealth = _walker.maxHealth
			_walker._on_hurt_box_area_entered(_attacker.get_node("weapon/sword"))
		"kill":
			_walker.currentHealth = 1
			_walker._on_hurt_box_area_entered(_attacker.get_node("weapon/sword"))
	# Log starts in the same frame: Godot can stop a player at once when its
	# bus is muted, before the next poll would see it playing.
	_log_starts()


func _drain() -> void:
	var n := _master_cap.get_frames_available()
	if n > 0:
		# Godot applies a bus's own volume and mute after its effects, so the
		# capture misses Master's; apply them here to get what reaches the
		# speakers. Other buses' volume and mute are already in the capture.
		var gain := 0.0 if AudioServer.is_bus_mute(0) else db_to_linear(AudioServer.get_bus_volume_db(0))
		var buf := _master_cap.get_buffer(n)
		if gain != 1.0:
			for i in buf.size():
				buf[i] *= gain
		_master.append_array(buf)
	for key in _probes:
		var probe: Dictionary = _probes[key]
		var cap: AudioEffectCapture = probe["cap"]
		var m := cap.get_frames_available()
		if m > 0:
			var data: PackedFloat32Array = probe["data"]
			for v in cap.get_buffer(m):
				data.append((v.x + v.y) * 0.5)
			probe["data"] = data


func _log_starts() -> void:
	## A sound player that starts (or restarts) playing is one logged sound.
	for key in _probes:
		var node = _probes[key]["node"]
		var playing: bool = node.playing
		var pos: float = node.get_playback_position() if playing else 0.0
		var restarted: bool = playing and _was_playing.get(key, false) and pos < _last_pos.get(key, 0.0)
		if playing and (not _was_playing.get(key, false) or restarted):
			var file: String = node.stream.resource_path.get_file() if node.stream else "<no stream>"
			_events.append({
				"t": snappedf(_now(), 0.001),
				"sound": _sound_name(file),
				"file": file,
				"player": _owner_name(node),
				"probe": key,
			})
		_was_playing[key] = playing
		_last_pos[key] = pos


static func _owner_name(node: Node) -> String:
	## Player node name for sounds on a player, "local" for music and UI.
	var n := node.get_parent()
	while n != null:
		if n is CharacterBody2D:
			return str(n.name)
		n = n.get_parent()
	return "local"


static func _sound_name(file: String) -> String:
	var base := file.get_basename()
	var parts := base.split("_")
	if parts.size() > 1 and parts[-1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	return "_".join(parts)


static func _db(v: float) -> float:
	return -200.0 if v <= 0.0 else 20.0 * log(v) / log(10.0)


func _master_stats(start: float, end: float) -> Vector2:
	## (peak, rms) of the Master mix over [start, end] seconds.
	var a := clampi(int(start * _rate), 0, _master.size())
	var b := clampi(int(end * _rate), 0, _master.size())
	var peak := 0.0
	var sum := 0.0
	for i in range(a, b):
		var v: Vector2 = _master[i]
		peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
		sum += (v.x * v.x + v.y * v.y) * 0.5
	return Vector2(peak, sqrt(sum / maxi(1, b - a)))


func _probe_rms(key: String, start: float, end: float) -> float:
	var data: PackedFloat32Array = _probes[key]["data"]
	var a := clampi(int(start * _rate), 0, data.size())
	var b := clampi(int(end * _rate), 0, data.size())
	var sum := 0.0
	for i in range(a, b):
		sum += data[i] * data[i]
	return sqrt(sum / maxi(1, b - a))


func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("FAIL audio_check: " + msg)


func _finish() -> void:
	var report := []
	# Clipping over the whole recording.
	var whole := _master_stats(0.0, _now())
	if whole.x >= 1.0:
		_fail("Master clips (peak %.2f dBFS)" % _db(whole.x))
	for w in _windows:
		var s := _master_stats(w["start"], w["end"])
		var line := "%-18s %6.2f-%6.2f s  peak %7.1f dBFS  rms %7.1f dBFS" % [w["name"], w["start"], w["end"], _db(s.x), _db(s.y)]
		if w["kind"] == "silent":
			if _db(s.x) > SILENCE_DB:
				_fail("%s should be silent, peak %.1f dBFS" % [w["name"], _db(s.x)])
		else:
			var rms := _db(s.y)
			if rms < RMS_RANGE_DB.x or rms > RMS_RANGE_DB.y:
				_fail("%s rms %.1f dBFS outside %s" % [w["name"], rms, RMS_RANGE_DB])
		print(line)
		report.append(line)

	for i in TIMELINE.size():
		var step: Dictionary = TIMELINE[i]
		var w: Dictionary = _windows[i * 2]
		var counts := {}
		for e in _events:
			# Log times are rounded to 1 ms, so allow that much before the window.
			if e["t"] >= w["start"] - 0.001 and e["t"] < w["end"] + IDLE_GAP - SILENT_TAIL:
				counts[e["sound"]] = counts.get(e["sound"], 0) + 1
		for sound in step["expect"]:
			if counts.get(sound, 0) != step["expect"][sound]:
				_fail("%s: %s started %d times, want %d" % [step["name"], sound, counts.get(sound, 0), step["expect"][sound]])
		for sound in counts:
			if not step["expect"].has(sound):
				_fail("%s: unexpected %s x%d" % [step["name"], sound, counts[sound]])

	for e in _events:
		var rms := _db(_probe_rms(e["probe"], e["t"] - ONSET_SLACK, e["t"] + ONSET_WINDOW))
		e["onset_rms_db"] = snappedf(rms, 0.1)
		if rms < ONSET_DB:
			_fail("%s (%s, player %s) at %.2f s not heard: %.1f dBFS on its own bus" % [e["sound"], e["file"], e["player"], e["t"], rms])
		print("event %6.2f s  %-14s %-22s player %s  onset rms %6.1f dBFS" % [e["t"], e["sound"], e["file"], e["player"], rms])

	_write_outputs()
	if _failures.is_empty():
		print("AUDIO_CHECK_OK (%d sounds over %.1f s)" % [_events.size(), _now()])
		quit(0)
	else:
		printerr("audio_check: %d failure(s)" % _failures.size())
		quit(1)


func _write_outputs() -> void:
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	# WAV of the Master mix, 16-bit stereo.
	var bytes := PackedByteArray()
	bytes.resize(_master.size() * 4)
	for i in _master.size():
		var v: Vector2 = _master[i]
		bytes.encode_s16(i * 4, int(clampf(v.x, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(v.y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(_rate)
	wav.data = bytes
	wav.save_to_wav(_out + ".wav")
	var f := FileAccess.open(_out + "_events.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"events": _events, "windows": _windows, "failures": _failures}, "  "))
	f.close()
	_write_plot()
	print("saved ", ProjectSettings.globalize_path(_out + ".wav"))
	print("saved ", ProjectSettings.globalize_path(_out + "_events.json"))
	print("saved ", ProjectSettings.globalize_path(_out + ".png"))


func _write_plot() -> void:
	## Waveform (peak per column) with event windows green, silent windows
	## grey and logged sound starts as red ticks.
	var w := 1600
	var h := 240
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("101418"))
	var total := maxf(_now(), 0.001)
	for win in _windows:
		var x0 := int(win["start"] / total * w)
		var x1 := maxi(x0 + 1, int(win["end"] / total * w))
		img.fill_rect(Rect2i(x0, 0, x1 - x0, h), Color("1d4d2b") if win["kind"] == "event" else Color("2a2d33"))
	var per := maxi(1, _master.size() / w)
	for x in range(w):
		var peak := 0.0
		for i in range(x * per, mini((x + 1) * per, _master.size())):
			peak = maxf(peak, absf(_master[i].x))
		var half := int(peak * (h / 2 - 4))
		img.fill_rect(Rect2i(x, h / 2 - half, 1, half * 2 + 1), Color("8fd3ff"))
	for e in _events:
		var x := int(e["t"] / total * w)
		img.fill_rect(Rect2i(x, 0, 2, 14), Color("ff4d4d"))
	img.save_png(_out + ".png")
