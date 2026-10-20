extends Node
## Autoload: Music and SFX volume, applied to the buses in
## default_bus_layout.tres and saved in user settings.
##
## Volumes are linear 0..1 (slider position). 0 mutes the bus; anything else
## sets volume_db = linear_to_db(value).

const SECTION := "audio"
const BUSES := ["Music", "SFX"]
## SFX at 1.0 keeps game sounds at their designed level.
const DEFAULTS := {"Music": 0.6, "SFX": 1.0}

## Tests point this at a scratch file.
var save_path := "user://audio_settings.cfg"
var _volumes := DEFAULTS.duplicate()


func _ready() -> void:
	load_from_disk()


func get_volume(bus: String) -> float:
	return float(_volumes.get(bus, 1.0))


func set_volume(bus: String, value: float, save := true) -> void:
	if not BUSES.has(bus):
		push_error("audio settings: unknown bus %s" % bus)
		return
	value = clampf(value, 0.0, 1.0)
	_volumes[bus] = value
	_apply(bus)
	if save:
		save_to_disk()


func reset_to_defaults() -> void:
	_volumes = DEFAULTS.duplicate()
	for bus in BUSES:
		_apply(bus)


func _apply(bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		push_error("audio settings: bus %s missing from the bus layout" % bus)
		return
	var value := get_volume(bus)
	AudioServer.set_bus_mute(idx, value <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(value) if value > 0.0 else -80.0)


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for bus in BUSES:
		cfg.set_value(SECTION, bus, get_volume(bus))
	cfg.save(save_path)


func load_from_disk() -> void:
	## Load saved volumes (defaults for anything missing) and apply them.
	_volumes = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		for bus in BUSES:
			_volumes[bus] = parse_volume(cfg.get_value(SECTION, bus, DEFAULTS[bus]), DEFAULTS[bus])
	for bus in BUSES:
		_apply(bus)


static func parse_volume(value: Variant, fallback: float) -> float:
	## A saved volume, or `fallback` if it is not a finite number or is
	## negative (a hand-edited or corrupt file must not crash or mute).
	## Values above 1 are clamped to 1.
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var v := float(value)
	if is_nan(v) or is_inf(v) or v < 0.0:
		return fallback
	return minf(v, 1.0)
