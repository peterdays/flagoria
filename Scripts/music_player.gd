extends Node
## Autoload: background music on the Music bus, local to this client.
##
## Two players crossfade: play() fades the new track in on the idle player
## and the old one out. Asking for the track that is already playing does
## nothing, so the music never restarts or doubles when menus or scenes
## change. Nothing here is networked; each client plays its own music.

const MENU_TRACK := "res://art/Sprites/NinjaAdventure/Musics/5 - Peaceful.ogg"
const GAME_TRACK := "res://art/Sprites/NinjaAdventure/Musics/4 - Village.ogg"
const VOLUME_DB := -8.0
const FADE := 1.5

## play() calls that started a track (tests read this).
var starts := 0
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tweens := {}


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = &"Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


func current_track() -> String:
	var p := _players[_active]
	return p.stream.resource_path if p.playing and p.stream else ""


func players() -> Array[AudioStreamPlayer]:
	return _players


func play(track: String, fade := FADE) -> void:
	## Crossfade to `track` (res:// path). No-op if it is already playing.
	if current_track() == track:
		return
	var stream: AudioStream = load(track)
	if stream == null:
		push_error("music: cannot load %s" % track)
		return
	if "loop" in stream:
		stream.loop = true
	var old := _players[_active]
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.play()
	starts += 1
	_fade(p, VOLUME_DB, fade, false)
	if old.playing:
		_fade(old, -80.0, fade, true)


func stop(fade := FADE) -> void:
	for p in _players:
		if p.playing:
			_fade(p, -80.0, fade, true)


func _fade(p: AudioStreamPlayer, to_db: float, seconds: float, stop_after: bool) -> void:
	if _tweens.has(p) and _tweens[p].is_valid():
		_tweens[p].kill()
	if seconds <= 0.0:
		p.volume_db = to_db
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, seconds)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[p] = tw
