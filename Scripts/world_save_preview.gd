class_name WorldSavePreview
extends RefCounted
## Small terrain thumbnails for saved worlds, from generation inputs only.

const PREVIEW_DIR := MapSave.SAVE_DIR + "_previews/v1/"
const TILE_SET := "res://art/flagoria/flagoria_tiles_v3.tres"
const MAP_SCRIPT := "res://Scripts/TileMap.gd"
const CELLS := Vector2i(40, 24)
const ICON_SIZE := Vector2i(64, 40)
const PLACEHOLDER := Color(0.32, 0.34, 0.4)

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


static func build_image(map: TileMap, params: MapGenParams) -> Image:
	## Predicted terrain over CELLS around the origin, scaled to ICON_SIZE.
	map.apply_map_params(params)
	var img := Image.create(CELLS.x, CELLS.y, false, Image.FORMAT_RGBA8)
	var ox := CELLS.x / 2
	var oy := CELLS.y / 2
	for y in CELLS.y:
		for x in CELLS.x:
			var cell := Vector2i(x - ox, y - oy)
			var p: Array = map.predict_cell(cell)
			img.set_pixel(x, y, MinimapPanel.cell_colour(p, false, cell, 0, 0))
	img.resize(ICON_SIZE.x, ICON_SIZE.y, Image.INTERPOLATE_NEAREST)
	return img


static func _try_build(tree: SceneTree, save_path: String) -> Image:
	var loaded := MapSave.load_map(save_path)
	if loaded["error"] != "" or loaded["params"] == null:
		return null
	var data: Dictionary = loaded["params"].to_dict()
	for key in data.keys():
		if key.ends_with("_seed") and data[key] == 0:
			return null
	return build_image(_sampler_map(tree), loaded["params"])


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