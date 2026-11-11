extends CharacterBody2D

const MAX_SPEED = 130
const ACCEL = 120
const FRICTION = 95
## Top speed with the touch joystick, in px/s. The joystick has always moved
## the player at ACCEL * 0.5 = 60 px/s, under the keyboard's MAX_SPEED; kept
## as is because matching MAX_SPEED would change how touch play feels.
const JOYSTICK_MAX_SPEED = 60

var input = Vector2.ZERO

@onready var camera = $Camera2D
@onready var joystick = get_node_or_null(^"/root/Flagoria/CanvasLayer1/player_joystick")  # none when the hero runs outside the game scene, as in tests
@onready var animations = $AnimationPlayer
@onready var weapon = $weapon
@onready var combat_sfx: CombatSfx = $CombatSfx
@onready var health: PlayerHealth = $Health
@onready var sprite: Sprite2D = $Sprite2D
@onready var chop_sprite: Sprite2D = $ChopSprite
@onready var sword: Area2D = $weapon/sword
@onready var sword_shape: CollisionShape2D = $weapon/sword/CollisionShape2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

const HUD_PATH := "/root/Flagoria/CanvasLayer1/HeartsHud"
const SCORE_HUD_PATH := "/root/Flagoria/CanvasLayer1/ScoreHud"
const POINTS_PATH := "/root/Flagoria/Points"
const RESOURCE_HUD_PATH := "/root/Flagoria/CanvasLayer1/ResourceHud"
const INVENTORY_PATH := "/root/Flagoria/Inventory"
const INTERACTION_PATH := "/root/Flagoria/World/Interaction"
const MAP_PATH := "/root/Flagoria/World/worldMap"
## Walk frame is 16 px, centred on Sprite2D at (0, -8), so the body runs from
## the feet (this node's origin) up 16 px. Wall caps sit at z 2 through 5.
const BODY_RECT := Rect2(-8, -16, 16, 16)
const WALL_CAP_LAYER := 6
## The hero draws over a wall until about two thirds of the body is on it.
const WALL_COVER_FRACTION := 2.0 / 3.0
const MapZoom := preload("res://Scripts/map_zoom.gd")
const AttackAimScript := preload("res://Scripts/attack_aim.gd")
const SWORD_DAMAGE := 1  ## half-hearts per sword hit
const REGEN_AMOUNT := 1  ## half-hearts per regen_timer tick
const BLINK_PERIOD_MS := 100  ## invulnerability blink: this long shown, this long faded
const CHOP_ROWS := {"Down": 0, "Left": 1, "Right": 2, "Up": 3}  ## rows of the chop sheet

const RESPAWN_HOLD_MS := 1000  ## longest a copy waits for its owner to catch up with a respawn

## On copies the owner moves: the respawn spot to hold while the owner's
## synced position is still the one from before it saw the respawn.
var _respawn_hold := Vector2.INF
var _respawn_hold_until := 0
## The owner's health.respawn_count when it sent an update, synced with
## its position. A copy holds the spawn until this reaches the number the
## server gave the respawn, so it needs no baseline of its own.
var owner_respawns := 0
## Physics frames left with the body's collision off after a respawn moved
## it. The physics server moves a body to a new position only at its next
## step, so for one tick the bodies of players who also just respawned still
## stand where they died. Colliding then pushes the owner off the server's
## spot, or (taking a body's top for a floor) carries it along when that
## body jumps to its own spot (found in a multi-peer play-test).
var _respawn_ghost_ticks := 0

var lastAnimDirection: String = "Down"
## The walk facing this player last sent with updateAnimation; the owner sends
## a new one only when the facing changes, not every physics frame.
var _sent_walk_direction := ""
## The walk facing the owner last sent; replayed when an attack ends.
var _walk_direction := "Down"
var isAttacking: bool = false
## How far the current swing turns from its four-way animation to the exact
## aim angle (#231), about AttackAim.ORIGIN; 0 for a four-way swing.
var swing_turn := 0.0


