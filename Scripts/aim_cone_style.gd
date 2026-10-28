class_name AimConeStyle
extends Resource
## How the attack aim cone looks (#231): every colour and size in one place.
## AttackAim draws with its `style`; swap the look by assigning another
## AimConeStyle (in code or as a saved .tres) without touching the aim logic.
## Defaults read on sand, grass and water: a bright fill, a bright rim along
## the arc and a dark outline round the whole cone.

@export var range := 26.0  ## world px from tip to arc: the blade reaches ~21.5 px, plus half a mob's hurt box
@export var fill_color := Color(1.0, 0.98, 0.9, 0.5)
@export var rim_color := Color(1.0, 1.0, 1.0, 0.95)  ## the arc edge, where the swing lands
@export var rim_width := 1.5
@export var outline_color := Color(0.12, 0.08, 0.16, 0.85)  ## dark edge so the cone reads on light ground
@export var outline_width := 1.0
