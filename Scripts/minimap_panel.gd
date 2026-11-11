class_name MinimapPanel
extends Control
## Explored ground in the top-right wood panel. A save restores the chart.
## The panel starts closed; the round minimap button or M opens it (#450).
const FRAME := preload("res://art/ui/map/ui_map_panel_open.png")
const HERO := {
	"Up": preload("res://art/ui/map/ui_map_marker_hero_up.png"),
	"Right": preload("res://art/ui/map/ui_map_marker_hero_right.png"),
	"Down": preload("res://art/ui/map/ui_map_marker_hero_down.png"),
	"Left": preload("res://art/ui/map/ui_map_marker_hero_left.png"),
}
const MAP_ICON := preload("res://assets/ui/hud/icon_map.png")
const MARGIN := 4.0  ## art pixels from the right edge
const TOP := 28.0  ## art pixels from the top; the arc slides the panel to its left
const WINDOW := Rect2i(4, 16, 216, 124)  ## map window inside the frame
const CELL_PX := 2
const CHECK_FRAMES := 15  ## physics frames between reveals
const WORLD_PATH := "/root/Flagoria/World"
const HERO_ANCHOR := Vector2i(8, 8)  ## marker pixel that sits on the hero's cell

# Palette (cartoon v1.1).
const SKY := Color("7cc8f2")
const SKY_DEEP := Color("4a8fd6")
const THATCH := Color("e8c968")
const GRASS := Color("6fbf3a")
const GRASS_HI := Color("b6e04c")
const GRASS_DARK := Color("3f8a3c")
const LEAF_DEEP := Color("24604a")
const STONE := Color("8e97a3")
const GOLD := Color("f2b632")
const CLOUD := Color("ffffff")
const CLOUD_SHADE := Color("d9e6f2")
const INK := Color("2a2238")
const CITY_HOST := Color("3b70e0")
const CITY_MOBS := Color("9b54c4")
const CITY_NEUTRAL := Color("8c8c99")
const CITY_OTHER := Color("e04a4a")

## Terrain kinds kept per cell (stored + 1, 0 = not looked up yet).
enum Kind { WATER, SAND, SWAMP, PINE, TREE, BUSH, STONES, FLOWER, GRASS }
const _SHORE_KNOWN := 0x40
const _SHORE := 0x80
const _KIND_BITS := 0x0f
const _SIDES := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]

const _NEIGHBOURS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
		Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

var explored := ExploredMap.new()
var hero_cell := Vector2i.ZERO
var facing := "Down"
var shown := false  ## closed until the minimap button or M
var parchment: ParchmentMap
var _map_button: Button

var _textures := {}  ## chunk (Vector2i) -> ImageTexture
var _images := {}  ## chunk (Vector2i) -> Image behind its texture
var _terrain := {}  ## chunk (Vector2i) -> PackedByteArray, a Kind per cell, see _cell_info
var _frames := 0
var _last_sample := Vector2i.MAX  ## hero cell at the previous tick
var _view: Control
var _mist: ImageTexture


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP  # touches on the panel are HUD touches
	texture_filter = TEXTURE_FILTER_NEAREST
	size = Vector2(FRAME.get_size())
	_view = Control.new()
	_view.name = "MapView"
	_view.position = WINDOW.position
	_view.size = WINDOW.size
	_view.clip_contents = true
	_view.mouse_filter = MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_map)
	add_child(_view)
	var frame := TextureRect.new()
	frame.name = "Frame"
	frame.texture = FRAME
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(frame)
	_mist = ImageTexture.create_from_image(_mist_image())
	_add_header_buttons()
	var map := _map()
	if map:
		map.ground_changed.connect(_on_ground_changed)
	get_viewport().size_changed.connect(_fit_pixel_scale)
	_fit_pixel_scale()


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames % CHECK_FRAMES == 0:
		tick()


func _process(_delta: float) -> void:
	var player := local_player()
	if player == null or not visible:
		return
	var cell := _cell_of(player)
	var dir: String = player.lastAnimDirection
	if cell != hero_cell or dir != facing:
		hero_cell = cell
		facing = dir
		_view.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or local_player() == null:
		return
	if event.keycode != KEY_M:
		return
	if event.shift_pressed:
		if parchment.is_open():
			parchment.hide_map()
		else:
			maximize()
	else:
		shown = not shown
		if parchment.is_open():
			parchment.hide_map()
	apply_chrome()
	get_viewport().set_input_as_handled()


