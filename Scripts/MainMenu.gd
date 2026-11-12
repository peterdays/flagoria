extends PanelContainer

const JoinAddress = preload("res://Scripts/join_address.gd")
const WorldsSaveList = preload("res://Scripts/worlds_save_list.gd")

@onready var main_menu = $"."
@onready var address_entry = $MarginContainer/VBoxContainer/AddressEntry
@onready var join_status: Label = $MarginContainer/VBoxContainer/JoinStatus
@onready var ux_layer = $/root/Flagoria/CanvasLayer1
@onready var music_volume: HSlider = $MarginContainer/VBoxContainer/MusicVolumeRow/MusicVolume
@onready var sfx_volume: HSlider = $MarginContainer/VBoxContainer/SFXVolumeRow/SFXVolume
@onready var music_value: Label = $MarginContainer/VBoxContainer/MusicVolumeRow/MusicValue
@onready var sfx_value: Label = $MarginContainer/VBoxContainer/SFXVolumeRow/SFXValue
@onready var mob_rate: HSlider = $MarginContainer/VBoxContainer/MobRateRow/MobRate
@onready var mob_rate_value: Label = $MarginContainer/VBoxContainer/MobRateRow/MobRateValue

var admin_panel: PanelContainer

signal new_server_created
signal new_player_added
signal new_player_joined(port: int)


func _ready() -> void:
	var music = get_node("/root/MusicPlayer")
	music.play(music.MENU_TRACK)
	var audio = get_node("/root/AudioSettings")
	music_volume.value = audio.get_volume("Music")
	sfx_volume.value = audio.get_volume("SFX")
	music_value.text = percent(music_volume.value)
	sfx_value.text = percent(sfx_volume.value)
	music_volume.value_changed.connect(func(v: float) -> void:
		audio.set_volume("Music", v)
		music_value.text = percent(v))
	sfx_volume.value_changed.connect(func(v: float) -> void:
		audio.set_volume("SFX", v)
		sfx_value.text = percent(v))
	# Mob spawn rate: used when this game hosts; a joining client gets the
	# host's mobs.
	var game = get_node("/root/GameSettings")
	mob_rate.min_value = game.MOB_RATE_MIN
	mob_rate.max_value = game.MOB_RATE_MAX
	mob_rate.step = game.MOB_RATE_STEP
	mob_rate.value = game.mob_rate
	mob_rate_value.text = game.rate_label(game.mob_rate)
	mob_rate.value_changed.connect(func(v: float) -> void:
		game.set_mob_rate(v)
		mob_rate_value.text = game.rate_label(game.mob_rate))
	# The join address is typed on the in-game letter keyboard, not the OS one.
	var keyboard: NumberPad = preload("res://number_pad.tscn").instantiate()
	keyboard.name = "LetterKeyboard"
	add_child(keyboard)
	keyboard.attach_text(address_entry)
	visibility_changed.connect(keyboard.close)
	admin_panel = preload("res://map_admin_panel.tscn").instantiate()
	admin_panel.visible = false
	admin_panel.closed.connect(_on_admin_closed)
	admin_panel.start_host_requested.connect(_on_host_button_pressed)
	# Defer so we are not adding children while the parent CanvasLayer is still setting up.
	get_parent().call_deferred("add_child", admin_panel)


static func percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


func _unhandled_input(_event):
	# No "quit" action is mapped in project.godot. Without this guard the check
	# logs an InputMap error for every unhandled event.
	if InputMap.has_action("quit") and Input.is_action_just_pressed("quit"):
		get_tree().quit()


func _on_new_world_pressed() -> void:
	## A new match, even if a save was loaded and not hosted yet.
	get_node("/root/MapGen").clear_loaded_world()
	get_node("/root/Flagoria").save_name = ""
	_on_host_button_pressed()


func _on_host_button_pressed():
	## Host the loaded world when there is one. Otherwise start a new match
	## in its own save file.
	var map_gen = get_node("/root/MapGen")
	var game = get_node("/root/Flagoria")
	if not map_gen.has_loaded_world():
		var menu_script: GDScript = load("res://Scripts/ingame_menu.gd")
		game.save_name = menu_script.unused_save_name(
				menu_script.auto_save_name(Time.get_datetime_dict_from_system()))
	_begin_host()


