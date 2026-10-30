class_name NumberPad
extends Control
## In-game keys for LineEdits, so touch devices do not pop up the OS keyboard.
## attach() gives a number field the digit pad and attach_spin_box() does the
## same for a SpinBox; attach_text() gives a text field the letter keyboard
## (letters, digits, "." and ":"). Focusing or tapping the field opens the
## keys, OK or a tap outside closes them. The field's text is selected on open,
## so the first key replaces it. A physical keyboard keeps working, and a
## number field drops anything it does not accept. Number fields that allow a
## sign or a decimal point also get "-" and "." keys. The keycap styles are
## theme type variations in art/ui/main_menu_theme.tres.

## Used when the field sets no max_length; keeps the text a valid 64-bit int.
const DEFAULT_MAX_DIGITS := 18
const DEFAULT_MAX_LETTERS := 64
## Digit pad: three columns of digits, and a column of action keys where OK
## grows into the rows that a hidden "-" or "." leaves free.
const DIGIT_ROWS := [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["0"]]
const DIGIT_ACTIONS := ["Delete", "Minus", "Point", "OK"]
const LETTER_ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "Colon"],
	["z", "x", "c", "v", "b", "n", "m", "Point", "Delete", "OK"],
]
## Keys whose node name differs from the character they type.
const KEY_CHAR := {"Minus": "-", "Point": ".", "Colon": ":"}
const KEY_TEXT := {"Delete": "Del", "OK": "OK"}
const KEY_STYLE := {"Delete": &"KeyCapDelete", "OK": &"KeyCapOK"}
const DIGIT_KEY_SIZE := Vector2(44, 26)
const LETTER_KEY_SIZE := Vector2(30, 24)
const KEY_GAP := 3

var target: LineEdit
## Per field: {"negative": bool, "decimal": bool, "commit": Callable, "letters": bool}.
var _rules := {}
## Pointers (mouse left button, touch indexes) held down right now.
var _held := {}
## True while the press that opened the pad is still held. Its release, and the
## emulated twin of that press, belong to the tap on the field, not to the pad.
var _opening_tap := false
## Which key layout is built: null (none yet), false (digits) or true (letters).
var _letters = null

@onready var _panel: PanelContainer = $Panel
@onready var _keys: MarginContainer = $Panel/Margin


func _ready() -> void:
	hide()


func attach(field: LineEdit, negative := false, decimal := false, commit := Callable()) -> void:
	_hook(field, {"negative": negative, "decimal": decimal, "commit": commit, "letters": false})
	field.text_changed.connect(func(_t: String) -> void: _keep_digits(field, negative, decimal))


func attach_spin_box(spin: SpinBox) -> void:
	## The pad edits the SpinBox's text; closing the pad commits it, and the
	## SpinBox clamps and snaps it to its own min, max and step.
	var decimal := not spin.rounded and not is_equal_approx(spin.step, roundf(spin.step))
	attach(spin.get_line_edit(), spin.min_value < 0.0, decimal, spin.apply)


func attach_text(field: LineEdit) -> void:
	_hook(field, {"letters": true})


func _hook(field: LineEdit, rules: Dictionary) -> void:
	_rules[field] = rules
	field.virtual_keyboard_enabled = false
	field.select_all_on_focus = true
	field.focus_entered.connect(open.bind(field))
	field.gui_input.connect(func(event: InputEvent) -> void:
		if _is_tap(event) and not visible:
			open(field))


func open(field: LineEdit) -> void:
	target = field
	_opening_tap = not _held.is_empty()
	var rules: Dictionary = _rules.get(field, {})
	_build(rules.get("letters", false))
	if not _letters:
		_keys.find_child("Minus", true, false).visible = rules.get("negative", false)
		_keys.find_child("Point", true, false).visible = rules.get("decimal", false)
	show()
	_place_beside(field)
	# Deferred, so a click that focused the field and placed its caret does
	# not clear the selection again.
	(func() -> void:
		if target == field:
			field.select_all()).call_deferred()


func close() -> void:
	var field := target
	hide()
	target = null
	if field != null:
		var commit: Callable = _rules.get(field, {}).get("commit", Callable())
		if commit.is_valid():
			commit.call()


func _build(letters: bool) -> void:
	if _letters == letters:
		return
	_letters = letters
	for child in _keys.get_children():
		child.free()
	if letters:
		var rows := _box(VBoxContainer.new())
		for row in LETTER_ROWS:
			var line := _box(HBoxContainer.new())
			line.alignment = BoxContainer.ALIGNMENT_CENTER
			for key in row:
				var b := _key(key, LETTER_KEY_SIZE)
				if key in KEY_TEXT:
					b.custom_minimum_size.x = LETTER_KEY_SIZE.x * 1.5
				line.add_child(b)
			rows.add_child(line)
		_keys.add_child(rows)
		return
	var body := _box(HBoxContainer.new())
	var digits := _box(VBoxContainer.new())
	for row in DIGIT_ROWS:
		var line := _box(HBoxContainer.new())
		for key in row:
			var b := _key(key, DIGIT_KEY_SIZE)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(b)
		digits.add_child(line)
	var actions := _box(VBoxContainer.new())
	for key in DIGIT_ACTIONS:
		actions.add_child(_key(key, DIGIT_KEY_SIZE))
	actions.get_node("OK").size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(digits)
	body.add_child(actions)
	_keys.add_child(body)


