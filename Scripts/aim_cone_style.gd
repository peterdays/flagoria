class_name AimConeStyle
extends Resource
## How the attack aim cone looks (#231): every colour and size in one place.
## AttackAim draws with its `style`; swap the look by assigning another
## AimConeStyle (in code or as a saved .tres) without touching the aim logic.
## Defaults (Castle Stone UI set): a see-through dark fill that pulses, a
## light rim just inside a dark outline, both one screen pixel wide at any
## camera zoom, so the cone reads on sand, grass and water.

@export var range := 26.0  ## world px from tip to arc: the blade reaches ~21.5 px, plus half a mob's hurt box
@export var fill_color := Color("3d3a5c")  ## its alpha is replaced by the pulse below
@export var fill_alpha_min := 0.40  ## the pulse starts here, the faint end
@export var fill_alpha_max := 0.55
@export var pulse_period := 0.8  ## seconds per faint-strong-faint cycle; 0 holds the faint end
@export var rim_color := Color("ffffff")  ## just inside the outline, round the whole cone
@export var rim_width := 1.0  ## screen px
@export var outline_color := Color("2a2238")  ## on the cone's edge
@export var outline_width := 1.0  ## screen px


func fill_at(t: float) -> Color:
	## The fill `t` seconds after the aim started.
	var wave := 0.0
	if pulse_period > 0.0:
		wave = 0.5 - 0.5 * cos(TAU * t / pulse_period)
	return Color(fill_color, lerpf(fill_alpha_min, fill_alpha_max, wave))
