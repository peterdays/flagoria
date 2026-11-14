extends Node2D
## Debug layout: every BuildingBlockPiece with its tile and N/E/S/W socket labels.

const CELL := 96
const GRID_COLS := 4
const TILE_SIZE := 16


func _ready() -> void:
	_build()
	position = Vector2(12, 12)


func _build() -> void:
	var pieces: Array[BuildingBlockPiece] = BuildingBlockCatalog.all()
	var atlas_tex: Texture2D = load("res://art/flagoria/flagoria_tiles_v4.png")
	for i in pieces.size():
		var piece: BuildingBlockPiece = pieces[i]
		var col := i % GRID_COLS
		var row := i / GRID_COLS
		var origin := Vector2(col * CELL, row * CELL)
		var block := Node2D.new()
		block.name = piece.id
		block.position = origin
		add_child(block)
		if piece.tile_name != "" and TileCatalog.TILES.has(piece.tile_name):
			var atlas: Vector2i = TileCatalog.TILES[piece.tile_name]["atlas"]
			var sprite := Sprite2D.new()
			sprite.texture = atlas_tex
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(atlas.x * TILE_SIZE, atlas.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			sprite.position = Vector2(CELL * 0.5 - TILE_SIZE * 0.5, CELL * 0.5 - TILE_SIZE * 0.5)
			block.add_child(sprite)
		else:
			var placeholder := ColorRect.new()
			placeholder.color = Color(0.15, 0.15, 0.18, 1)
			placeholder.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
			placeholder.position = Vector2(CELL * 0.5 - TILE_SIZE, CELL * 0.5 - TILE_SIZE)
			block.add_child(placeholder)
		_add_socket_labels(block, piece)


func _add_socket_labels(block: Node2D, piece: BuildingBlockPiece) -> void:
	var cx := CELL * 0.5
	var cy := CELL * 0.5
	var offsets := {
		"N": Vector2(cx, 6),
		"E": Vector2(CELL - 6, cy),
		"S": Vector2(cx, CELL - 6),
		"W": Vector2(6, cy),
	}
	var anchors := {
		"N": Vector2(0.5, 0.0),
		"E": Vector2(1.0, 0.5),
		"S": Vector2(0.5, 1.0),
		"W": Vector2(0.0, 0.5),
	}
	for side: String in BuildingBlockCatalog.SIDES:
		var label := Label.new()
		label.text = piece.socket(side)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 9)
		label.modulate = Color(1, 0.95, 0.55, 1)
		label.position = offsets[side]
		label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		label.size = Vector2(44, 14)
		label.pivot_offset = label.size * anchors[side]
		label.position -= label.size * anchors[side]
		block.add_child(label)
	var title := Label.new()
	title.text = piece.id
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(cx - 40, CELL - 18)
	title.size = Vector2(80, 16)
	title.add_theme_font_size_override("font_size", 10)
	block.add_child(title)