func _ready():
	health.damaged.connect(_on_damaged)
	health.healed.connect(_on_healed)
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	health.health_changed.connect(_apply_dead_state.unbind(2))
	health.state_received.connect(_apply_dead_state.unbind(2))
	animations.mixer_applied.connect(_turn_swing)
	var sync := get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.synchronized.connect(_on_synchronized)
	if not is_multiplayer_authority(): return
	camera.make_current()
	# A peer that joins later gets the current walk facing on the next frame.
	multiplayer.peer_connected.connect(func(_id): _sent_walk_direction = "")
	var map_zoom := MapZoom.new()  # local camera only; zoom is never synced
	map_zoom.name = "MapZoom"
	camera.add_child(map_zoom)
	var aim := AttackAimScript.new()  # local mouse aim; only the attack is sent
	aim.name = "AttackAim"
	add_child(aim)
	var hud = get_node_or_null(HUD_PATH)
	if hud:
		hud.bind(health)
	var score_hud = get_node_or_null(SCORE_HUD_PATH)
	var points = get_node_or_null(POINTS_PATH)
	if score_hud and points:
		score_hud.bind(points, str(name).to_int())
	var resource_hud = get_node_or_null(RESOURCE_HUD_PATH)
	var inventory = get_node_or_null(INVENTORY_PATH)
	if resource_hud and inventory:
		resource_hud.bind(inventory)
	var interaction = get_node_or_null(INTERACTION_PATH)
	if interaction:
		interaction.bind(self)

var _wall_atlases: Dictionary = {}


func _process(_delta):
	# Hidden while dead; blinks while invulnerable after a hit or a respawn.
	sprite.visible = not health.is_dead() and not chop_sprite.visible
	var faded := health.is_invulnerable() and (Time.get_ticks_msec() / BLINK_PERIOD_MS) % 2 == 1
	sprite.modulate.a = 0.3 if faded else 1.0
	chop_sprite.modulate.a = sprite.modulate.a
	_apply_wall_draw()


func _apply_wall_draw() -> void:
	## Walls are z 1 and their caps are z 2 through 5, so a body that only
	## overlaps the face of a wall would lose its head. Stay above the caps
	## until most of the body is on a wall, then drop behind the wall layer.
	var map := get_node_or_null(MAP_PATH) as TileMap
	if map == null:
		z_index = 0
		return
	var cover := _wall_cover(map)
	# No wall contact keeps the old order (trees stay above the hero). A
	# graze lifts the hero over the wall. Most of the body on the wall drops
	# the hero behind it again.
	if cover <= 0.0 or cover >= WALL_COVER_FRACTION:
		z_index = 0
	else:
		z_index = map.get_layer_z_index(WALL_CAP_LAYER) + 1


func _wall_cover(map: TileMap) -> float:
	## Share of the body rect that lies on a wall tile. 0 when clear.
	var body := Rect2(global_position + BODY_RECT.position, BODY_RECT.size)
	var area := body.size.x * body.size.y
	if area <= 0.0:
		return 0.0
	var covered := 0.0
	var top_left := map.local_to_map(map.to_local(body.position))
	var bottom_right := map.local_to_map(map.to_local(body.end - Vector2(0.01, 0.01)))
	for y in range(mini(top_left.y, bottom_right.y), maxi(top_left.y, bottom_right.y) + 1):
		for x in range(mini(top_left.x, bottom_right.x), maxi(top_left.x, bottom_right.x) + 1):
			var cell := Vector2i(x, y)
			if not _is_wall(map, cell):
				continue
			var center := map.to_global(map.map_to_local(cell))
			var tile := Vector2(map.tile_set.tile_size)
			var wall := Rect2(center - tile * 0.5, tile)
			var hit := body.intersection(wall)
			if hit.size.x > 0.0 and hit.size.y > 0.0:
				covered += hit.size.x * hit.size.y
	return covered / area


func _is_wall(map: TileMap, cell: Vector2i) -> bool:
	if map.get_cell_source_id(1, cell) == -1:
		return false
	_ensure_wall_atlases()
	return _wall_atlases.has(map.get_cell_atlas_coords(1, cell))


func _ensure_wall_atlases() -> void:
	if not _wall_atlases.is_empty():
		return
	for tile_name: String in TileCatalog.TILES:
		if not tile_name.begins_with("WALL_") and not tile_name.begins_with("PALISADE_") \
				and not tile_name.begins_with("TOWER_STONE_"):
			continue
		_wall_atlases[TileCatalog.TILES[tile_name]["atlas"]] = true