func _begin_host() -> void:
	var map_gen = get_node("/root/MapGen")
	map_gen.save_to_disk()
	emit_signal("new_server_created", map_gen.params.duplicate_params())
	main_menu.hide()
	if admin_panel:
		admin_panel.hide()
	var worlds := get_parent().get_node_or_null("WorldsPanel")
	if worlds:
		worlds.hide()
	ux_layer.show()
	get_node("/root/MusicPlayer").play(get_node("/root/MusicPlayer").GAME_TRACK)
	emit_signal("new_player_added", multiplayer.get_unique_id())


func _on_join_button_pressed():
	var parsed: Dictionary = JoinAddress.parse(address_entry.text)
	if not parsed["ok"]:
		# Stay on the menu. A bad address never opens an ENet client.
		show_address_error(str(parsed["error"]))
		return
	join_status.visible = false
	join_status.text = ""
	main_menu.hide()
	if admin_panel:
		admin_panel.hide()
	ux_layer.show()
	get_node("/root/MusicPlayer").play(get_node("/root/MusicPlayer").GAME_TRACK)
	emit_signal("new_player_joined", int(parsed["port"]))


func _on_worlds_pressed() -> void:
	var panel := _worlds_panel()
	main_menu.hide()
	panel.show()
	_refresh_worlds()
	var scroll := panel.get_node_or_null("Margin/VBox/Scroll") as ScrollContainer
	if scroll:
		scroll.scroll_vertical = 0


func _worlds_list() -> ItemList:
	return _worlds_panel().get_node("Margin/VBox/Scroll/List") as ItemList


func _worlds_panel() -> PanelContainer:
	var existing := get_parent().get_node_or_null("WorldsPanel") as PanelContainer
	if existing:
		return existing
	var panel := PanelContainer.new()
	panel.name = "WorldsPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.theme = theme
	panel.visible = false
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "VBox"
	box.custom_minimum_size = Vector2(240, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	var title := Label.new()
	title.text = "Worlds"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 96)
	box.add_child(scroll)
	var list := WorldsSaveList.new()
	list.name = "List"
	list.auto_height = true
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	box.add_child(buttons)
	_world_button(buttons, "Load", _on_load_world_pressed)
	_world_button(buttons, "Delete", _on_delete_world_pressed)
	_world_button(buttons, "Rename", _on_rename_world_pressed)
	_world_button(buttons, "NewWorld", _on_new_world_pressed).text = "New world"
	var confirm := HBoxContainer.new()
	confirm.name = "Confirm"
	confirm.visible = false
	box.add_child(confirm)
	var ask := Label.new()
	ask.name = "Ask"
	ask.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ask.text = "Delete this world?"
	confirm.add_child(ask)
	_world_button(confirm, "Yes", _on_delete_yes_pressed)
	_world_button(confirm, "No", _on_delete_no_pressed)
	var rename := HBoxContainer.new()
	rename.name = "Rename"
	rename.visible = false
	box.add_child(rename)
	var rename_field := LineEdit.new()
	rename_field.name = "Name"
	rename_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_field.text_submitted.connect(_on_rename_yes_pressed)
	rename.add_child(rename_field)
	var keyboard := get_node_or_null("LetterKeyboard")
	if keyboard:
		keyboard.attach_text(rename_field)
	_world_button(rename, "Confirm", _on_rename_yes_pressed)
	_world_button(rename, "Cancel", _on_rename_no_pressed)
	var status := Label.new()
	status.name = "Status"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_world_button(box, "Back", _on_worlds_back_pressed)
	get_parent().add_child(panel)
	return panel


