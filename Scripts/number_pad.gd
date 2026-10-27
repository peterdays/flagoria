class_name NumberPad
extends Control
## Small in-game digit pad for numeric LineEdits, so touch devices do not
## pop up the OS keyboard. Call attach() on each field; focusing or tapping
## the field opens the pad, OK or a tap outside the pad closes it. A physical
## keyboard keeps working, and anything that is not a digit is dropped.

## Used when the field sets no max_length; keeps the text a valid 64-bit int.
const DEFAULT_MAX_DIGITS := 18
const KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "Delete", "0", "OK"]
const KEY_SIZE := Vector2(44, 26)

var target: LineEdit
## Pointers (mouse left button, touch indexes) held down right now.
var _held := {}
## True while the press that opened the pad is still held. Its release, and the
## emulated twin of that press, belong to the tap on the field, not to the pad.
var _opening_tap := false

@onready var _panel: PanelContainer = $Panel
@onready var _grid: GridContainer = $Panel/Margin/Grid


func _ready() -> void:
	hide()
	for key in KEYS:
		var b := Button.new()
		b.name = key if key.length() > 1 else "Digit" + key
		b.text = "Del" if key == "Delete" else key
		b.custom_minimum_size = KEY_SIZE
		# Keep focus (and the caret) on the field so a keyboard still types there.
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_key.bind(key))
		_grid.add_child(b)


func attach(field: LineEdit) -> void:
	field.virtual_keyboard_enabled = false
	field.focus_entered.connect(open.bind(field))
	field.gui_input.connect(func(event: InputEvent) -> void:
		if _is_tap(event) and not visible:
			open(field))
	field.text_changed.connect(func(_t: String) -> void: _keep_digits(field))


func open(field: LineEdit) -> void:
	target = field
	_opening_tap = not _held.is_empty()
	show()
	_place_beside(field)


func close() -> void:
	hide()
	target = null


func _on_key(key: String) -> void:
	if target == null:
		return
	match key:
		"OK":
			close()
			return
		"Delete":
			target.text = target.text.left(-1)
		_:
			if target.text == "0":
				target.text = ""
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
	## Put the pad on the side of the screen away from the field, so the
	## field and its digits stay visible.
	_panel.reset_size()
	var pad_size := _panel.get_combined_minimum_size()
	var screen := get_viewport_rect().size
	var field_center := field.get_global_rect().get_center()
	var x := 8.0
	if field_center.x < screen.x / 2.0:
		x = screen.x - pad_size.x - 8.0
	var y := clampf(field_center.y - pad_size.y / 2.0, 0.0, maxf(screen.y - pad_size.y, 0.0))
	_panel.global_position = Vector2(maxf(x, 0.0), y)


static func _keep_digits(field: LineEdit) -> void:
	var digits := ""
	for ch in field.text:
		if ch >= "0" and ch <= "9":
			digits += ch
	digits = digits.left(_max_digits(field))
	if digits != field.text:
		var caret := field.caret_column - (field.text.length() - digits.length())
		field.text = digits
		field.caret_column = clampi(caret, 0, digits.length())


static func _max_digits(field: LineEdit) -> int:
	return field.max_length if field.max_length > 0 else DEFAULT_MAX_DIGITS


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
