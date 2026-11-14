class_name FootprintOrientation
extends RefCounted
## Rotated facing marker for footprint placements (#493). The wooden tower
## tiles read the same at 90° and 270°, so play uses a small sprite rotated
## with quarter turns clockwise at the anchor (preview draw and placed nodes).

const MARKER := preload("res://art/ui/map/ui_map_marker_hero_up.png")
const LAYER_NAME := "FootprintOrientationMarkers"
const MARKER_SCALE := 0.55

const _WorldMap := preload("res://Scripts/TileMap.gd")


static func angle_rad(quarter_turns: int) -> float:
	return -posmod(quarter_turns, 4) * TAU / 4.0


static func layer_for(map: _WorldMap) -> Node2D:
	var world: Node = map.get_parent()
	var node := world.get_node_or_null(LAYER_NAME) as Node2D
	if node == null:
		node = Node2D.new()
		node.name = LAYER_NAME
		node.z_index = 4
		world.add_child(node)
	return node


static func draw_at(ci: CanvasItem, local_center: Vector2, quarter_turns: int) -> void:
	## Preview marker in interaction local space.
	var half := MARKER.get_size() * MARKER_SCALE * 0.5
	ci.draw_set_transform(local_center, angle_rad(quarter_turns), Vector2.ONE * MARKER_SCALE)
	ci.draw_texture(MARKER, -half)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func sync_sprite(map: _WorldMap, markers: Dictionary, id: int, anchor: Vector2i,
		quarter_turns: int) -> void:
	var sprite := markers.get(id) as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "facing_%d" % id
		sprite.texture = MARKER
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE * MARKER_SCALE
		layer_for(map).add_child(sprite)
		markers[id] = sprite
	sprite.global_position = map.to_global(map.map_to_local(anchor))
	sprite.rotation = angle_rad(quarter_turns)


static func clear_sprites(markers: Dictionary) -> void:
	for id in markers:
		var node: Node = markers[id]
		if is_instance_valid(node):
			node.queue_free()
	markers.clear()