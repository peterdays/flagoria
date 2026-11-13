extends Control
## In-game menu: a three-bar menu button in the HUD corner (or Esc on
## desktop) opens a small panel over the game. The game keeps running
## underneath; nothing is paused, locally or for other players.
##
## Resume closes the panel. Save writes the current world into its own save
## (docs/world-saves.md). A new match is named after the date and time; later
## saves of that match replace that file. The line under the buttons stays
## one line high, and the panel stays open. Main menu leaves the match:
## Flagoria closes the network session and reloads the main scene.

## The HUD menu button is an 18 px square (48 screen px at 1280x720): big
## enough to tap, small enough to keep the corner clear.
const ICON_BUTTON_PAD := 2  ## px left and right of the icon at 1x

@onready var menu_button: Button = $MenuButton
@onready var panel: Control = $Pause
@onready var resume_button: Button = $Pause/Panel/Margin/VBox/Resume
@onready var save_button: Button = $Pause/Panel/Margin/VBox/Save
@onready var customize_hud_button: Button = $Pause/Panel/Margin/VBox/CustomizeHud
@onready var main_menu_button: Button = $Pause/Panel/Margin/VBox/MainMenu
@onready var status_label: Label = $Pause/Panel/Margin/VBox/Status
@onready var hud_layout_edit: Control = $HudLayoutEdit


func _ready() -> void:
	fit_icon_button(menu_button)
	menu_button.pressed.connect(open)
	resume_button.pressed.connect(close)
	save_button.pressed.connect(save_world)
	customize_hud_button.pressed.connect(_on_customize_hud_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)


static func fit_icon_button(button: Button) -> void:
	## The theme's button styles, with side padding sized for an icon, not text.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_left = ICON_BUTTON_PAD
		style.content_margin_right = ICON_BUTTON_PAD
		button.add_theme_stylebox_override(state, style)


func is_open() -> bool:
	return panel.visible


func open() -> void:
	panel.show()
	menu_button.hide()
	resume_button.grab_focus()


func close() -> void:
	panel.hide()
	status_label.text = ""
	menu_button.show()


func _unhandled_input(event: InputEvent) -> void:
	# Only during a match: the HUD layer is hidden on the main menu.
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		close() if is_open() else open()
		get_viewport().set_input_as_handled()


func save_world() -> Dictionary:
	## Saves the world being played: its generation inputs as this peer
	## received or chose them (Flagoria.world_params), this peer's tree and
	## bush cuts (world.object_changes), plank bridges (world.tile_edits,
	## #226), placed structures and walls (world.structures, #42), and this
	## peer's player state (world.player, #197). {"path", "error"}.
	var params: MapGenParams = owner.world_params if owner else null
	var result := {"path": "", "error": "the world has not loaded yet"}
	if params != null:
		var save_name := str(owner.save_name) if owner != null and owner.save_name != "" else ""
		if save_name == "":
			save_name = unused_save_name(auto_save_name(Time.get_datetime_dict_from_system()))
			if owner != null:
				owner.save_name = save_name
		var world := WorldSave.new(params)
		var world_map := owner.get_node_or_null("World/worldMap")
		if world_map:
			world.object_changes = world_map.cut_changes()
			world.tile_edits = BridgeBuilder.to_changes(world_map.bridges_for_sync())
			world.structures = StructureSaves.to_changes(world_map)
		world.player = PlayerSave.capture(owner)
		result = get_node("/root/MapGen").save_world(world, save_name)
	if result["error"] == "":
		status_label.text = saved_text(result["path"].get_file().get_basename())
	else:
		status_label.text = "Not saved: %s" % result["error"]
	return result


static func saved_text(save_name: String) -> String:
	## "Saved: 10-27 22:15" for "2026-10-27 22-15-03" (" 2" and the like
	## dropped): one line in the panel at the theme's label size.
	return "Saved: %s %s" % [save_name.substr(5, 5), save_name.substr(11, 5).replace("-", ":")]


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


func _on_customize_hud_pressed() -> void:
	if hud_layout_edit != null and hud_layout_edit.has_method("open"):
		hud_layout_edit.open()


func _on_main_menu_pressed() -> void:
	get_node("/root/Flagoria").leave_to_main_menu()
