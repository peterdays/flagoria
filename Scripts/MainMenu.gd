extends PanelContainer

@onready var main_menu = $"."
@onready var address_entry = $MarginContainer/VBoxContainer/AddressEntry
@onready var ux_layer = $/root/Flagoria/CanvasLayer1
@onready var music_volume: HSlider = $MarginContainer/VBoxContainer/MusicVolumeRow/MusicVolume
@onready var sfx_volume: HSlider = $MarginContainer/VBoxContainer/SFXVolumeRow/SFXVolume
@onready var music_value: Label = $MarginContainer/VBoxContainer/MusicVolumeRow/MusicValue
@onready var sfx_value: Label = $MarginContainer/VBoxContainer/SFXVolumeRow/SFXValue

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
	admin_panel = preload("res://map_admin_panel.tscn").instantiate()
	admin_panel.visible = false
	admin_panel.closed.connect(_on_admin_closed)
	admin_panel.start_host_requested.connect(_on_host_button_pressed)
	# Defer so we are not adding children while the parent CanvasLayer is still setting up.
	get_parent().call_deferred("add_child", admin_panel)


static func percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


func _unhandled_input(_event):
	if Input.is_action_just_pressed("quit"):
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
