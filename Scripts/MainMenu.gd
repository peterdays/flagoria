extends PanelContainer

const Player = preload("res://character_body_2d.tscn")
@onready var main_menu = $"."
@onready var address_entry = $MarginContainer/VBoxContainer/AddressEntry

const PORT = 9999
var enet_peer = ENetMultiplayerPeer.new()

signal new_server_created

#func _unhandled_input(event):
#	if Input.is_action_just_pressed("quit"):
#		get_tree().quit()

func _ready():
	#self.connect("new_server_created", get_node("../../worldMap"), update_world_seeds)
	#self.connect("new_server_created", $worldMap, update_world_seeds)

func _on_host_button_pressed():
	main_menu.hide()
	# creating the server
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)

	# adding the player
	add_player(multiplayer.get_unique_id())
	var world_seed = WorldSeeder.new()
	print("signal emitted")
	emit_signal("new_server_created", world_seed)

func _on_join_button_pressed():
	main_menu.hide()
	# creating the server
	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer


func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	get_node("/root/World").add_child(player)

