class_name CombatSfx
extends Node2D
## Combat sounds for one player instance.
##
## Every trigger already runs once on each peer: attack_animation is a
## call_local RPC, and hurt-box overlaps are detected locally on every peer
## from replicated positions. So each peer plays each event once from those
## paths, and nothing here is sent over the network.
##
## Events:
##   swing - this player starts an attack.
##   hit   - another player's sword lands on this player (played with hurt).
##   hurt  - this player loses health.
##   sting - accent when a hit takes this player's health to 0.

const SOUNDS := {
	"swing": [
		preload("res://art/audio/sfx/combat/sword_swing_01.wav"),
		preload("res://art/audio/sfx/combat/sword_swing_02.wav"),
		preload("res://art/audio/sfx/combat/sword_swing_03.wav"),
	],
	"hit": [
		preload("res://art/audio/sfx/combat/hit_land_01.wav"),
		preload("res://art/audio/sfx/combat/hit_land_02.wav"),
		preload("res://art/audio/sfx/combat/hit_land_03.wav"),
	],
	"hurt": [
		preload("res://art/audio/sfx/combat/player_hurt_01.wav"),
		preload("res://art/audio/sfx/combat/player_hurt_02.wav"),
	],
	"sting": [
		preload("res://art/audio/sfx/combat/hit_sting_01.wav"),
	],
}
const VOLUME_DB := {"swing": -10.0, "hit": -8.0, "hurt": -9.0, "sting": -8.0}
## Minimum seconds between two plays of the same event.
const COOLDOWN := {"swing": 0.15, "hit": 0.1, "hurt": 0.25, "sting": 0.5}
const PITCH_MIN := 0.93
const PITCH_MAX := 1.07

## Plays started per event (tests read this; playback is not observable headless).
var plays := {"swing": 0, "hit": 0, "hurt": 0, "sting": 0}
var _players := {}
var _last_ms := {}


func _ready() -> void:
	for event in SOUNDS:
		var p := AudioStreamPlayer2D.new()
		p.name = event
		p.volume_db = VOLUME_DB[event]
		p.max_polyphony = 1
		p.bus = &"SFX"
		add_child(p)
		_players[event] = p


func play_event(event: String) -> bool:
	## Play `event` unless it played less than COOLDOWN ago. Returns true if it played.
	if not SOUNDS.has(event):
		return false
	var now := Time.get_ticks_msec()
	if _last_ms.has(event) and now - int(_last_ms[event]) < int(COOLDOWN[event] * 1000.0):
		return false
	_last_ms[event] = now
	var options: Array = SOUNDS[event]
	var p: AudioStreamPlayer2D = _players[event]
	p.stream = options[randi() % options.size()]
	p.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	p.play()
	plays[event] += 1
	return true
