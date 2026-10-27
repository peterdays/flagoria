class_name MobSfx
extends Node2D
## Sounds for one mob, played on every peer from what that peer already
## receives, so nothing extra is sent for them except the `attacks` counter.
##
## Hooks (see Mob):
##   notice - Mob.state enters CHASE, unless the mob was hurt since it last
##            calmed down (a hit mob goes HURT -> IDLE -> CHASE; that is not a
##            new notice). state is synced on change, so every peer sees it.
##   attack - Mob.attacks rises. The server counts each contact hit that
##            lands; the counter is synced on change with the mob's state.
##   hurt   - Mob.state enters HURT or DYING: a sword hit landed. See
##            sword_hit_landed, the one place a hit on a mob is handled here.
##   death  - Mob.state enters DYING (played with hurt on the last hit).
##   idle   - local and ambient: a rare quiet sound while the mob idles or
##            wanders, on a random timer of its own on each peer.
## Values set by the spawn packet (before the mob is ready) play nothing, so a
## late joiner does not hear old events. A hidden mob (on ground this peer has
## not generated yet) plays nothing. Sounds are positional: AudioStreamPlayer2D
## fades them out by MAX_DISTANCE from the listener.

const EVENTS := ["notice", "attack", "hurt", "death", "idle"]
const SOUNDS := {
	"slime": {
		"notice": [
			preload("res://art/audio/sfx/mobs/slime/slime_notice_01.wav"),
		],
		"attack": [
			preload("res://art/audio/sfx/mobs/slime/slime_attack_01.wav"),
			preload("res://art/audio/sfx/mobs/slime/slime_attack_02.wav"),
			preload("res://art/audio/sfx/mobs/slime/slime_attack_03.wav"),
		],
		"hurt": [
			preload("res://art/audio/sfx/mobs/slime/slime_hurt_01.wav"),
			preload("res://art/audio/sfx/mobs/slime/slime_hurt_02.wav"),
			preload("res://art/audio/sfx/mobs/slime/slime_hurt_03.wav"),
		],
		"death": [
			preload("res://art/audio/sfx/mobs/slime/slime_death_01.wav"),
		],
		"idle": [
			preload("res://art/audio/sfx/mobs/slime/slime_idle_01.wav"),
			preload("res://art/audio/sfx/mobs/slime/slime_idle_02.wav"),
		],
	},
	"crab": {
		"notice": [
			preload("res://art/audio/sfx/mobs/crab/crab_notice_01.wav"),
		],
		"attack": [
			preload("res://art/audio/sfx/mobs/crab/crab_attack_01.wav"),
			preload("res://art/audio/sfx/mobs/crab/crab_attack_02.wav"),
			preload("res://art/audio/sfx/mobs/crab/crab_attack_03.wav"),
		],
		"hurt": [
			preload("res://art/audio/sfx/mobs/crab/crab_hurt_01.wav"),
			preload("res://art/audio/sfx/mobs/crab/crab_hurt_02.wav"),
			preload("res://art/audio/sfx/mobs/crab/crab_hurt_03.wav"),
		],
		"death": [
			preload("res://art/audio/sfx/mobs/crab/crab_death_01.wav"),
		],
		"idle": [
			preload("res://art/audio/sfx/mobs/crab/crab_idle_01.wav"),
			preload("res://art/audio/sfx/mobs/crab/crab_idle_02.wav"),
		],
	},
	"piglet": {
		"notice": [
			preload("res://art/audio/sfx/mobs/piglet/piglet_notice_01.wav"),
		],
		"attack": [
			preload("res://art/audio/sfx/mobs/piglet/piglet_attack_01.wav"),
			preload("res://art/audio/sfx/mobs/piglet/piglet_attack_02.wav"),
			preload("res://art/audio/sfx/mobs/piglet/piglet_attack_03.wav"),
		],
		"hurt": [
			preload("res://art/audio/sfx/mobs/piglet/piglet_hurt_01.wav"),
			preload("res://art/audio/sfx/mobs/piglet/piglet_hurt_02.wav"),
			preload("res://art/audio/sfx/mobs/piglet/piglet_hurt_03.wav"),
		],
		"death": [
			preload("res://art/audio/sfx/mobs/piglet/piglet_death_01.wav"),
		],
		"idle": [
			preload("res://art/audio/sfx/mobs/piglet/piglet_idle_01.wav"),
			preload("res://art/audio/sfx/mobs/piglet/piglet_idle_02.wav"),
		],
	},
}
const VOLUME_DB := {"notice": -12.0, "attack": -11.0, "hurt": -10.0, "death": -9.0, "idle": -12.0}
## Added to VOLUME_DB per mob type: the crab clips are 1-3.6 dB quieter.
const MOB_VOLUME_DB := {"slime": 0.0, "crab": 2.0, "piglet": 0.0}
## Minimum seconds between two plays of the same event on one mob.
const COOLDOWN := {"notice": 1.0, "attack": 0.3, "hurt": 0.1, "death": 0.5, "idle": 1.0}
## Seconds between idle sounds, picked at random per mob within this range.
const IDLE_INTERVAL := Vector2(12.0, 30.0)
## px from the listener where a mob's sounds fade out (the view is about
## 690 x 390 px at the default zoom, so this is just past its edge).
const MAX_DISTANCE := 320.0
const ATTENUATION := 1.5
const PITCH_MIN := 0.93
const PITCH_MAX := 1.07

