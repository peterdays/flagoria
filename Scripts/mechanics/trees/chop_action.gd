class_name ChopAction
extends RefCounted
## One chop of a tree or bush, driven by Interaction: the hero faces the
## plant and swings its type's `hits` chops, each impact plays the type's hit
## sounds, hit sheet and fx, and FLASH_TIME after the last impact the plant
## becomes its stump through Interaction._cut, with its fall and pickup
## sounds, puff or fx. Sounds are local, on the SFX bus.
## Moved from Scripts/interaction.gd (#262); Interaction keeps wrappers with
## the same names.

## A chop's axe landed on `cell`; `hit` counts from 1 to the type's `hits`.
signal chop_hit(cell: Vector2i, hit: int)

## One chop, in s: wind-up 0.10, swing 0.04, impact 0.10, recover 0.08. Each
## entry ends a column of the hero's chop sheet. Chops chain with no idle.
const CHOP_FRAME_ENDS := [0.10, 0.14, 0.24, 0.32]
const CHOP_TIME := 0.32
const IMPACT_AT := 0.14  ## s into each chop when the axe lands and the hit counts
const FLASH_TIME := 0.10  ## s from the last impact until the plant becomes a stump
const HIT_FRAME_TIME := 0.05  ## s per frame of a type's hit_sheet and of fx_sheet frames 0-1
const FX_FELL_FRAMES := [[2, 0.15], [3, 0.25]]  ## fx_sheet [frame, s] once the plant falls
## Alternative tile of a choppable with a hit_sheet: invisible, same
## collision. Swapped in while the hit sheet draws in the tile's place.
const HIDDEN_ALT := 1
const MOVE_CANCEL := 2.0  ## world px the player can move from where a chop started

var chop_cell := Vector2i.ZERO  ## the plant being chopped
var chop_type: InteractableType  ## its type, set when the chop starts
var chop_time := -1.0  ## s since the chop's first wind-up, or -1 when not chopping
var chop_hits := 0
var _chop_from := Vector2.ZERO  ## player position when the chop started
var _chop_facing := "Down"
var _felled := false
var _puff: Sprite2D  ## the cloud over a tree that just fell
var _puff_time := -1.0
var _hit: Sprite2D  ## chop_type's hit_sheet, drawn in place of the hit tile
var _hit_time := -1.0
var _hidden_cell := Vector2i.ZERO  ## the cell showing HIDDEN_ALT while _hit plays
var _fx: Sprite2D  ## chop_type's fx_sheet over the cell
var _fx_time := -1.0
var _fx_fell := false  ## _fx plays the falling frames, not a hit
var _sfx: AudioStreamPlayer2D  ## hit_sounds and fell_sounds
var _sfx_layer: AudioStreamPlayer2D  ## hit_layer_sounds
var _sfx_last: AudioStreamPlayer2D  ## last_hit_sounds
var _sfx_pickup: AudioStreamPlayer2D  ## pickup_sounds
var _last_hit_sound: AudioStream  ## for InteractableType.hit_no_repeat
## Streams started by the chop, in order (tests read this; playback is not
## observable headless).
var sfx_log: Array[AudioStream] = []
var _i: Interaction


func _init(interaction: Interaction) -> void:
	_i = interaction


func setup() -> void:
	## Make the puff, hit and fx sprites and the sound player, as children of
	## the Interaction node (called from its _ready).
	_puff = Sprite2D.new()
	_puff.texture = load(MobCatalog.PUFF_SHEET)
	_puff.hframes = MobCatalog.PUFF_FRAMES
	_puff.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_puff.visible = false
	_i.add_child(_puff)
	_hit = _sheet_sprite()
	_hit.z_as_relative = false
	_hit.z_index = _i.world_map.get_layer_z_index(1)  # in the foliage tile's place
	_fx = _sheet_sprite()
	_sfx = _sound_player()
	_sfx_layer = _sound_player()
	_sfx_last = _sound_player()
	_sfx_pickup = _sound_player()