func set_chop_pose(direction: String, col: int) -> void:
	## Interaction's chop (local only): show chop sheet column `col` facing
	## `direction` in place of the walk sprite, or the walk sprite again for -1.
	chop_sprite.visible = col >= 0 and not health.is_dead()
	if col >= 0:
		lastAnimDirection = direction
		chop_sprite.frame_coords = Vector2i(col, CHOP_ROWS[direction])
	sprite.visible = not health.is_dead() and not chop_sprite.visible

func _physics_process(delta):
	if _respawn_ghost_ticks > 0:
		_respawn_ghost_ticks -= 1
		if _respawn_ghost_ticks == 0:
			_apply_dead_state()
	if not is_multiplayer_authority(): return
	if health.is_dead():
		velocity = Vector2.ZERO
		return
	if _map_covers_play():
		velocity = Vector2.ZERO
		return
	player_movement(delta)
	var direction := walk_direction()
	if direction != _sent_walk_direction:
		_sent_walk_direction = direction
		updateAnimation.rpc(direction)
	

func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	if health.is_dead(): return
	if _map_covers_play(): return
	
	if Input.is_action_just_pressed("attack"):
		attack_animation.rpc()

func attack_toward(direction: String, angle := NAN):
	## An aimed attack (AttackAim): swing toward `direction`, at `angle` when
	## given, on every peer.
	attack_animation.rpc(direction, angle)

@rpc("call_local")  # the call local calls in all remotes and the local too
func attack_animation(direction: String = "", angle: float = NAN):
	# `direction` is Up, Down, Left or Right from an aimed attack; anything
	# else, or none (Space, the touch button), swings in the facing direction.
	# `angle` (radians) is the exact aim: the swing plays `direction`'s
	# animation turned to it, and the sprite still faces `direction`. An angle
	# that is not finite or not within 45 degrees of `direction` is rejected:
	# the swing goes the facing direction, as for an unknown direction.
	# Every peer, the server included, checks and swings the same way, and
	# the server's copy still decides what the sword hits.
	swing_turn = 0.0
	if direction in AttackAimScript.DIRECTIONS:
		var turn := 0.0 if is_nan(angle) else AttackAimScript.turn_to(direction, angle)
		if not is_nan(turn):
			lastAnimDirection = direction
			swing_turn = turn
	animations.stop()
	combat_sfx.play_event("swing")
	animations.play("attack" + lastAnimDirection)
	isAttacking = true
	weapon.visible = true
	sword_shape.set_deferred("disabled", false)  # the sword only hits during a swing
	await animations.animation_finished
	weapon.visible = false
	sword_shape.set_deferred("disabled", true)
	isAttacking = false
	swing_turn = 0.0


func _turn_swing() -> void:
	## After each animation step: turn the swing's weapon about the aim
	## origin by swing_turn, so its hitbox follows the exact aim angle.
	if swing_turn == 0.0 or not str(animations.current_animation).begins_with("attack"):
		return
	var origin := AttackAimScript.ORIGIN
	weapon.position = origin + (weapon.position - origin).rotated(swing_turn)
	weapon.rotation += swing_turn


func _map_covers_play() -> bool:
	## The parchment full map is open: this hero does not move or attack.
	var node := get_tree().get_first_node_in_group(ParchmentMap.GROUP)
	return node != null and node.is_open()


func sword_active() -> bool:
	## True while this player's swing can hit: mid-attack and alive.
	return isAttacking and not health.is_dead()

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func get_input_axis():
	input.x = int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left"))
	input.y = int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up"))
	return input.normalized()

func get_joystick_axis() -> Vector2:
	## The touch joystick's direction while a finger holds it, read every
	## physics frame: the joystick only signals on touch and drag events, so a
	## finger held still sends nothing.
	if not is_instance_valid(joystick) or joystick.ongoing_drag == -1:
		return Vector2.ZERO
	return joystick.get_button_pos().normalized()