## Plays started per event (tests read this; playback is not observable headless).
var plays := {"notice": 0, "attack": 0, "hurt": 0, "death": 0, "idle": 0}
## Off stops the idle timer (tools that need a fixed set of sounds).
var idle_enabled := true
var mob_type := "slime"
var idle_left := 0.0
var _players := {}
var _last_ms := {}
var _skip_notice := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var mob := get_parent() as Mob
	if mob:
		mob_type = mob.mob_type
	_rng.randomize()
	idle_left = next_idle_delay()
	for event in EVENTS:
		var p := AudioStreamPlayer2D.new()
		p.name = event
		p.volume_db = VOLUME_DB[event] + float(MOB_VOLUME_DB.get(mob_type, 0.0))
		p.max_distance = MAX_DISTANCE
		p.attenuation = ATTENUATION
		p.max_polyphony = 1
		p.bus = &"SFX"
		add_child(p)
		_players[event] = p


func _process(delta: float) -> void:
	var mob := get_parent() as Mob
	if not idle_enabled or mob == null or not (mob.state == Mob.State.IDLE or mob.state == Mob.State.WALK):
		return
	idle_left -= delta
	if idle_left <= 0.0:
		idle_left = next_idle_delay()
		play_event("idle")


func next_idle_delay() -> float:
	return _rng.randf_range(IDLE_INTERVAL.x, IDLE_INTERVAL.y)


func on_state_changed(from: int, to: int) -> void:
	## Mob.state changed on this peer (server: behaviour; others: sync).
	match to:
		Mob.State.CHASE:
			if not _skip_notice:
				play_event("notice")
		Mob.State.HURT:
			sword_hit_landed(false)
		Mob.State.DYING:
			sword_hit_landed(true)
		Mob.State.WALK:
			_skip_notice = false
		Mob.State.IDLE:
			if from == Mob.State.CHASE:  # gave up: the next chase is a new notice
				_skip_notice = false


func sword_hit_landed(killed: bool) -> void:
	## A sword hit landed on this mob (once per hit on every peer). The mob's
	## voice plays here; a sword impact sound would go here too.
	_skip_notice = true
	play_event("hurt")
	if killed:
		play_event("death")


func play_event(event: String) -> bool:
	## Play `event` unless the mob is hidden or it played less than COOLDOWN
	## ago. Returns true if it played.
	if not SOUNDS.has(mob_type) or not SOUNDS[mob_type].has(event) or not is_visible_in_tree():
		return false
	var now := Time.get_ticks_msec()
	if _last_ms.has(event) and now - int(_last_ms[event]) < int(COOLDOWN[event] * 1000.0):
		return false
	_last_ms[event] = now
	var options: Array = SOUNDS[mob_type][event]
	var p: AudioStreamPlayer2D = _players[event]
	p.stream = options[randi() % options.size()]
	p.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	p.play()
	plays[event] += 1
	return true
