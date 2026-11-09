extends RefCounted
## Attack-button aim for a chop. The finger is measured from the button's
## centre. Past Interaction.DRAG_START the offset is the cone: its angle is
## the direction and its world length, clamped to CHOP_REACH, is the reach.
## A shorter press chops in the facing direction at full reach. A second
## finger cancels. The map is not a chop target.


var touch := -1
var dragging := false
var start := Vector2.ZERO
var end := Vector2.ZERO


func cancel() -> void:
	touch = -1
	dragging = false


func handle(host, event: InputEvent) -> void:
	if host.mode != Interaction.Mode.INTERACT or host.build.tool != BuildPlacement.Tool.CUT \
			or host.player == null or Interaction.player_dead(host.player):
		if touch != -1:
			cancel()
		return
	if event is InputEventScreenTouch:
		_touch(host, event)
	elif event is InputEventScreenDrag and event.index == touch:
		end = event.position
		if start.distance_to(end) > Interaction.DRAG_START:
			dragging = true


func _touch(host, event: InputEventScreenTouch) -> void:
	if event.pressed:
		if touch != -1 and event.index != touch:
			cancel()
			return
		if touch == -1 and _on_button(host, event.position):
			var button = _button(host)
			touch = event.index
			start = button.aim_center()
			end = event.position
			dragging = start.distance_to(end) > Interaction.DRAG_START
		return
	if event.index != touch:
		return
	end = event.position
	if start.distance_to(end) > Interaction.DRAG_START:
		dragging = true
	if dragging:
		host._release_drag()
	else:
		host._release_tap()
	cancel()


func _on_button(host, pos: Vector2) -> bool:
	var button = _button(host)
	return button != null and button.is_visible_in_tree() and button.has_method("hits") and button.hits(pos)


func _button(host):
	return host.get_tree().get_first_node_in_group(AttackAim.ATTACK_BUTTON_GROUP)