func _speed_scale() -> float:
	## Run button on this hero's HUD. Missing when a hero is built on its own,
	## which keeps the walk cap. Joystick direction is not part of this scale.
	var button := get_node_or_null(^"../../CanvasLayer1/RunButton")
	if button != null and button.has_method("speed_scale"):
		return float(button.speed_scale())
	return 1.0


func player_movement(delta):
	input = get_input_axis()
	var max_speed := MAX_SPEED
	if input == Vector2.ZERO:
		input = get_joystick_axis()
		if input != Vector2.ZERO:
			max_speed = JOYSTICK_MAX_SPEED
	var scale := _speed_scale()
	max_speed *= scale

	if input == Vector2.ZERO:  # no input
		if velocity.length() > (FRICTION * delta):
			# if we are moving we will slow down
			velocity -= velocity.normalized() * (FRICTION * delta)
		else:
			velocity = Vector2.ZERO
	else:  # moving the player
		velocity += (input * ACCEL * scale * delta)
		velocity = velocity.limit_length(max_speed)

	move_and_slide()

func walk_direction() -> String:
	## The walk animation's facing for the owner's current velocity.
	if velocity.x < 0: return "Left"
	if velocity.x > 0: return "Right"
	if velocity.y < 0: return "Up"
	return "Down"

@rpc("call_local")
func updateAnimation(direction: String):
	_walk_direction = direction
	if isAttacking: return

	lastAnimDirection = direction
	animations.play("walk" + direction)


func spawn_position() -> Vector2:
	## Where this player respawns: a free spot near the map's land spawn, as
	## on joining.
	var main = get_node_or_null("/root/Flagoria")
	if main and main.has_method("_land_spawn_position"):
		return main._land_spawn_position(self)
	return position


func _on_damaged(_amount: int):
	combat_sfx.play_event("hit")
	combat_sfx.play_event("hurt")


func _on_healed(_amount: int):
	# Regen only runs after damage, so this ticks only while recovering. Only
	# the peer that controls this player hears it.
	if is_multiplayer_authority():
		combat_sfx.play_event("regen")


func _on_died():
	combat_sfx.play_event("sting")


func _apply_dead_state():
	# Follows health state, however it arrived (a hit, set_health_now, a
	# respawn, or a late copy's state reply): a dead player neither blocks
	# movement nor hits until it respawns. The sprite hides in _process.
	var dead := health.is_dead()
	body_shape.set_deferred("disabled", dead or _respawn_ghost_ticks > 0)
	if dead:
		weapon.visible = false
		sword_shape.set_deferred("disabled", true)


func _on_respawned(at: Vector2):
	if is_multiplayer_authority():
		owner_respawns = health.respawn_count
	else:
		_respawn_hold = at
		_respawn_hold_until = Time.get_ticks_msec() + RESPAWN_HOLD_MS
	position = at
	velocity = Vector2.ZERO
	# On every peer: this body neither pushes nor is pushed until the
	# physics server has every respawned body at its new spot.
	_respawn_ghost_ticks = 1
	body_shape.set_deferred("disabled", true)


func _on_synchronized():
	# The owner keeps sending its pre-respawn position until the respawn
	# reaches it; keep the copy at the spawn until an update the owner sent
	# after it respawned (or the hold runs out), then follow again.
	if _respawn_hold == Vector2.INF:
		return
	if owner_respawns >= health.respawn_count or Time.get_ticks_msec() > _respawn_hold_until:
		_respawn_hold = Vector2.INF
	else:
		position = _respawn_hold

func _on_animation_player_animation_finished(anim_name):
	# An attack ended: back to the walk facing the owner last sent, which no
	# longer arrives every frame.
	lastAnimDirection = _walk_direction
	animations.play("walk" + _walk_direction)


func _on_regen_timer_timeout():
	health.heal(REGEN_AMOUNT)  # server only; full or dead players are skipped


func _on_hurt_box_area_entered(area):
	# An area never reports itself, and the hurtBox is on no layer anyway.
	var collision_player = area.get_parent().get_parent()
	if collision_player.name != name and collision_player.has_method("sword_active") and collision_player.sword_active():
		# A different player's sword, mid-swing. Every peer sees the overlap; only
		# the server's take_damage counts, and it syncs health and sounds to all.
		health.take_damage(SWORD_DAMAGE)
