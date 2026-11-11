class_name RunControl
extends Button
## HUD control for a faster walk (#449).
##
## A press of TAP_FRAMES process frames or fewer toggles run on or off.
## A longer press runs only while the button is held. The run action (Shift)
## also runs while it is held, without toggling. Walk speed only: chop reach,
## the sword and the joystick direction are unchanged.

## Process frames at or under this length are a tap. A drive click is two
## frames, so this stays a tap even when a frame is slow.
const TAP_FRAMES := 12
## Run acceleration and the speed cap, as a multiple of the walk values.
const SPEED_SCALE := 2.0

var latched := false
var held := false
var _down_frame := 0
var _toggled_frame := -1


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = "Run"
	tooltip_text = "Hold to run, or tap to keep running"
	_fit()
	button_down.connect(_on_down)
	button_up.connect(_on_up)


func _process(_delta: float) -> void:
	var on := running()
	if button_pressed != on:
		set_pressed_no_signal(on)
	var label := "RUN" if on else "Run"
	if text != label:
		text = label


func running() -> bool:
	## True while the button is held, latched on, or the run action is down.
	return held or latched or Input.is_action_pressed("run")


func speed_scale() -> float:
	## 1 while walking, SPEED_SCALE while running.
	return SPEED_SCALE if running() else 1.0


func _on_down() -> void:
	held = true
	_down_frame = Engine.get_process_frames()


func _on_up() -> void:
	if not held:
		return
	var frames := Engine.get_process_frames() - _down_frame
	held = false
	# A mouse click and the touch it emulates can both arrive in one frame.
	# That pair is one tap, so the second release does not undo the first.
	if frames <= TAP_FRAMES and _toggled_frame != Engine.get_process_frames():
		latched = not latched
		_toggled_frame = Engine.get_process_frames()


func _fit() -> void:
	## Smaller than the attack button. The word still reads Run or RUN;
	## font 6 fits that word inside the disc.
	add_theme_font_size_override("font_size", 6)
	add_theme_constant_override("outline_size", 1)
	RoundHudStyle.apply(self, RoundHudStyle.RUN_HIT, RoundHudStyle.RUN_SIZE)
	reset_size()


func _get_minimum_size() -> Vector2:
	return Vector2(RoundHudStyle.RUN_HIT, RoundHudStyle.RUN_HIT)