func chopping() -> bool:
	return chop_time >= 0.0


func start_chop(cell: Vector2i) -> bool:
	## Start chopping the tree or bush at `cell`; false while another chop
	## runs, or when there is nothing to chop in reach there.
	if chopping() or not _i.interact_allowed() or not _i.world_map.choppable(cell) or not _i.in_reach(cell):
		return false
	chop_cell = cell
	chop_type = _i.world_map.choppable(cell)
	chop_time = 0.0
	chop_hits = 0
	_felled = false
	_chop_from = _i.player.global_position
	var d := _i.cell_center(cell) - _i.player.global_position
	if absf(d.x) > absf(d.y):
		_chop_facing = "Left" if d.x < 0.0 else "Right"
	else:
		_chop_facing = "Up" if d.y < 0.0 else "Down"
	_pose()
	return true


static func fell_at(hits: int) -> float:
	## s from the first wind-up until a plant of `hits` hits falls (0.56 for 2).
	return (hits - 1) * CHOP_TIME + IMPACT_AT + FLASH_TIME


func step_chop(delta: float) -> void:
	## Advance the chop and its effects by `delta` s. Each chop's impact
	## counts a hit (with the type's hit sound, hit sheet and fx); fell_at
	## after the first wind-up the plant becomes its stump, plays its fall
	## effects and gives its yields, and the hero recovers until the last
	## chop ends. Moving away, leaving interact mode, the hero dying or
	## losing the plant before it falls cancels with no stump and no wood.
	_step_fx(delta)
	if not chopping():
		return
	if not _felled and (_i.mode != Interaction.Mode.INTERACT or _i.player == null or not _i.interact_allowed()
			or _i.player.global_position.distance_to(_chop_from) > MOVE_CANCEL
			or _i.world_map.choppable(chop_cell) != chop_type or _player_dead()):
		cancel_chop()
		return
	chop_time += delta
	while chop_hits < chop_type.hits and chop_time >= chop_hits * CHOP_TIME + IMPACT_AT:
		chop_hits += 1
		chop_hit.emit(chop_cell, chop_hits)
		_on_hit()
	if not _felled and chop_time >= fell_at(chop_type.hits):
		_felled = true
		if _i._cut(chop_cell):
			_on_fell()
	if chop_time >= chop_type.hits * CHOP_TIME:
		cancel_chop()
	else:
		_pose()


func cancel_chop() -> void:
	## Stop chopping and give the hero back the walk sprite.
	if not chopping():
		return
	chop_time = -1.0
	_end_hit()
	_pose()


func _player_dead() -> bool:
	var health := _i.player.get_node_or_null("Health") as PlayerHealth
	return health != null and health.is_dead()


func _play(streams: Array[AudioStream], player: AudioStreamPlayer2D = null, avoid: AudioStream = null) -> void:
	## One of `streams` at random on `player` (default _sfx), not `avoid`.
	if streams.is_empty():
		return
	if player == null:
		player = _sfx
	var pick := randi() % streams.size()
	if avoid != null and streams.size() > 1 and streams[pick] == avoid:
		pick = (pick + 1 + randi() % (streams.size() - 1)) % streams.size()
	player.stream = streams[pick]
	player.position = _i.to_local(_i.cell_center(chop_cell))
	player.pitch_scale = randf_range(0.93, 1.07)
	player.play()
	sfx_log.append(player.stream)


