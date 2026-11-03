extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## Host half of the two-launch Host/Join drive (see features/two-player-host-join.md).
## Clicks Host, waits for a second player under World, prints the players and
## seeds, and stays up a few seconds so the client can finish its own checks.
## It lives in drives/two_player/, outside the drives/*.gd glob that
## verify-drive.yml runs one by one, because alone it waits for a client and fails.
## Start it first: `bin/launch.sh drives/two_player/two_player_host.gd`, then the client.

const JOIN_TIMEOUT_S := 60.0
const LINGER_S := 5.0


func run() -> void:
	if not await start_game():
		return
	step("wait-for-client")
	var joined := await wait_until(func() -> bool: return players().size() >= 2, JOIN_TIMEOUT_S)
	print_world("host")
	await create_timer(LINGER_S).timeout
	done(joined)


## Names of the player nodes under World: each is its peer id.
func players() -> Array:
	var names := []
	for child in current_scene.get_node("World").get_children():
		if str(child.name).is_valid_int():
			names.append(str(child.name))
	names.sort()
	return names


func print_world(who: String) -> void:
	var p: MapGenParams = current_scene.world_params
	var seeds := "none" if p == null else "%d,%d,%d,%d" % [p.altitude_seed, p.moisture_seed, p.temperature_seed, p.items_seed]
	print("two_player: %s players=%s seeds=%s" % [who, ",".join(players()), seeds])