func _add_header_buttons() -> void:
	## Collapse and maximize sit in the wood header. The round minimap button
	## is a sibling in the top-right arc, so it stays up when this panel hides.
	var collapse := _header_button("CollapseButton", MapWoodButton.Glyph.MINUS, Vector2(184, 1))
	collapse.activated.connect(collapse_panel)
	var maximize_button := _header_button("MaximizeButton", MapWoodButton.Glyph.SQUARE, Vector2(204, 1))
	maximize_button.activated.connect(maximize)
	_map_button = Button.new()
	_map_button.name = "MinimapButton"
	_map_button.toggle_mode = true
	_map_button.theme = load("res://art/ui/main_menu_theme.tres")
	_map_button.icon = MAP_ICON
	_map_button.tooltip_text = "Minimap"
	RoundHudStyle.apply(_map_button)
	_map_button.pressed.connect(_on_map_button)
	parchment = ParchmentMap.new()
	parchment.panel = self
	# The canvas layer is still entering the tree when the panel's _ready runs.
	var layer := get_parent()
	layer.add_child.call_deferred(_map_button)
	layer.add_child.call_deferred(parchment)


func _on_map_button() -> void:
	## Opens the wood panel, or closes it. A press while the parchment is up
	## puts the parchment away and leaves the panel closed.
	if parchment != null and parchment.is_open():
		parchment.hide_map()
		shown = false
	else:
		shown = not shown
	apply_chrome()


func _header_button(node_name: String, glyph: int, at: Vector2) -> MapWoodButton:
	var button := MapWoodButton.new()
	button.name = node_name
	button.glyph = glyph
	button.position = at
	button.size = Vector2(18, 14)
	add_child(button)
	return button


func collapse_panel() -> void:
	shown = false
	apply_chrome()


func reopen_panel() -> void:
	shown = true
	apply_chrome()


func maximize() -> void:
	if local_player() == null:
		return
	parchment.show_map()
	apply_chrome()


func apply_chrome() -> void:
	## The wood window, or neither while it is closed or the parchment is up.
	## The round minimap button stays in the top-right arc either way.
	var playing := local_player() != null
	var map_open := parchment != null and parchment.is_open()
	visible = shown and playing and not map_open
	if _map_button:
		_map_button.set_pressed_no_signal(visible)


func tick() -> void:
	## Shows the panel while there is a local hero and reveals the cells
	## around it.
	var player := local_player()
	apply_chrome()
	if player == null:
		return
	var map := _map()
	if not map.player_spawned:
		return  # a client's hero waits at the origin until it is placed
	var health := player.get_node_or_null("Health") as PlayerHealth
	if health and health.is_dead():
		return
	hero_cell = _cell_of(player)
	facing = player.lastAnimDirection
	# Reveal only when two ticks in a row agree, so the spot a joining hero
	# passes through before it is placed (or a respawn jump) is not revealed.
	var steady := _last_sample != Vector2i.MAX \
			and (hero_cell - _last_sample).length_squared() <= ExploredMap.REVEAL_RADIUS * ExploredMap.REVEAL_RADIUS
	_last_sample = hero_cell
	if not steady:
		return
	reveal_around(hero_cell)
	_view.queue_redraw()


func reveal_around(cell: Vector2i) -> void:
	## Reveals the cells around cell and paints them into the chunk images.
	var fresh := explored.reveal_cells(cell)
	if fresh.is_empty():
		return
	# A new cell's own pixels, plus the coast line of the explored land beside it.
	var paint := {}
	for c in fresh:
		paint[c] = true
		for d in _SIDES:
			paint[c + d] = true
	var dirty := {}
	for c: Vector2i in paint:
		if not explored.is_explored(c):
			continue
		var chunk := ExploredMap.chunk_of(c)
		var img: Image = _images.get(chunk)
		if img == null:
			img = _blank_image()
			_images[chunk] = img
		_paint_cell(img, c)
		dirty[chunk] = true
	for chunk in dirty:
		var tex: ImageTexture = _textures.get(chunk)
		if tex:
			tex.update(_images[chunk])
		else:
			_textures[chunk] = ImageTexture.create_from_image(_images[chunk])
	_view.queue_redraw()


func restore_chart(chunks: Dictionary) -> void:
	## Replace explored cells (`chunks` is chunk -> a 128-byte bitset). Empty clears.
	explored.replace_chunks(chunks)
	for bucket in [_textures, _images, _terrain]:
		bucket.clear()
	_last_sample = Vector2i.MAX
	for chunk in explored.chunks():
		var img := render_chunk(chunk)
		_images[chunk] = img
		_textures[chunk] = ImageTexture.create_from_image(img)
	if _view:
		_view.queue_redraw()


