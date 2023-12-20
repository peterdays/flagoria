extends TextureProgressBar

# Called when the node enters the scene tree for the first time.
func _ready():
	var current_player_id = str(multiplayer.get_unique_id())
	var curr_player = get_node_or_null("/root/Flagoria/World/" + str(current_player_id))
	if curr_player:
		curr_player.healthChanged.connect(update)
	update()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func update():
	var current_player_id = str(multiplayer.get_unique_id())
	var curr_player = get_node_or_null("/root/Flagoria/World/" + str(current_player_id))
	if curr_player:
		value = curr_player.currentHealth * 100 / curr_player.maxHealth
