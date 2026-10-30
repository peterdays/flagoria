class_name MinimapPanel
extends Control
## The in-play explored map: a wood panel in the top right corner that shows
## the ground the local hero has explored, centred on the hero, at 2 screen
## pixels per world cell. Cells the hero has not been near show as mist.
## Exploration is local to this client for now (no network traffic); a new
## world clears it. M hides or shows the panel.
##
## Each explored 32 x 32 cell chunk is drawn once into a 64 x 64 texture and
## only redrawn when its explored cells change, so a frame just draws the few
## chunk textures under the map window.

const FRAME := preload("res://art/ui/map/ui_map_panel_open.png")
const HERO := {
	"Up": preload("res://art/ui/map/ui_map_marker_hero_up.png"),
	"Right": preload("res://art/ui/map/ui_map_marker_hero_right.png"),
	"Down": preload("res://art/ui/map/ui_map_marker_hero_down.png"),
	"Left": preload("res://art/ui/map/ui_map_marker_hero_left.png"),
}
const MARGIN := 4.0  ## art pixels from the right edge
const TOP := 28.0  ## art pixels from the top, below the HUD buttons
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

const _NEIGHBOURS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
		Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

var explored := ExploredMap.new()
var hero_cell := Vector2i.ZERO
var facing := "Down"
var shown := true  ## false after M hides the panel

var _textures := {}  ## chunk (Vector2i) -> ImageTexture
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
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_M and not event.shift_pressed and local_player() != null:
		shown = not shown
		visible = shown
		get_viewport().set_input_as_handled()


func tick() -> void:
	## Shows the panel while there is a local hero and reveals the cells
	## around it.
	var player := local_player()
	visible = shown and player != null
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
	var changed := explored.reveal(hero_cell)
	var dirty := {}
	for chunk in changed:
		dirty[chunk] = true
		# Coast lines on a neighbour's edge depend on cells in this chunk.
		for d in _NEIGHBOURS:
			if _textures.has(chunk + d):
				dirty[chunk + d] = true
	for chunk in dirty:
		_textures[chunk] = ImageTexture.create_from_image(render_chunk(chunk))
	_view.queue_redraw()


func local_player() -> Node2D:
	var world := get_node_or_null(WORLD_PATH)
	if world == null:
		return null
	return world.get_node_or_null(str(multiplayer.get_unique_id())) as Node2D


func chunk_texture(chunk: Vector2i) -> ImageTexture:
	return _textures.get(chunk)


func render_chunk(chunk: Vector2i) -> Image:
	## The chunk's explored cells, 2 x 2 pixels each; unexplored cells stay
	## transparent so the mist below shows through.
	var img := Image.create(ExploredMap.CHUNK * CELL_PX, ExploredMap.CHUNK * CELL_PX, false, Image.FORMAT_RGBA8)
	var map := _map()
	var origin := chunk * ExploredMap.CHUNK
	for ly in ExploredMap.CHUNK:
		for lx in ExploredMap.CHUNK:
			var cell := origin + Vector2i(lx, ly)
			if not explored.is_explored(cell):
				continue
			var p: Array = map.predict_cell(cell)
			var water: bool = p[0] == TileCatalog.WATER
			var shore := water and _touches_land(map, cell)
			for sy in CELL_PX:
				for sx in CELL_PX:
					var px := cell.x * CELL_PX + sx
					var py := cell.y * CELL_PX + sy
					var colour := cell_colour(p, shore, cell, px, py)
					if not water and _coast(map, cell, sx, sy):
						colour = INK
					img.set_pixel(lx * CELL_PX + sx, ly * CELL_PX + sy, colour)
	return img


static func cell_colour(p: Array, shore: bool, cell: Vector2i, px: int, py: int) -> Color:
	## Map colour of one pixel of a cell from its predicted [ground, top].
	var ground: Vector2i = p[0]
	var top: Vector2i = p[1]
	if ground == TileCatalog.WATER:
		return SKY if shore else SKY_DEEP
	if ground == TileCatalog.SAND:
		return THATCH
	if ground == TileCatalog.SWAMP or ground == TileCatalog.SWAMP_SPECIAL:
		return SKY_DEEP if (px * 2 + py) % 5 == 0 else GRASS_DARK
	match top:
		TileCatalog.PINE:
			return LEAF_DEEP
		TileCatalog.TREE:
			return GRASS if posmod(px, CELL_PX) == 0 and posmod(py, CELL_PX) == 0 else GRASS_DARK
		TileCatalog.BUSH:
			return GRASS_DARK
		TileCatalog.STONES:
			return STONE
		TileCatalog.FLOWER:
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


func _on_ground_changed(cells: Rect2i) -> void:
	if cells.size != Vector2i.ZERO:
		return
	# A new world: what was explored belongs to the old one.
	explored.clear()
	_textures.clear()
	_last_sample = Vector2i.MAX
	_view.queue_redraw()


func _fit_pixel_scale() -> void:
	## Whole screen pixels per art pixel, like the hearts, kept MARGIN art
	## pixels from the right edge. Rounds down, never up, so the panel stays
	## clear of the attack button at fractional window stretches.
	var stretch := get_viewport().get_final_transform().get_scale().x
	if stretch <= 0.0:
		return
	var k := floorf(stretch) / stretch if stretch >= 1.0 else 1.0
	scale = Vector2(k, k)
	position = Vector2(get_viewport_rect().size.x - (size.x + MARGIN) * k, TOP * k)


func _map() -> Node:
	return get_node_or_null(WORLD_PATH + "/worldMap")


func _cell_of(player: Node2D) -> Vector2i:
	var map := _map()
	return map.local_to_map(map.to_local(player.global_position))


func _touches_land(map: Node, cell: Vector2i) -> bool:
	for d in _NEIGHBOURS:
		if map.predict_cell(cell + d)[0] != TileCatalog.WATER:
			return true
	return false


func _coast(map: Node, cell: Vector2i, sx: int, sy: int) -> bool:
	## True when this land pixel sits on an edge shared with explored water.
	var side := [Vector2i(-1 if sx == 0 else 1, 0), Vector2i(0, -1 if sy == 0 else 1)]
	for d: Vector2i in side:
		var n := cell + d
		if explored.is_explored(n) and map.predict_cell(n)[0] == TileCatalog.WATER:
			return true
	return false


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
