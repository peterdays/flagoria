class_name HudLayoutVisual
extends RefCounted
## Full on-screen rects for HUD layout overlap checks (joystick ring, attack art).


static func blocks_hud_actions() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var hl := tree.root.get_node_or_null("HudLayout")
	return hl != null and hl.blocks_hud_actions()


static func control_rect(id: String, layer: CanvasLayer, paths: Dictionary) -> Rect2:
	var node := layer.get_node_or_null(paths[id])
	if node == null:
		return Rect2()
	match id:
		"joystick":
			return _joystick_rect(node as Node2D)
		"attack":
			var atk := node as TouchScreenButton
			if atk.texture_normal != null:
				var sz: Vector2 = atk.texture_normal.get_size() * atk.global_scale
				return Rect2(atk.global_position - sz * 0.5, sz)
			return atk.get_global_rect()
		_:
			var ctrl := node as Control
			return ctrl.get_global_rect() if ctrl != null else Rect2()


static func dismiss_popups(layer: CanvasLayer) -> void:
	var panel := layer.get_node_or_null("MinimapPanel") as MinimapPanel
	if panel != null:
		panel.collapse_panel()
		if panel.parchment != null and panel.parchment.is_open():
			panel.parchment.hide_map()
	var map_btn := layer.get_node_or_null("MinimapButton") as BaseButton
	if map_btn != null:
		map_btn.set_pressed_no_signal(false)
	var buildings := layer.get_node_or_null("BuildingsButton") as BaseButton
	if buildings != null:
		buildings.set_pressed_no_signal(false)
	var picker := layer.get_node_or_null("BuildPicker") as CanvasItem
	if picker != null:
		picker.visible = false


static func _joystick_rect(stick: Node2D) -> Rect2:
	var ring := stick.get_node_or_null("joystick") as Sprite2D
	if ring != null and ring.texture != null:
		var sz: Vector2 = ring.texture.get_size() * stick.global_scale
		return Rect2(stick.global_position - sz * 0.5, sz)
	var r: float = stick.start_reach() if stick.has_method("start_reach") else 64.0
	return Rect2(stick.global_position - Vector2(r, r), Vector2(r, r) * 2.0)
