extends "res://.cursor/skills/verify-flagoria/drives/two_player/two_player_host.gd"
## Client half of the two-launch Host/Join drive. Start it a few seconds after
## drives/two_player/two_player_host.gd: it leaves the address empty (localhost), clicks
## Join, and waits for both players and the host's map params.

const JOIN_BUTTON := "CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinButton"


func run() -> void:
	if change_scene_to_file(MAIN) != OK:
		_fail("cannot load " + MAIN)
		return
	if not await wait_until(func() -> bool:
			return current_scene != null and current_scene.has_node(JOIN_BUTTON), START_TIMEOUT_S):
		_fail("no " + JOIN_BUTTON)
		return
	print("VERIFY_READY pid=%d scene=%s" % [OS.get_process_id(), MAIN])
	step("join")
	await click(JOIN_BUTTON)
	var joined := await wait_until(func() -> bool:
			return players().size() >= 2 and current_scene.world_params != null, JOIN_TIMEOUT_S)
	print_world("client")
	done(joined)
