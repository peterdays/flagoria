extends SceneTree
## Smoke checks for the generated art the game ships: the hero sheet, the app
## icon and the main menu theme. Each check loads the committed output the way
## the game does and checks the shape it was generated with. A broken re-run of
## tools/hero/make_hero.py or tools/icon/make_icon.py, or a theme edit that
## drops a style, then fails here instead of in a play-test.
##
## Run: godot --headless --path . --script res://tools/generator_smoke.gd \
##     [-- --hero-sheet=/abs/path/flagbearer_sheet.png]
## With --hero-sheet, that freshly generated sheet must match the committed one
## pixel for pixel. Prints GENERATOR_SMOKE_OK on success.

const HERO_SHEET := "res://art/hero/sheets/flagbearer_sheet.png"
const HERO_SHEET_SIZE := Vector2i(128, 256)
const PLAYER_SCENE := "res://Player/character_body_2d.tscn"
const MENU_SCENE := "res://flagoria_main.tscn"
const MENU_THEME := "res://art/ui/main_menu_theme.tres"
const BUTTON_STYLES := ["normal", "hover", "pressed", "disabled", "focus"]
## export_presets.cfg Android launcher keys and the square size each needs.
const LAUNCHER_ICONS := {
	"launcher_icons/main_192x192": 192,
	"launcher_icons/adaptive_foreground_432x432": 432,
	"launcher_icons/adaptive_background_432x432": 432,
}
const PROJECT_ICON_SIZE := 256

var _failures := 0


func _initialize() -> void:
	_check_hero()
	_check_icon()
	_check_menu_theme()
	if _failures == 0:
		print("GENERATOR_SMOKE_OK")
		quit(0)
	else:
		printerr("generator smoke: %d failure(s)" % _failures)
		quit(1)


func _fail(message: String) -> void:
	printerr("FAIL " + message)
	_failures += 1


func _texture_size(path: String) -> Vector2i:
	## Size of an imported texture, or (0, 0) after reporting why it is missing.
	if path.is_empty() or not ResourceLoader.exists(path):
		_fail("missing texture '%s'" % path)
		return Vector2i.ZERO
	var texture := load(path) as Texture2D
	if texture == null:
		_fail("not a Texture2D: %s" % path)
		return Vector2i.ZERO
	return Vector2i(texture.get_width(), texture.get_height())


func _file_mentions(path: String, needle: String) -> bool:
	return FileAccess.get_file_as_string(path).contains(needle)


func _check_hero() -> void:
	var before := _failures
	var size := _texture_size(HERO_SHEET)
	if size != Vector2i.ZERO and size != HERO_SHEET_SIZE:
		_fail("hero sheet is %s, expected %s" % [size, HERO_SHEET_SIZE])
	if not _file_mentions(PLAYER_SCENE, HERO_SHEET):
		_fail("%s does not use %s" % [PLAYER_SCENE, HERO_SHEET])
	if _failures == before:
		print("PASS hero sheet %s used by the player scene" % HERO_SHEET_SIZE)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hero-sheet="):
			_compare_sheet(arg.trim_prefix("--hero-sheet="))


func _compare_sheet(fresh_path: String) -> void:
	var fresh := Image.load_from_file(fresh_path)
	var committed := Image.load_from_file(ProjectSettings.globalize_path(HERO_SHEET))
	if fresh == null or committed == null:
		_fail("could not read hero sheets for comparison")
		return
	fresh.convert(Image.FORMAT_RGBA8)
	committed.convert(Image.FORMAT_RGBA8)
	if fresh.get_size() != committed.get_size() or fresh.get_data() != committed.get_data():
		_fail("regenerated hero sheet differs from %s; re-run tools/hero/make_hero.py and commit, or fix the generator" % HERO_SHEET)
	else:
		print("PASS hero sheet regenerates identically")


func _check_icon() -> void:
	var before := _failures
	var icon_path := String(ProjectSettings.get_setting("application/config/icon", ""))
	var size := _texture_size(icon_path)
	if size != Vector2i.ZERO and size != Vector2i(PROJECT_ICON_SIZE, PROJECT_ICON_SIZE):
		_fail("project icon %s is %s, expected %d px square" % [icon_path, size, PROJECT_ICON_SIZE])
	var presets := ConfigFile.new()
	if presets.load("res://export_presets.cfg") != OK:
		_fail("cannot read export_presets.cfg")
		return
	for key in LAUNCHER_ICONS:
		var path := String(presets.get_value("preset.0.options", key, ""))
		var want: int = LAUNCHER_ICONS[key]
		var got := _texture_size(path)
		if got != Vector2i.ZERO and got != Vector2i(want, want):
			_fail("%s (%s) is %s, expected %d px square" % [key, path, got, want])
	if _failures == before:
		print("PASS app icon and %d launcher icons" % LAUNCHER_ICONS.size())


func _check_menu_theme() -> void:
	var before := _failures
	var theme := load(MENU_THEME) as Theme
	if theme == null:
		_fail("cannot load %s as a Theme" % MENU_THEME)
		return
	if theme.default_font == null:
		_fail("menu theme has no default font")
	for style in BUTTON_STYLES:
		if not theme.has_stylebox(style, "Button"):
			_fail("menu theme has no Button/%s style" % style)
	if not _file_mentions(MENU_SCENE, MENU_THEME):
		_fail("%s does not use %s" % [MENU_SCENE, MENU_THEME])
	if _failures == before:
		print("PASS menu theme (%d Button styles) used by the main menu" % BUTTON_STYLES.size())