func local_player() -> Node2D:
	var world := get_node_or_null(WORLD_PATH)
	if world == null:
		return null
	var player := world.get_node_or_null(str(multiplayer.get_unique_id())) as Node2D
	if player == null or player.get("lastAnimDirection") == null:
		return null  # a stand-in node with the hero's name is not a hero
	return player


func chunk_texture(chunk: Vector2i) -> ImageTexture:
	return _textures.get(chunk)


func chunk_image(chunk: Vector2i) -> Image:
	## The image behind chunk's texture, as painted so far.
	return _images.get(chunk)


func render_chunk(chunk: Vector2i) -> Image:
	## The chunk's explored cells drawn from scratch, 2 x 2 pixels each;
	## unexplored cells stay transparent so the mist below shows through.
	## The incremental images from reveal_around match this pixel for pixel.
	var img := _blank_image()
	var origin := chunk * ExploredMap.CHUNK
	for ly in ExploredMap.CHUNK:
		for lx in ExploredMap.CHUNK:
			var cell := origin + Vector2i(lx, ly)
			if explored.is_explored(cell):
				_paint_cell(img, cell)
	return img


func _paint_cell(img: Image, cell: Vector2i) -> void:
	var info := _cell_info(cell, true)
	var kind := (info & _KIND_BITS) - 1
	var shore := info & _SHORE != 0
	var local := Vector2i(posmod(cell.x, ExploredMap.CHUNK), posmod(cell.y, ExploredMap.CHUNK)) * CELL_PX
	for sy in CELL_PX:
		for sx in CELL_PX:
			var colour := kind_colour(kind, shore, cell, cell.x * CELL_PX + sx, cell.y * CELL_PX + sy)
			if kind != Kind.WATER and _coast(cell, sx, sy):
				colour = INK
			img.set_pixel(local.x + sx, local.y + sy, colour)


func _cell_info(cell: Vector2i, need_shore: bool = false) -> int:
	## Kind + 1 of cell, with _SHORE set on water next to land once
	## need_shore has asked for it. Looked up from the map once per cell.
	var chunk := ExploredMap.chunk_of(cell)
	var bytes: PackedByteArray = _terrain.get(chunk, PackedByteArray())
	if bytes.is_empty():
		bytes.resize(ExploredMap.CHUNK * ExploredMap.CHUNK)
	var i := posmod(cell.y, ExploredMap.CHUNK) * ExploredMap.CHUNK + posmod(cell.x, ExploredMap.CHUNK)
	var info := bytes[i]
	var changed := false
	if info == 0:
		info = kind_of(_map().predict_cell(cell)) + 1
		changed = true
	if need_shore and info & _SHORE_KNOWN == 0:
		info |= _SHORE_KNOWN
		if info & _KIND_BITS == Kind.WATER + 1 and _touches_land(cell):
			info |= _SHORE
		changed = true
	if changed:
		bytes[i] = info
		_terrain[chunk] = bytes
	return info


func _is_water(cell: Vector2i) -> bool:
	return _cell_info(cell) & _KIND_BITS == Kind.WATER + 1


static func kind_of(p: Array) -> int:
	## The map Kind of a predicted [ground, top].
	var ground: Vector2i = p[0]
	if ground == TileCatalog.WATER:
		return Kind.WATER
	if ground == TileCatalog.SAND:
		return Kind.SAND
	if ground == TileCatalog.SWAMP or ground == TileCatalog.SWAMP_SPECIAL:
		return Kind.SWAMP
	match p[1]:
		TileCatalog.PINE:
			return Kind.PINE
		TileCatalog.TREE, TileCatalog.TREE_BUSHY:
			return Kind.TREE
		TileCatalog.BUSH:
			return Kind.BUSH
		TileCatalog.STONES:
			return Kind.STONES
		TileCatalog.FLOWER:
			return Kind.FLOWER
	return Kind.GRASS


static func cell_colour(p: Array, shore: bool, cell: Vector2i, px: int, py: int) -> Color:
	## Map colour of one pixel of a cell from its predicted [ground, top].
	return kind_colour(kind_of(p), shore, cell, px, py)


static func kind_colour(kind: int, shore: bool, cell: Vector2i, px: int, py: int) -> Color:
	match kind:
		Kind.WATER:
			return SKY if shore else SKY_DEEP
		Kind.SAND:
			return THATCH
		Kind.SWAMP:
			return SKY_DEEP if (px * 2 + py) % 5 == 0 else GRASS_DARK
		Kind.PINE:
			return LEAF_DEEP
		Kind.TREE:
			return GRASS if posmod(px, CELL_PX) == 0 and posmod(py, CELL_PX) == 0 else GRASS_DARK
		Kind.BUSH:
			return GRASS_DARK
		Kind.STONES:
			return STONE
		Kind.FLOWER:
			if posmod(px, 2) == 0 and posmod(py, 2) == 1:
				return GOLD
	return GRASS_HI if _hash01(cell) < 0.12 else GRASS


