extends Node
## Autoload: per-device touch HUD positions and scales in user settings,
## separate from world saves. Empty means HudToolRow's default layout.
##
## Each control stores a normalized top-left (x, y in 0..1) and scale s
## (1.0 = today's size). Positions survive viewport resize and rotation.

const SECTION := "hud"
const SAVE_VERSION := 1
const SIDE := 4.0
const GAP := 2.0
const SCALE_MIN := 1.0
const SCALE_MAX := 1.75

const IDS := ["joystick", "attack", "run", "buildings", "map", "mode"]
const PATHS := {
	"joystick": "player_joystick",
	"attack": "TouchScreenButton",
	"run": "RunButton",
	"buildings": "BuildingsButton",
	"map": "MinimapButton",
	"mode": "ModeButton",
}

## Tests point this at a scratch file.
var save_path := "user://hud_layout.cfg"
var _saved: Dictionary = {}  ## id -> {x, y, s}
var _draft: Dictionary = {}  ## during edit; mirrors _saved until changed


func _ready() -> void:
	load_from_disk()


func uses_custom() -> bool:
	return not _saved.is_empty()


var _editing := false


func editing() -> bool:
	return _editing


func edit_begin(layer: CanvasLayer) -> void:
	_editing = true
	_draft = _saved.duplicate(true)
	if _draft.is_empty():
		_draft = capture_from_layer(layer)


func edit_end() -> void:
	_editing = false
	_draft.clear()


func active_layout() -> Dictionary:
	if _editing:
		return _draft
	return _saved


func layout_active() -> bool:
	return uses_custom() or _editing


func get_entry(id: String) -> Dictionary:
	var src := active_layout()
	if src.has(id):
		return src[id].duplicate()
	return {}


func set_entry(id: String, entry: Dictionary) -> bool:
	if not IDS.has(id):
		return false
	var clean := _sanitize_entry(entry)
	if clean.is_empty():
		return false
	if _editing:
		_draft[id] = clean
	else:
		_saved[id] = clean
	return true


func try_place(id: String, x: float, y: float, s: float, layer: CanvasLayer) -> bool:
	## Move one control if it fits on screen and does not overlap others.
	s = clampf(s, SCALE_MIN, SCALE_MAX)
	var view := layer.get_viewport().get_visible_rect().size
	var size := _hit_size(id, s, layer)
	if size == Vector2.ZERO:
		return false
	var pos := Vector2(x * view.x, y * view.y)
	var rect := Rect2(pos, size)
	rect = clamp_rect(rect, layer)
	return entry_write(id, _entry_from_rect(id, rect, layer, s), layer)


func entry_write(id: String, entry: Dictionary, layer: CanvasLayer) -> bool:
	var rect := _rect_for_entry(id, entry, layer)
	if rect.size == Vector2.ZERO:
		return false
	rect = clamp_rect(rect, layer)
	if overlaps(id, rect, layer):
		return false
	if _editing:
		_draft[id] = _entry_from_rect(id, rect, layer, float(entry.get("s", 1.0)))
	else:
		_saved[id] = _entry_from_rect(id, rect, layer, float(entry.get("s", 1.0)))
	apply_control(id, layer)
	_place_build_column(layer)
	return true


func save_to_disk() -> void:
	if _editing:
		_saved = _draft.duplicate(true)
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "version", SAVE_VERSION)
	for id in IDS:
		if _saved.has(id):
			var e: Dictionary = _saved[id]
			cfg.set_value(SECTION, id + "_x", e.get("x", 0.0))
			cfg.set_value(SECTION, id + "_y", e.get("y", 0.0))
			cfg.set_value(SECTION, id + "_s", e.get("s", 1.0))
	cfg.save(save_path)
	_draft = _saved.duplicate(true)


func load_from_disk() -> void:
	_saved.clear()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	if int(cfg.get_value(SECTION, "version", 0)) != SAVE_VERSION:
		return
	for id in IDS:
		var xv: Variant = _finite(cfg.get_value(SECTION, id + "_x"))
		var yv: Variant = _finite(cfg.get_value(SECTION, id + "_y"))
		var sv: Variant = _finite(cfg.get_value(SECTION, id + "_s"), 1.0)
		if xv == null or yv == null or sv == null:
			continue
		var x: float = xv
		var y: float = yv
		var s: float = sv
		s = clampf(s, SCALE_MIN, SCALE_MAX)
		if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
			continue
		_saved[id] = {"x": x, "y": y, "s": s}


func reset() -> void:
	_saved.clear()
	_draft.clear()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


func reset_to_defaults() -> void:
	_saved.clear()
	_draft.clear()
	_editing = false
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


func forget_memory() -> void:
	## Clears in-memory layout without touching the save file (tests).
	_saved.clear()
	_draft.clear()
	_editing = false


