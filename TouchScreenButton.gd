extends TouchScreenButton


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_pressed():
	var current_player_id = str(multiplayer.get_unique_id())

	var curr_player = get_node_or_null("/root/Flagoria/World/" + str(current_player_id))
	if curr_player:		
		curr_player.attack_animation()