func _world_button(parent: Node, node_name: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = node_name
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _refresh_worlds() -> void:
	var list := _worlds_list()
	list.clear()
	for row in MapSave.list_saves():
		var when: Dictionary = Time.get_datetime_dict_from_unix_time(int(row["modified"]))
		var stamp := "%04d-%02d-%02d %02d:%02d" % [when["year"], when["month"], when["day"], when["hour"], when["minute"]]
		list.add_item("%s  %s" % [row["name"], stamp])
		list.set_item_metadata(list.item_count - 1, row["name"])


func _selected_world() -> String:
	var list := _worlds_list()
	var picked := list.get_selected_items()
	if picked.is_empty():
		return ""
	return str(list.get_item_metadata(picked[0]))


func _world_status(text: String) -> void:
	var status := _worlds_panel().get_node("Margin/VBox/Status") as Label
	status.text = text


func _on_load_world_pressed() -> void:
	var save_name := _selected_world()
	if save_name == "":
		_world_status("Select a world")
		return
	var err := str(get_node("/root/MapGen").load_map_inputs(MapSave.path_for(save_name)))
	if err != "":
		_world_status(err)
		return
	get_node("/root/Flagoria").save_name = save_name
	_begin_host()


func _on_delete_world_pressed() -> void:
	if _selected_world() == "":
		_world_status("Select a world")
		return
	_on_rename_no_pressed()
	var panel := _worlds_panel()
	panel.get_node("Margin/VBox/Buttons").hide()
	panel.get_node("Margin/VBox/Confirm").show()
	_world_status("")


func _on_rename_world_pressed() -> void:
	var save_name := _selected_world()
	if save_name == "":
		_world_status("Select a world")
		return
	_on_delete_no_pressed()
	var panel := _worlds_panel()
	panel.get_node("Margin/VBox/Buttons").hide()
	var rename := panel.get_node("Margin/VBox/Rename")
	rename.show()
	var field := rename.get_node("Name") as LineEdit
	field.text = save_name
	field.grab_focus()
	_world_status("")


func _on_rename_yes_pressed(_new_text: String = "") -> void:
	var save_name := _selected_world()
	var rename := _worlds_panel().get_node("Margin/VBox/Rename")
	var field := rename.get_node("Name") as LineEdit
	var new_name := field.text
	var err := str(MapSave.rename_save(save_name, new_name) if save_name != "" else "Select a world")
	if err != "":
		_world_status(err)
		return
	var clean := new_name.strip_edges().validate_filename()
	_on_rename_no_pressed()
	_refresh_worlds()
	_select_world_named(clean)
	_world_status("")


func _on_rename_no_pressed() -> void:
	var panel := _worlds_panel()
	var rename := panel.get_node_or_null("Margin/VBox/Rename")
	if rename:
		rename.hide()
	panel.get_node("Margin/VBox/Buttons").show()


func _select_world_named(save_name: String) -> void:
	if save_name == "":
		return
	var list := _worlds_list()
	for i in list.item_count:
		if str(list.get_item_metadata(i)) == save_name:
			list.select(i)
			list.ensure_current_is_visible()
			return


func _on_delete_yes_pressed() -> void:
	var save_name := _selected_world()
	var err := str(MapSave.delete_save(save_name) if save_name != "" else "Select a world")
	_on_delete_no_pressed()
	_refresh_worlds()
	_world_status("" if err == "" else err)


func _on_delete_no_pressed() -> void:
	var panel := _worlds_panel()
	panel.get_node("Margin/VBox/Confirm").hide()
	panel.get_node("Margin/VBox/Buttons").show()


func _on_worlds_back_pressed() -> void:
	_on_delete_no_pressed()
	_on_rename_no_pressed()
	_worlds_panel().hide()
	main_menu.show()


func _on_map_settings_pressed() -> void:
	main_menu.hide()
	if admin_panel == null:
		return
	# Panel may still be deferred-added on the very first frame.
	if not admin_panel.is_inside_tree():
		await admin_panel.ready
	admin_panel.load_from_params(get_node("/root/MapGen").params)
	admin_panel.show()


func _on_admin_closed() -> void:
	main_menu.show()


func show_join_failed(address: String) -> void:
	## Bring the main menu back after a join that never connected (#348).
	## Message copy is fixed in the issue: "Could not join <address>".
	_show_status("Could not join %s" % address)


func show_address_error(message: String) -> void:
	## A typed address that Join will not dial. Shown at once, with no
	## connection attempt. The address field is left as typed.
	_show_status(message)


func _show_status(message: String) -> void:
	if admin_panel:
		admin_panel.hide()
	ux_layer.hide()
	main_menu.show()
	join_status.text = message
	join_status.visible = true
	get_node("/root/MusicPlayer").play(get_node("/root/MusicPlayer").MENU_TRACK)

