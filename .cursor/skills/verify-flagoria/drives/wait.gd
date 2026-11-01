extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## The smallest drive: starts a game through the main menu, then stays up for
## an agent until bin/cleanup.sh stops it. Start it with
## `bin/launch.sh drives/wait.gd`.


func run() -> void:
	if await start_game():
		await idle()