func capture_into_draft(layer: CanvasLayer) -> void:
	_draft = capture_from_layer(layer)
	_editing = true


func scale_of(id: String, layer: CanvasLayer) -> float:
	return _scale_of(id, layer)


func apply(layer: CanvasLayer) -> void:
	if not layout_active():
		return
	var src := active_layout()
	for id in IDS:
		if src.has(id):
			apply_control(id, layer)
	_place_build_column(layer)
	# Minimap panel still hugs the arc.
	var row := layer.get_node_or_null("HudToolRow") as HudToolRow
	if row != null:
		row.place_panel_only(layer)


func apply_control(id: String, layer: CanvasLayer) -> void:
	var src := active_layout()
	if not src.has(id):
		return
	var node := layer.get_node_or_null(PATHS[id])
	if node == null:
		return
	var entry: Dictionary = src[id]
	var s: float = clampf(float(entry.get("s", 1.0)), SCALE_MIN, SCALE_MAX)
	var view := layer.get_viewport().get_visible_rect().size
	var pos := Vector2(float(entry.get("x", 0.0)) * view.x, float(entry.get("y", 0.0)) * view.y)
	match id:
		"joystick":
			_apply_joystick(node as Node2D, pos, s)
		"attack":
			_apply_attack(node as TouchScreenButton, pos, s)
		"run":
			_apply_run(node as Button, pos, s)
		_:
			_apply_round(node as Button, pos, s)


func overlaps(id: String, rect: Rect2, layer: CanvasLayer, margin := 0.0) -> bool:
	var grow := rect.grow(margin)
	var layout := active_layout()
	for other in IDS:
		if other == id:
			continue
		var orc := Rect2()
		if layout.has(other):
			orc = _rect_for_entry(other, layout[other], layer)
		else:
			orc = control_hit_rect(other, layer)
		if orc.size != Vector2.ZERO and grow.intersects(orc):
			return true
	return false


func clamp_rect(rect: Rect2, layer: CanvasLayer) -> Rect2:
	var view := layer.get_viewport().get_visible_rect()
	var out := rect
	if out.position.x < SIDE:
		out.position.x = SIDE
	if out.position.y < SIDE:
		out.position.y = SIDE
	if out.end.x > view.size.x - SIDE:
		out.position.x = view.size.x - SIDE - out.size.x
	if out.end.y > view.size.y - SIDE:
		out.position.y = view.size.y - SIDE - out.size.y
	return out


func control_hit_rect(id: String, layer: CanvasLayer) -> Rect2:
	var node := layer.get_node_or_null(PATHS[id])
	if node == null:
		return Rect2()
	match id:
		"joystick":
			var stick := node as Node2D
			var r: float = stick.start_reach()
			return Rect2(stick.global_position - Vector2(r, r), Vector2(r, r) * 2.0)
		"attack":
			var btn := node as TouchScreenButton
			var size := btn.texture_normal.get_size() * btn.scale if btn.texture_normal else Vector2.ZERO
			return Rect2(btn.global_position, size)
		_:
			var c := node as Control
			return c.get_global_rect() if c != null else Rect2()


func _rect_for_entry(id: String, entry: Dictionary, layer: CanvasLayer) -> Rect2:
	var view := layer.get_viewport().get_visible_rect().size
	var s: float = clampf(float(entry.get("s", 1.0)), SCALE_MIN, SCALE_MAX)
	var size := _hit_size(id, s, layer)
	var pos := Vector2(float(entry.get("x", 0.0)) * view.x, float(entry.get("y", 0.0)) * view.y)
	return Rect2(pos, size)


func _hit_size(id: String, s: float, layer: CanvasLayer) -> Vector2:
	match id:
		"joystick":
			var stick := layer.get_node_or_null("player_joystick")
			if stick == null or not stick.has_method("start_reach"):
				return Vector2.ZERO
			var old: Vector2 = stick.scale
			stick.scale = Vector2.ONE * s
			var r: float = stick.start_reach()
			stick.scale = old
			return Vector2(r, r) * 2.0
		"attack":
			var btn := layer.get_node_or_null(PATHS[id]) as TouchScreenButton
			if btn == null or btn.texture_normal == null:
				return Vector2.ZERO
			return btn.texture_normal.get_size() * s
		"run":
			return Vector2(RoundHudStyle.RUN_HIT, RoundHudStyle.RUN_HIT) * s
		_:
			return Vector2(RoundHudStyle.HIT, RoundHudStyle.HIT) * s
	return Vector2.ZERO


func _entry_from_rect(id: String, rect: Rect2, layer: CanvasLayer, s: float) -> Dictionary:
	var view := layer.get_viewport().get_visible_rect().size
	return {
		"x": rect.position.x / view.x if view.x > 0.0 else 0.0,
		"y": rect.position.y / view.y if view.y > 0.0 else 0.0,
		"s": clampf(s, SCALE_MIN, SCALE_MAX),
	}


