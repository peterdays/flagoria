extends PanelContainer
## In-game admin panel for map generation parameters. Touch-friendly at 480x270.

signal closed
signal start_host_requested

@onready var scroll: ScrollContainer = $Margin/VBox/Scroll
@onready var form: VBoxContainer = $Margin/VBox/Scroll/Form
@onready var seed_alt: LineEdit = $Margin/VBox/Scroll/Form/SeedRow/AltitudeSeed
@onready var seed_moist: LineEdit = $Margin/VBox/Scroll/Form/SeedRow2/MoistureSeed
@onready var seed_temp: LineEdit = $Margin/VBox/Scroll/Form/SeedRow3/TemperatureSeed
@onready var seed_items: LineEdit = $Margin/VBox/Scroll/Form/SeedRow4/ItemsSeed
@onready var noise_type_opt: OptionButton = $Margin/VBox/Scroll/Form/NoiseTypeRow/NoiseType

## Fields with their own controls in map_admin_panel.tscn.
const HAND_WIRED := ["altitude_seed", "moisture_seed", "temperature_seed", "items_seed", "noise_type"]
## Abbreviations in property names, spelled out in row labels.
const LABEL_WORDS := {"alt": "altitude"}

var _spin_boxes: Dictionary = {}


func _ready() -> void:
	_build_extra_controls(get_node("/root/MapGen").params)
	_populate_noise_types()
	load_from_params(get_node("/root/MapGen").params)


func _populate_noise_types() -> void:
	noise_type_opt.clear()
	noise_type_opt.add_item("Value", FastNoiseLite.TYPE_VALUE)
	noise_type_opt.add_item("Value Cubic", FastNoiseLite.TYPE_VALUE_CUBIC)
	noise_type_opt.add_item("Perlin", FastNoiseLite.TYPE_PERLIN)
	noise_type_opt.add_item("Cellular", FastNoiseLite.TYPE_CELLULAR)
	noise_type_opt.add_item("Simplex", FastNoiseLite.TYPE_SIMPLEX)
	noise_type_opt.add_item("Simplex Smooth", FastNoiseLite.TYPE_SIMPLEX_SMOOTH)


func _build_extra_controls(params: MapGenParams) -> void:
	## One spinbox row per exported int/float property outside HAND_WIRED, in
	## declaration order, with min/max/step from its @export_range hint.
	for prop in params.exported_properties():
		var key: String = prop["name"]
		if HAND_WIRED.has(key):
			continue
		if prop["hint"] != PROPERTY_HINT_RANGE:
			push_warning("MapGenParams.%s has no @export_range; no Map Settings row" % key)
			continue
		var bounds: PackedStringArray = prop["hint_string"].split(",")
		if prop["type"] == TYPE_INT:
			_add_int(key, _label_for(key), bounds[0].to_int(), bounds[1].to_int(), params.get(key))
		elif prop["type"] == TYPE_FLOAT:
			var step := bounds[2].to_float() if bounds.size() > 2 else 0.0
			_add_float(key, _label_for(key), bounds[0].to_float(), bounds[1].to_float(), step, params.get(key))


func _label_for(key: String) -> String:
	## "water_max_alt" -> "Water max altitude", "ground_chance_a" -> "Ground chance A".
	var words := PackedStringArray()
	for word in key.split("_"):
		word = LABEL_WORDS.get(word, word)
		words.append(word.to_upper() if word.length() == 1 else word)
	var text := " ".join(words)
	return text[0].to_upper() + text.substr(1)


func _add_float(key: String, label_text: String, min_v: float, max_v: float, step: float, default_v: float) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(140, 0)
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = default_v
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.custom_minimum_size = Vector2(100, 22)
	row.add_child(label)
	row.add_child(spin)
	form.add_child(row)
	_spin_boxes[key] = spin


func _add_int(key: String, label_text: String, min_v: int, max_v: int, default_v: int) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(140, 0)
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1
	spin.rounded = true
	spin.value = default_v
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.custom_minimum_size = Vector2(100, 22)
	row.add_child(label)
	row.add_child(spin)
	form.add_child(row)
	_spin_boxes[key] = spin


func load_from_params(p: MapGenParams) -> void:
	if seed_alt == null:
		return
	seed_alt.text = str(p.altitude_seed)
	seed_moist.text = str(p.moisture_seed)
	seed_temp.text = str(p.temperature_seed)
	seed_items.text = str(p.items_seed)
	var idx = noise_type_opt.get_item_index(p.noise_type)
	if idx >= 0:
		noise_type_opt.select(idx)
	for key in _spin_boxes.keys():
		var spin: SpinBox = _spin_boxes[key]
		spin.value = p.get(key)
		# SpinBox leaves LineEdit text unchanged when the numeric value is
		# already equal, so a typed-but-uncommitted string can survive a reopen.
		spin.get_line_edit().text = str(spin.value)


func apply_to_params(p: MapGenParams) -> void:
	p.altitude_seed = int(seed_alt.text) if seed_alt.text.is_valid_int() else 0
	p.moisture_seed = int(seed_moist.text) if seed_moist.text.is_valid_int() else 0
	p.temperature_seed = int(seed_temp.text) if seed_temp.text.is_valid_int() else 0
	p.items_seed = int(seed_items.text) if seed_items.text.is_valid_int() else 0
	p.noise_type = noise_type_opt.get_selected_id()
	for key in _spin_boxes.keys():
		p.set(key, _spin_boxes[key].value)


func _on_random_seed_pressed() -> void:
	apply_to_params(get_node("/root/MapGen").params)
	get_node("/root/MapGen").randomize_seeds()
	load_from_params(get_node("/root/MapGen").params)


func _on_reset_pressed() -> void:
	get_node("/root/MapGen").reset_to_defaults()
	load_from_params(get_node("/root/MapGen").params)


func _on_back_pressed() -> void:
	apply_to_params(get_node("/root/MapGen").params)
	get_node("/root/MapGen").save_to_disk()
	hide()
	emit_signal("closed")


func _on_start_pressed() -> void:
	apply_to_params(get_node("/root/MapGen").params)
	get_node("/root/MapGen").save_to_disk()
	hide()
	emit_signal("start_host_requested")
