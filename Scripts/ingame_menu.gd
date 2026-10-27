extends Control
## In-game menu: a Menu button in the HUD corner (or Esc on desktop) opens a
## small panel over the game. The game keeps running underneath; nothing is
## paused, locally or for other players.
##
## Resume closes the panel. Main menu leaves the match: Flagoria closes the
## network session and reloads the main scene, which frees the world and
## brings back the main menu and its music.

@onready var menu_button: Button = $MenuButton
@onready var panel: Control = $Pause
@onready var resume_button: Button = $Pause/Panel/Margin/VBox/Resume
@onready var main_menu_button: Button = $Pause/Panel/Margin/VBox/MainMenu


func _ready() -> void:
	menu_button.pressed.connect(open)
	resume_button.pressed.connect(close)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	# Buttons for later entries (Save) go in Pause/Panel/Margin/VBox,
	# between Resume and Main menu, and connect here.


func is_open() -> bool:
	return panel.visible


func open() -> void:
	panel.show()
	menu_button.hide()
	resume_button.grab_focus()


func close() -> void:
	panel.hide()
	menu_button.show()


func _unhandled_input(event: InputEvent) -> void:
	# Only during a match: the HUD layer is hidden on the main menu.
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		close() if is_open() else open()
		get_viewport().set_input_as_handled()


func _on_main_menu_pressed() -> void:
	get_node("/root/Flagoria").leave_to_main_menu()