func _on_hit() -> void:
	## An impact on chop_cell: its hit sounds, hit sheet and hit fx.
	_play(chop_type.hit_sounds, _sfx, _last_hit_sound if chop_type.hit_no_repeat else null)
	_last_hit_sound = _sfx.stream
	_play(chop_type.hit_layer_sounds, _sfx_layer)
	if chop_hits == chop_type.hits:
		_play(chop_type.last_hit_sounds, _sfx_last)
	var corner := _i.to_local(_i.cell_center(chop_cell)) - Vector2(_i.world_map.tile_set.tile_size) / 2.0
	if chop_type.hit_sheet:
		_end_hit()
		_hidden_cell = chop_cell
		_i.world_map.set_cell(1, chop_cell, TileCatalog.SOURCE_ID, _i.world_map.get_cell_atlas_coords(1, chop_cell), HIDDEN_ALT)
		_hit.texture = chop_type.hit_sheet
		_hit.hframes = chop_type.hit_sheet.get_width() / chop_type.hit_sheet.get_height()
		_hit.frame = 0
		_hit.position = corner
		_hit.visible = true
		_hit_time = 0.0
	if chop_type.fx_sheet:
		_fx.texture = chop_type.fx_sheet
		_fx.hframes = 4
		_fx.frame = 0
		_fx.position = corner
		_fx.visible = true
		_fx_time = 0.0
		_fx_fell = false


func _on_fell() -> void:
	## chop_cell just became its stump and gave its yields: fall and pickup
	## sounds, puff or fx falling frames.
	_play(chop_type.fell_sounds)
	if not chop_type.yields.is_empty():
		_play(chop_type.pickup_sounds, _sfx_pickup)
	_end_hit()
	if chop_type.fell_puff:
		_puff.position = _i.to_local(_i.cell_center(chop_cell))
		_puff.frame = 0
		_puff.visible = true
		_puff_time = 0.0
	if chop_type.fx_sheet:
		_fx.frame = FX_FELL_FRAMES[0][0]
		_fx.visible = true
		_fx_time = 0.0
		_fx_fell = true


func _end_hit() -> void:
	## Stop the hit sheet and show the plant's own tile again, if it is still there.
	if _hit_time < 0.0:
		return
	_hit_time = -1.0
	_hit.visible = false
	if _i.world_map.get_cell_alternative_tile(1, _hidden_cell) == HIDDEN_ALT:
		_i.world_map.set_cell(1, _hidden_cell, TileCatalog.SOURCE_ID, _i.world_map.get_cell_atlas_coords(1, _hidden_cell))


func _step_fx(delta: float) -> void:
	if _puff_time >= 0.0:
		_puff_time += delta
		var frame := int(_puff_time * MobCatalog.PUFF_FPS)
		_puff.visible = frame < MobCatalog.PUFF_FRAMES
		_puff.frame = mini(frame, MobCatalog.PUFF_FRAMES - 1)
		if not _puff.visible:
			_puff_time = -1.0
	if _hit_time >= 0.0:
		_hit_time += delta
		var frame := int(_hit_time / HIT_FRAME_TIME)
		if frame >= _hit.hframes:
			_end_hit()
		else:
			_hit.frame = frame
	if _fx_time >= 0.0:
		_fx_time += delta
		var frame := -1
		if not _fx_fell:
			frame = int(_fx_time / HIT_FRAME_TIME) if _fx_time < 2 * HIT_FRAME_TIME else -1
		else:
			var t := _fx_time
			for step in FX_FELL_FRAMES:
				if t < step[1]:
					frame = step[0]
					break
				t -= step[1]
		_fx.visible = frame >= 0
		if frame >= 0:
			_fx.frame = frame
		else:
			_fx_time = -1.0


func _pose() -> void:
	if _i.player == null or not _i.player.has_method("set_chop_pose"):
		return
	var col := -1
	if chopping():
		var t := fmod(chop_time, CHOP_TIME)
		col = 0
		while col < CHOP_FRAME_ENDS.size() - 1 and t >= CHOP_FRAME_ENDS[col]:
			col += 1
	_i.player.set_chop_pose(_chop_facing, col)


func _sound_player() -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.bus = &"SFX"
	player.volume_db = -8.0
	_i.add_child(player)
	return player


func _sheet_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = false
	_i.add_child(sprite)
	return sprite
