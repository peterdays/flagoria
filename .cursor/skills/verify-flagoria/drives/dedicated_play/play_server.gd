extends "res://.cursor/skills/verify-flagoria/drives/dedicated_play/play_common.gd"
## launch: --seed 5
## Dedicated server for the cut-and-hit pair. Start this first, with
## --seed 5, then play_client_b.gd, then play_client_a.gd. It does not click
## Host and it does not spawn World/1. It stays up long enough for both
## clients to finish. verify-drive skips this folder.

const HOLD_S := 110.0


func run() -> void:
	if change_scene_to_file(MAIN) != OK:
		_fail("cannot load " + MAIN)
		return
	for _i in 3:
		await process_frame
	var main = current_scene
	if main.start_dedicated_server(PORT) != OK:
		_fail("could not listen on %d" % PORT)
		return
	print("VERIFY_READY pid=%d scene=%s" % [OS.get_process_id(), MAIN])
	step("listen")
	if main.get_node_or_null("World/1") != null:
		_fail("dedicated server spawned player 1")
		return
	await wait_until(func() -> bool: return false, HOLD_S)
	var ids := players()
	print("dedicated_play: server players=%s" % ",".join(ids))
	done(not ids.has("1"))
