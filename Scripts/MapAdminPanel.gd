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

var _spin_boxes: Dictionary = {}


func _ready() -> void:
	_build_extra_controls()
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


func _build_extra_controls() -> void:
	## Add numeric spinboxes for every float/int tunable under the seed section.
	_add_float("altitude_frequency", "Altitude frequency", 0.001, 1.0, 0.001, 0.01)
	_add_float("moisture_frequency", "Moisture frequency", 0.001, 1.0, 0.001, 0.01)
	_add_float("temperature_frequency", "Temperature frequency", 0.001, 1.0, 0.001, 0.01)
	_add_float("items_frequency", "Items frequency", 0.01, 4.0, 0.01, 1.0)
	_add_int("fractal_octaves", "Fractal octaves", 1, 10, 5)
	_add_float("fractal_lacunarity", "Fractal lacunarity", 0.1, 4.0, 0.1, 2.0)
	_add_float("fractal_gain", "Fractal gain", 0.0, 2.0, 0.05, 0.5)
	_add_int("chunk_width", "Chunk width", 8, 128, 32)
	_add_int("chunk_height", "Chunk height", 8, 128, 32)
	_add_int("chunk_refresh_frames", "Chunk refresh frames", 1, 120, 15)
	_add_float("water_max_alt", "Water max altitude", -1.0, 1.0, 0.01, 0.2)
	_add_float("sand_max_alt", "Sand max altitude", -1.0, 1.0, 0.01, 0.25)
	_add_float("swamp_special_alt", "Swamp special altitude", -1.0, 1.0, 0.01, 0.26)
	_add_float("ground_chance_a", "Ground chance A", -1.0, 1.0, 0.05, -0.25)
	_add_float("ground_chance_b", "Ground chance B", -1.0, 1.0, 0.05, 0.25)
	_add_float("ground_chance_c", "Ground chance C", -1.0, 1.0, 0.05, 0.75)
	_add_float("bush_min_alt", "Bush min altitude", -1.0, 1.0, 0.01, 0.3)
	_add_float("bush_max_alt", "Bush max altitude", -1.0, 1.0, 0.01, 0.4)
	_add_float("bush_min_chance", "Bush min chance", -1.0, 1.0, 0.05, 0.0)
	_add_float("tree_min_alt", "Tree min altitude", -1.0, 1.0, 0.01, 0.4)
	_add_float("tree_min_chance", "Tree min chance", -1.0, 1.0, 0.05, 0.3)


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
