class_name WorldSavePreview
extends RefCounted
## Small terrain thumbnails for saved worlds, from generation inputs only.

const PREVIEW_DIR := MapSave.SAVE_DIR + "_previews/v2/"
const TILE_SET := "res://art/flagoria/flagoria_tiles_v3.tres"
const MAP_SCRIPT := "res://Scripts/TileMap.gd"
const ICON_SIZE := Vector2i(64, 40)
const MIN_LAND_FRACTION := 0.02
const PLACEHOLDER := Color(0.32, 0.34, 0.4)
const _NEIGHBOURS := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]

static var _sampler: TileMap
static var _placeholder: ImageTexture


static func icon_for(tree: SceneTree, save_path: String, save_name: String) -> Texture2D:
	## Cached preview for one save, or a placeholder when the file or preview is missing.
	var cached := _load_png(save_name)
	if cached != null and not _stale(save_path, save_name):
		return ImageTexture.create_from_image(cached)
	var built := _try_build(tree, save_path)
	if built != null:
		_store_png(save_name, built)
		return ImageTexture.create_from_image(built)
	return placeholder()


static func remove(save_name: String) -> void:
	var path := _png_path(save_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func rename_save(old_name: String, new_name: String) -> void:
	var old_path := _png_path(old_name)
	if not FileAccess.file_exists(old_path):
		return
	var new_path := _png_path(new_name)
	if FileAccess.file_exists(new_path):
		DirAccess.remove_absolute(new_path)
	DirAccess.rename_absolute(old_path, new_path)


static func placeholder() -> ImageTexture:
	if _placeholder == null:
		var img := Image.create(ICON_SIZE.x, ICON_SIZE.y, false, Image.FORMAT_RGBA8)
		img.fill(PLACEHOLDER)
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


static func land_pixel_fraction(img: Image) -> float:
	## Share of thumbnail pixels that are not open water (MinimapPanel palette).
	var land := 0
	var sky := MinimapPanel.SKY
	var deep := MinimapPanel.SKY_DEEP
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c != sky and c != deep:
				land += 1
	return float(land) / float(img.get_width() * img.get_height())


static func build_image(map: TileMap, params: MapGenParams) -> Image:
	## The whole generated world in sample_rect, fitted to ICON_SIZE.
	map.apply_map_params(params)
	var region := _sample_rect(map)
	var kinds := PackedInt32Array()
	kinds.resize(ICON_SIZE.x * ICON_SIZE.y)
	var cells: Array[Vector2i] = []
	cells.resize(ICON_SIZE.x * ICON_SIZE.y)
	for py in ICON_SIZE.y:
		for px in ICON_SIZE.x:
			var idx := py * ICON_SIZE.x + px
			var cell := Vector2i(
					region.position.x + int((px * region.size.x) / float(ICON_SIZE.x)),
					region.position.y + int((py * region.size.y) / float(ICON_SIZE.y)))
			cells[idx] = cell
			kinds[idx] = MinimapPanel.kind_of(map.predict_cell(cell))
	var img := Image.create(ICON_SIZE.x, ICON_SIZE.y, false, Image.FORMAT_RGBA8)
	for py in ICON_SIZE.y:
		for px in ICON_SIZE.x:
			var idx := py * ICON_SIZE.x + px
			var kind: int = kinds[idx]
			var shore := kind == MinimapPanel.Kind.WATER and _touches_land(kinds, px, py)
			img.set_pixel(px, py, MinimapPanel.kind_colour(kind, shore, cells[idx], px, py))
	return img


static func _touches_land(kinds: PackedInt32Array, px: int, py: int) -> bool:
	for d in _NEIGHBOURS:
		var nx: int = px + d.x
		var ny: int = py + d.y
		if nx < 0 or ny < 0 or nx >= ICON_SIZE.x or ny >= ICON_SIZE.y:
			continue
		if kinds[ny * ICON_SIZE.x + nx] != MinimapPanel.Kind.WATER:
			return true
	return false


static func _sample_rect(map: TileMap) -> Rect2i:
	## Cell bounds that cover every shaped island in this world's params.
	if map.archipelago_spacing > 0:
		var extent: int = map.archipelago_world_extent
		if extent > 0:
			var edge: int = extent + map.archipelago_island_radius
			return Rect2i(-edge, -edge, edge * 2 + 1, edge * 2 + 1)
		if map.archipelago_island_count > 0:
			var rings: int = ceili(sqrt(float(map.archipelago_island_count))) + 1
			var edge2: int = rings * map.archipelago_spacing + map.archipelago_island_radius
			return Rect2i(-edge2, -edge2, edge2 * 2 + 1, edge2 * 2 + 1)
		var fallback: int = map.archipelago_spacing * 6 + map.archipelago_island_radius
		return Rect2i(-fallback, -fallback, fallback * 2 + 1, fallback * 2 + 1)
	if map.island_radius > 0:
		var margin := 12
		var r: int = map.island_radius + margin
		return Rect2i(-r, -r, r * 2 + 1, r * 2 + 1)
	var half_w := maxi(1, map.chunk_width / 2)
	var half_h := maxi(1, map.chunk_height / 2)
	return Rect2i(-half_w, -half_h, half_w * 2 + 1, half_h * 2 + 1)


static func _try_build(tree: SceneTree, save_path: String) -> Image:
	var loaded := MapSave.load_map(save_path)
	if loaded["error"] != "" or loaded["params"] == null:
		return null
	var data: Dictionary = loaded["params"].to_dict()
	for key in data.keys():
		if key.ends_with("_seed") and data[key] == 0:
			return null
	var img := build_image(_sampler_map(tree), loaded["params"])
	if land_pixel_fraction(img) < MIN_LAND_FRACTION:
		return null
	return img


static func _sampler_map(tree: SceneTree) -> TileMap:
	if _sampler != null and is_instance_valid(_sampler):
		return _sampler
	_sampler = TileMap.new()
	_sampler.name = "WorldSavePreviewSampler"
	_sampler.visible = false
	_sampler.tile_set = load(TILE_SET)
	_sampler.set_script(load(MAP_SCRIPT))
	tree.root.add_child(_sampler)
	return _sampler


static func _png_path(save_name: String) -> String:
	return PREVIEW_DIR + save_name.validate_filename() + ".png"


static func _stale(save_path: String, save_name: String) -> bool:
	if not FileAccess.file_exists(save_path):
		return true
	var png := _png_path(save_name)
	return FileAccess.get_modified_time(png) < FileAccess.get_modified_time(save_path)


static func _load_png(save_name: String) -> Image:
	var path := _png_path(save_name)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return img


static func _store_png(save_name: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(PREVIEW_DIR)
	img.save_png(_png_path(save_name))