func _place_build_column(layer: CanvasLayer) -> void:
	var buildings := layer.get_node_or_null("BuildingsButton") as Control
	var picker := layer.get_node_or_null("BuildPicker") as Control
	if buildings == null or picker == null:
		return
	_pin(buildings)
	picker.position = Vector2.ZERO
	picker.z_index = 2
	var view := layer.get_viewport().get_visible_rect().size
	var bsize := _control_size(buildings)
	var below := buildings.position.y + bsize.y + GAP
	var column_h := 0.0
	for child in picker.get_children():
		var button := child as Control
		if button == null or button.is_queued_for_deletion() or not button.visible:
			continue
		column_h += _control_size(button).y + GAP
	var place_below := below + column_h <= view.y - SIDE
	var x := buildings.position.x
	var y := below if place_below else buildings.position.y - GAP - column_h
	for child in picker.get_children():
		var button := child as Control
		if button == null or button.is_queued_for_deletion() or not button.visible:
			continue
		_pin(button)
		var size := _control_size(button)
		button.position = Vector2(roundf(x), roundf(y))
		button.z_index = 3
		y += size.y + GAP if place_below else -(size.y + GAP)


func _apply_joystick(stick: Node2D, pos: Vector2, s: float) -> void:
	stick.scale = Vector2.ONE * s
	var reach: float = stick.start_reach()
	stick.position = pos + Vector2(reach, reach)


func _apply_attack(btn: TouchScreenButton, pos: Vector2, s: float) -> void:
	btn.scale = Vector2.ONE * s
	btn.position = pos
	if btn.shape is CircleShape2D:
		(btn.shape as CircleShape2D).radius = 24.0 * s


func _apply_run(button: Button, pos: Vector2, s: float) -> void:
	var hit := RoundHudStyle.RUN_HIT * s
	var disc := RoundHudStyle.RUN_SIZE * s
	RoundHudStyle.apply(button, hit, disc, RoundHudStyle.RUN_ICON)
	button.position = pos


func _apply_round(button: Button, pos: Vector2, s: float, _is_run := false) -> void:
	var hit := RoundHudStyle.HIT * s
	var disc := RoundHudStyle.SIZE * s
	var icon := RoundHudStyle.ICON
	if button.get_script() != null and str(button.get_script().resource_path).ends_with("run_control.gd"):
		hit = RoundHudStyle.RUN_HIT * s
		disc = RoundHudStyle.RUN_SIZE * s
		icon = RoundHudStyle.RUN_ICON
	RoundHudStyle.apply(button, hit, disc, icon)
	button.position = pos


static func _pin(control: Control) -> void:
	if control.has_meta(&"hud_pinned"):
		return
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.set_meta(&"hud_pinned", true)


static func _control_size(control: Control) -> Vector2:
	var need := control.get_combined_minimum_size()
	return Vector2(maxf(control.size.x, need.x), maxf(control.size.y, need.y))


static func _sanitize_entry(entry: Dictionary) -> Dictionary:
	var xv: Variant = _finite(entry.get("x"))
	var yv: Variant = _finite(entry.get("y"))
	var sv: Variant = _finite(entry.get("s"), 1.0)
	if xv == null or yv == null or sv == null:
		return {}
	var x: float = clampf(xv, 0.0, 1.0)
	var y: float = clampf(yv, 0.0, 1.0)
	var s: float = clampf(sv, SCALE_MIN, SCALE_MAX)
	return {"x": x, "y": y, "s": s}


static func _finite(value: Variant, fallback = null):
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var v := float(value)
	if is_nan(v) or is_inf(v):
		return fallback
	return v


## Capture the default layout after HudToolRow runs (for tests and first save).
func capture_from_layer(layer: CanvasLayer) -> Dictionary:
	var out := {}
	var view := layer.get_viewport().get_visible_rect().size
	for id in IDS:
		var rect := control_hit_rect(id, layer)
		if rect.size == Vector2.ZERO:
			continue
		var s := _scale_of(id, layer)
		out[id] = {
			"x": rect.position.x / view.x,
			"y": rect.position.y / view.y,
			"s": s,
		}
	return out


func _scale_of(id: String, layer: CanvasLayer) -> float:
	var node := layer.get_node_or_null(PATHS[id])
	if node == null:
		return 1.0
	match id:
		"joystick":
			return (node as Node2D).scale.x
		"attack":
			return (node as TouchScreenButton).scale.x
		_:
			var c := node as Control
			if c == null or c.size.x <= 0.0:
				return 1.0
			if id == "run":
				return c.size.x / RoundHudStyle.RUN_HIT
			return c.size.x / RoundHudStyle.HIT
	return 1.0
