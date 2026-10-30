extends PanelContainer

@onready var main_menu = $"."
@onready var address_entry = $MarginContainer/VBoxContainer/AddressEntry
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
signal new_player_joined


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


func _on_host_button_pressed():
	get_node("/root/MapGen").save_to_disk()
	emit_signal("new_server_created", get_node("/root/MapGen").params.duplicate_params())
	main_menu.hide()
	if admin_panel:
		admin_panel.hide()
	ux_layer.show()
	get_node("/root/MusicPlayer").play(get_node("/root/MusicPlayer").GAME_TRACK)
	emit_signal("new_player_added", multiplayer.get_unique_id())


func _on_join_button_pressed():
	main_menu.hide()
	if admin_panel:
		admin_panel.hide()
	ux_layer.show()
	get_node("/root/MusicPlayer").play(get_node("/root/MusicPlayer").GAME_TRACK)
	emit_signal("new_player_joined")


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
