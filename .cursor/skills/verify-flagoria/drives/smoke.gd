extends "res://.cursor/skills/verify-flagoria/bin/drive_base.gd"
## Sample drive: start a game, walk right for 30 frames, check the hero moved.
## Start it with `bin/launch.sh drives/smoke.gd`.

const WALK_FRAMES := 30
## Moved at least this far, in px. On a random map the hero may meet a tree or
## water a few px to the right, so this only tells walking from standing still.
const MIN_MOVED := 1.0


func run() -> void:
	if not await start_game():
		return
	var start := hero().position
	step("walk")
	await hold("ui_right", WALK_FRAMES)
	var moved := hero().position.distance_to(start)
	print("smoke: hero moved %.1f px" % moved)
	done(moved >= MIN_MOVED)
