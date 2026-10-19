class_name Footsteps
extends AudioStreamPlayer2D
## Terrain footsteps for one player instance.
##
## Runs on every peer for every visible player: steps follow the player's
## (replicated) position, so no RPC is needed and each peer plays each
## player's steps exactly once. One player node, so steps never overlap.

## Pixels walked between steps.
const STEP_DISTANCE := 22.0
## A larger jump in one frame is a teleport (spawn placement), not walking.
const TELEPORT_DISTANCE := 48.0
const PITCH_MIN := 0.92
const PITCH_MAX := 1.08
const WORLD_MAP_PATH := "/root/Flagoria/World/worldMap"

const SOUNDS := {
	"grass": [
		preload("res://art/audio/sfx/footsteps/footstep_grass_01.wav"),
		preload("res://art/audio/sfx/footsteps/footstep_grass_02.wav"),
		preload("res://art/audio/sfx/footsteps/footstep_grass_03.wav"),
	],
	"sand": [
		preload("res://art/audio/sfx/footsteps/footstep_sand_01.wav"),
		preload("res://art/audio/sfx/footsteps/footstep_sand_02.wav"),
		preload("res://art/audio/sfx/footsteps/footstep_sand_03.wav"),
	],
	"swamp": [
		preload("res://art/audio/sfx/footsteps/footstep_swamp_01.wav"),
		preload("res://art/audio/sfx/footsteps/footstep_swamp_02.wav"),
		preload("res://art/audio/sfx/footsteps/footstep_swamp_03.wav"),
	],
}
const FALLBACK_SURFACE := "grass"

## TileCatalog name -> surface. Names not listed use FALLBACK_SURFACE.
const SURFACE_BY_TILE := {
	"SAND": "sand",
	"SWAMP": "swamp",
	"SWAMP_SPECIAL": "swamp",
	"GRASS_A": "grass",
	"GRASS_B": "grass",
	"GRASS_C": "grass",
	"GRASS_D": "grass",
}

## Steps started so far (tests read this; audio playback is not observable headless).
var steps_played := 0
var last_surface := ""
var _travelled := 0.0
var _last_pos := Vector2.ZERO
var _has_last_pos := false


func _ready() -> void:
	volume_db = -10.0
	max_polyphony = 1


func _physics_process(_delta: float) -> void:
	var body := get_parent() as Node2D
	if body != null:
		advance(body.global_position)


func advance(pos: Vector2) -> void:
	## Feed the player's position for this frame; plays a step every
	## STEP_DISTANCE pixels walked. No movement, no steps.
	if not _has_last_pos:
		_last_pos = pos
		_has_last_pos = true
		return
	var moved := pos.distance_to(_last_pos)
	_last_pos = pos
	if moved > TELEPORT_DISTANCE:
		_travelled = 0.0
		return
	_travelled += moved
	if _travelled < STEP_DISTANCE:
		return
	_travelled = 0.0
	if playing:
		return  # never restart or stack a step that is still sounding
	_play_step(surface_at(pos))


func _play_step(surface: String) -> void:
	var options: Array = SOUNDS.get(surface, SOUNDS[FALLBACK_SURFACE])
	stream = options[randi() % options.size()]
	pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	last_surface = surface
	steps_played += 1
	play()


func surface_at(pos: Vector2) -> String:
	var world := get_node_or_null(WORLD_MAP_PATH) as TileMap
	if world == null:
		return FALLBACK_SURFACE
	var cell := world.local_to_map(world.to_local(pos))
	return surface_for_atlas(world.get_cell_atlas_coords(0, cell))


static func surface_for_atlas(atlas: Vector2i) -> String:
	for tile_name in TileCatalog.TILES:
		if TileCatalog.TILES[tile_name]["atlas"] == atlas:
			return SURFACE_BY_TILE.get(tile_name, FALLBACK_SURFACE)
	return FALLBACK_SURFACE
