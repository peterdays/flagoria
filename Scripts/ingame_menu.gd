extends Control
## In-game menu: a Menu button in the HUD corner (or Esc on desktop) opens a
## small panel over the game. The game keeps running underneath; nothing is
## paused, locally or for other players.
##
## Resume closes the panel. Save writes the current world as a world save
## (docs/world-saves.md) named after the date and time, and says so under the
## buttons; the panel stays open, so the player can resume or leave. Main menu
## leaves the match: Flagoria closes the network session and reloads the main
## scene, which frees the world and brings back the main menu and its music.

@onready var menu_button: Button = $MenuButton
@onready var panel: Control = $Pause
@onready var resume_button: Button = $Pause/Panel/Margin/VBox/Resume
@onready var save_button: Button = $Pause/Panel/Margin/VBox/Save
@onready var main_menu_button: Button = $Pause/Panel/Margin/VBox/MainMenu
@onready var status_label: Label = $Pause/Panel/Margin/VBox/Status


func _ready() -> void:
	menu_button.pressed.connect(open)
	resume_button.pressed.connect(close)
	save_button.pressed.connect(save_world)
	main_menu_button.pressed.connect(_on_main_menu_pressed)


func is_open() -> bool:
	return panel.visible


func open() -> void:
	panel.show()
	menu_button.hide()
	resume_button.grab_focus()


func close() -> void:
	panel.hide()
	_show_status("")
	menu_button.show()


func _unhandled_input(event: InputEvent) -> void:
	# Only during a match: the HUD layer is hidden on the main menu.
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		close() if is_open() else open()
		get_viewport().set_input_as_handled()


func save_world() -> Dictionary:
	## Saves the world being played: its generation inputs as this peer
	## received or chose them (Flagoria.world_params), and empty change
	## sections until the features that fill them land. {"path", "error"}.
	var params: MapGenParams = owner.world_params if owner else null
	var result := {"path": "", "error": "the world has not loaded yet"}
	if params != null:
		var save_name := unused_save_name(auto_save_name(Time.get_datetime_dict_from_system()))
		result = get_node("/root/MapGen").save_world(WorldSave.new(params), save_name)
	if result["error"] == "":
		_show_status("Saved as %s" % result["path"].get_file().get_basename())
	else:
		_show_status("Not saved: %s" % result["error"])
	return result


func _show_status(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


static func auto_save_name(now: Dictionary) -> String:
	## "2026-10-27 22-15-03" for a Time datetime dict. Sorts by time, and
	## has no characters that validate_filename would change.
	return "%04d-%02d-%02d %02d-%02d-%02d" % [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]]


static func unused_save_name(base: String) -> String:
	## base, or "base 2", "base 3"... so a second save in the same second
	## never replaces the first.
	var save_name := base
	var n := 2
	while FileAccess.file_exists(MapSave.path_for(save_name)):
		save_name = "%s %d" % [base, n]
		n += 1
	return save_name


func _on_main_menu_pressed() -> void:
	get_node("/root/Flagoria").leave_to_main_menu()
