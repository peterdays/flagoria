extends Control
## Quit prompt: the Android back button, or closing the desktop window, asks
## "Do you want to quit?" instead of exiting at once. Works on the main menu
## and in a match; nothing is paused behind it, locally or for other players.
##
## Cancel, Esc, or another back press while it is open closes it. Quit emits
## quit_confirmed; Flagoria closes the network session and quits.

signal quit_confirmed

@onready var panel: Control = $Dim
@onready var quit_button: Button = $Dim/Panel/Margin/VBox/Buttons/Quit
@onready var cancel_button: Button = $Dim/Panel/Margin/VBox/Buttons/Cancel


func _ready() -> void:
	# Back and window close arrive as notifications instead of quitting.
	get_tree().set_quit_on_go_back(false)
	get_tree().set_auto_accept_quit(false)
	quit_button.pressed.connect(quit_confirmed.emit)
	cancel_button.pressed.connect(close)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		close() if is_open() else open()


func is_open() -> bool:
	return panel.visible


func open() -> void:
	panel.show()
	cancel_button.grab_focus()


func close() -> void:
	panel.hide()


func _input(event: InputEvent) -> void:
	# Ahead of the in-game menu: while open, Esc only closes the prompt.
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
