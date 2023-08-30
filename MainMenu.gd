extends PanelContainer

const Player = preload("res://character_body_2d.tscn")
@onready var main_menu = $"."
@onready var address_entry = $MarginContainer/VBoxContainer/AddressEntry

const PORT = 9999
var enet_peer = ENetMultiplayerPeer.new()

func _unhandled_input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()


func _on_host_button_pressed():
	main_menu.hide()
	# creating the server
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)

	# adding the player
	add_player(multiplayer.get_unique_id())

func _on_join_button_pressed():
	main_menu.hide()
	# creating the server
	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer

func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
