extends Node
## Autoload: gameplay settings saved in user settings. For now, the mob spawn
## rate the host uses when it places a world's mobs (see MobSpawner.plan).
##
## Only the host spawns mobs, so only the host's rate matters in multiplayer;
## a client's saved rate is never read during a match.

const SECTION := "gameplay"
## Multiplier on MobSpawner's base density and caps. 1.0 was the only rate
## before the setting existed.
const MOB_RATE_DEFAULT := 2.0
const MOB_RATE_MIN := 0.5
const MOB_RATE_MAX := 3.0
const MOB_RATE_STEP := 0.25

## Tests point this at a scratch file.
var save_path := "user://game_settings.cfg"
var mob_rate := MOB_RATE_DEFAULT


func _ready() -> void:
	load_from_disk()


func set_mob_rate(value: float, save := true) -> void:
	mob_rate = clampf(snappedf(value, MOB_RATE_STEP), MOB_RATE_MIN, MOB_RATE_MAX)
	if save:
		save_to_disk()


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "mob_rate", mob_rate)
	cfg.save(save_path)


func load_from_disk() -> void:
	## Saved values, or defaults for anything missing or not a finite number.
	mob_rate = MOB_RATE_DEFAULT
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	var v: Variant = cfg.get_value(SECTION, "mob_rate", MOB_RATE_DEFAULT)
	if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v)):
		set_mob_rate(float(v), false)


static func rate_label(value: float) -> String:
	## "2x", "1.5x", "0.75x".
	var text := "%.2f" % value
	return text.rstrip("0").rstrip(".") + "x"