func _draw_map() -> void:
	# Mist under everything, then the explored chunks, then the hero.
	_view.draw_texture(_mist, Vector2.ZERO)
	var half := Vector2i(WINDOW.size.x / CELL_PX / 2, WINDOW.size.y / CELL_PX / 2)
	var top_left := hero_cell - half
	var first := ExploredMap.chunk_of(top_left)
	var last := ExploredMap.chunk_of(top_left + WINDOW.size / CELL_PX)
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var tex: ImageTexture = _textures.get(Vector2i(cx, cy))
			if tex:
				_view.draw_texture(tex, Vector2((Vector2i(cx, cy) * ExploredMap.CHUNK - top_left) * CELL_PX))
	var marker: Texture2D = HERO.get(facing, HERO["Down"])
	_view.draw_texture(marker, Vector2(half * CELL_PX + Vector2i.ONE - HERO_ANCHOR))
	paint_city_walls(_view, top_left, WINDOW.size)


func paint_city_walls(target: CanvasItem, top_left: Vector2i, window_size: Vector2i) -> void:
	## Owner-coloured city wall cells over an explored window (#277).
	var cities: Cities = get_node_or_null(WORLD_PATH + "/Cities")
	if cities == null or cities.cities.is_empty():
		return
	var map := _map()
	if map == null:
		return
	var placed: Dictionary = map.placed_structures()
	for id: int in cities.cities:
		var owner: int = placed.get(id, {}).get("owner", 0)
		var colour: Color = CITY_HOST if owner == 1 else (
			CITY_MOBS if owner == StructurePlacer.OWNER_MOBS else (
			CITY_NEUTRAL if owner == StructurePlacer.OWNER_NEUTRAL else CITY_OTHER))
		for cell: Vector2i in cities.cities[id]["walls"]:
			if not explored.is_explored(cell):
				continue
			var local := (cell - top_left) * CELL_PX
			if local.x < -CELL_PX or local.y < -CELL_PX \
					or local.x >= window_size.x or local.y >= window_size.y:
				continue
			target.draw_rect(Rect2(Vector2(local), Vector2(CELL_PX, CELL_PX)), colour)


func _on_ground_changed(cells: Rect2i) -> void:
	if cells.size != Vector2i.ZERO:
		return
	explored.clear()
	_textures.clear()
	_images.clear()
	_terrain.clear()
	_last_sample = Vector2i.MAX
	if parchment and parchment.is_open():
		parchment.hide_map()
	apply_chrome()
	_view.queue_redraw()


func _fit_pixel_scale() -> void:
	## Whole art pixels from the right edge, rounded down so the attack button stays clear.
	var stretch := get_viewport().get_final_transform().get_scale().x
	if stretch <= 0.0:
		return
	var k := floorf(stretch) / stretch if stretch >= 1.0 else 1.0
	scale = Vector2(k, k)
	position = Vector2(get_viewport_rect().size.x - (size.x + MARGIN) * k, maxf(TOP * k, 23.0))


func _map() -> Node:
	return get_node_or_null(WORLD_PATH + "/worldMap")


func _cell_of(player: Node2D) -> Vector2i:
	var map := _map()
	return map.local_to_map(map.to_local(player.global_position))


func _touches_land(cell: Vector2i) -> bool:
	for d in _NEIGHBOURS:
		if not _is_water(cell + d):
			return true
	return false


func _coast(cell: Vector2i, sx: int, sy: int) -> bool:
	## True when this land pixel sits on an edge shared with explored water.
	var side := [Vector2i(-1 if sx == 0 else 1, 0), Vector2i(0, -1 if sy == 0 else 1)]
	for d: Vector2i in side:
		var n := cell + d
		if explored.is_explored(n) and _is_water(n):
			return true
	return false


func _blank_image() -> Image:
	return Image.create(ExploredMap.CHUNK * CELL_PX, ExploredMap.CHUNK * CELL_PX, false, Image.FORMAT_RGBA8)


func _mist_image() -> Image:
	var img := Image.create(WINDOW.size.x, WINDOW.size.y, false, Image.FORMAT_RGBA8)
	for y in WINDOW.size.y:
		for x in WINDOW.size.x:
			img.set_pixel(x, y, CLOUD_SHADE if (x + y) % 2 == 0 else CLOUD)
	return img


static func _hash01(cell: Vector2i) -> float:
	var h := (cell.x * 374761393 + cell.y * 668265263 + 3 * 2147483647) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	return float(h ^ (h >> 16)) / 4294967296.0
