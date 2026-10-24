class_name MobCatalog
extends RefCounted
## Mob types and the frame layout their sheets share.
##
## Each type names one sheet path and nothing else about its art: the frame
## table below is the same for every mob, so a recoloured sheet is a file swap
## (same PNG name, or a new path here). See art/mobs/README.md.

const SLIME := "slime"
const CRAB := "crab"
const PIGLET := "piglet"

## Where a mob type may stand and walk.
const HOME_GRASS := 0
const HOME_SAND := 1

## sheet: the type's only art reference. home: HOME_GRASS or HOME_SAND.
## wander_speed, chase_speed: px/s. body: feet box in px (w, h).
## hp: sword hits to kill. hurtbox: px (w, h), centred HURTBOX_Y above the feet.
const TYPES := {
	SLIME: {"sheet": "res://art/mobs/mob_slime_sheet.png", "home": HOME_GRASS, "wander_speed": 16.0, "chase_speed": 40.0, "body": Vector2(10, 6), "hp": 2, "hurtbox": Vector2(12, 9)},
	CRAB: {"sheet": "res://art/mobs/mob_crab_sheet.png", "home": HOME_SAND, "wander_speed": 20.0, "chase_speed": 44.0, "body": Vector2(12, 6), "hp": 3, "hurtbox": Vector2(14, 10)},
	PIGLET: {"sheet": "res://art/mobs/mob_piglet_sheet.png", "home": HOME_GRASS, "wander_speed": 24.0, "chase_speed": 52.0, "body": Vector2(8, 6), "hp": 2, "hurtbox": Vector2(12, 10)},
}

const HURTBOX_Y := -4.0

## Death puff shared by every type: one row of 16x16 frames.
const PUFF_SHEET := "res://art/mobs/fx_puff.png"
const PUFF_FRAMES := 4
const PUFF_FPS := 10.0

## Sheet grid: 8 columns x 16 rows of 16x16, like the hero sheet.
const SHEET_COLS := 8
const SHEET_ROWS := 16
const FRAME_SIZE := 16

## Facing = row offset inside each 4-row animation block.
const DOWN := 0
const LEFT := 1
const RIGHT := 2
const UP := 3
const FACING_VECTORS := [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]

## First row, frame count and fps of each animation block.
const ANIMS := {
	"walk": {"row": 0, "frames": 4, "fps": 5.0},
	"attack": {"row": 4, "frames": 4, "fps": 5.0},
	"idle": {"row": 8, "frames": 2, "fps": 2.5},
	"hurt": {"row": 12, "frames": 2, "fps": 10.0},
}


static func names() -> Array:
	return TYPES.keys()


static func stat(type: String, key: String) -> Variant:
	return TYPES[type][key]


static func sheet(type: String) -> Texture2D:
	## Loaded by path at runtime, so replacing the file needs no code change.
	return load(TYPES[type]["sheet"])


static func frame(anim: String, facing: int, time: float) -> Vector2i:
	## Sheet cell (col, row) for `anim` facing `facing`, `time` seconds in. Loops.
	var a: Dictionary = ANIMS[anim]
	var col := int(floor(time * float(a["fps"]))) % int(a["frames"])
	return Vector2i(col, int(a["row"]) + clampi(facing, DOWN, UP))


static func facing_for(direction: Vector2) -> int:
	## Sheet facing for a movement direction; horizontal wins on diagonals.
	if direction == Vector2.ZERO:
		return DOWN
	if absf(direction.x) >= absf(direction.y):
		return LEFT if direction.x < 0.0 else RIGHT
	return UP if direction.y < 0.0 else DOWN