func _key(key: String, key_size: Vector2) -> Button:
	var b := Button.new()
	b.name = "Digit" + key if key.is_valid_int() else key
	b.text = KEY_TEXT.get(key, KEY_CHAR.get(key, key))
	b.theme_type_variation = KEY_STYLE.get(key, &"KeyCap")
	b.custom_minimum_size = key_size
	# Keep focus (and the caret) on the field so a keyboard still types there.
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_on_key.bind(key))
	return b


static func _box(box: BoxContainer) -> BoxContainer:
	box.add_theme_constant_override("separation", KEY_GAP)
	return box


func _on_key(key: String) -> void:
	if target == null:
		return
	if key == "OK":
		close()
		return
	# The text is selected while the pad is fresh, so the first key replaces it.
	if target.has_selection():
		target.text = ""
	if key == "Delete":
		target.text = target.text.left(-1)
	elif _letters:
		if target.text.length() < _max_length(target):
			target.text += KEY_CHAR.get(key, key)
	else:
		match key:
			"Minus":
				target.text = target.text.substr(1) if target.text.begins_with("-") else "-" + target.text
			"Point":
				if not target.text.contains("."):
					target.text += "0." if target.text in ["", "-"] else "."
			_:
				if target.text in ["0", "-0"]:
					target.text = target.text.left(-1)
				if target.text.length() < _max_digits(target):
					target.text += key
	target.caret_column = target.text.length()


func _input(event: InputEvent) -> void:
	## Track held pointers before the GUI routes the event. On Android a tap
	## arrives as an emulated mouse press, then the touch press, then both
	## releases; the mouse press focuses the field and opens the pad, so the
	## touch press and release of that same tap land on the pad. A new tap
	## starts only when nothing is held.
	var key = _pointer_key(event)
	if key == null:
		return
	if event.pressed:
		# A press of a key still marked held means its release was lost.
		if _held.is_empty() or _held.has(key):
			_held.clear()
			_opening_tap = false
		_held[key] = true
	else:
		_held.erase(key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_held.clear()


func _gui_input(event: InputEvent) -> void:
	# The pad panel takes its own clicks, so a tap that reaches here is outside it.
	if _pointer_key(event) != null:
		accept_event()
	if _is_tap(event) and not _opening_tap:
		close()


func _place_beside(field: LineEdit) -> void:
	## Keep the field and its text visible: a narrow pad goes on the side of
	## the screen away from the field, a wide keyboard above or below it.
	_panel.reset_size()
	var pad_size := _panel.get_combined_minimum_size()
	var screen := get_viewport_rect().size
	var field_center := field.get_global_rect().get_center()
	var pos := Vector2(8.0, 8.0)
	if pad_size.x <= screen.x / 2.0:
		if field_center.x < screen.x / 2.0:
			pos.x = screen.x - pad_size.x - 8.0
		pos.y = clampf(field_center.y - pad_size.y / 2.0, 0.0, maxf(screen.y - pad_size.y, 0.0))
	else:
		pos.x = (screen.x - pad_size.x) / 2.0
		if field_center.y < screen.y / 2.0:
			pos.y = screen.y - pad_size.y - 8.0
	_panel.global_position = Vector2(maxf(pos.x, 0.0), maxf(pos.y, 0.0))


static func _keep_digits(field: LineEdit, negative := false, decimal := false) -> void:
	## Keeps digits, plus a leading "-" and one "." when the field allows them.
	var digits := ""
	for ch in field.text:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif ch == "-" and negative and digits.is_empty():
			digits += ch
		elif ch == "." and decimal and not digits.contains("."):
			digits += ch
	digits = digits.left(_max_digits(field))
	if digits != field.text:
		var caret := field.caret_column - (field.text.length() - digits.length())
		field.text = digits
		field.caret_column = clampi(caret, 0, digits.length())


static func _max_digits(field: LineEdit) -> int:
	return field.max_length if field.max_length > 0 else DEFAULT_MAX_DIGITS


static func _max_length(field: LineEdit) -> int:
	return field.max_length if field.max_length > 0 else DEFAULT_MAX_LETTERS


static func _pointer_key(event: InputEvent) -> Variant:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return "mouse"
	if event is InputEventScreenTouch:
		return "touch%d" % event.index
	return null


static func _is_tap(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	return event is InputEventScreenTouch and not event.pressed
