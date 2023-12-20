extends PanelContainer

@onready var main_menu = $"."
@onready var address_entry = $MarginContainer/VBoxContainer/AddressEntry
@onready var joystick = $/root/Flagoria/CanvasLayer1/player_joystick
@onready var healthbar = $/root/Flagoria/CanvasLayer1/TextureProgressBar

signal new_server_created
signal new_player_added
signal new_player_joined


func _unhandled_input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

# func _ready():
	#self.connect("new_server_created", get_node("../../worldMap"), update_world_seeds)
	#self.connect("new_server_created", $worldMap, update_world_seeds)

func _on_host_button_pressed():
	var world_seed = WorldSeeder.new()
	print("signal emitted")
	emit_signal("new_server_created", world_seed)
	main_menu.hide()
	joystick.show()
	healthbar.show()
	
	# adding the player
	emit_signal("new_player_added", multiplayer.get_unique_id())

func _on_join_button_pressed():
	main_menu.hide()
	joystick.show()
	healthbar.show()
	# adding the player (joined)
	emit_signal("new_player_joined")
