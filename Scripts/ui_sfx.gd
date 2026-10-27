extends Node
## Autoload: UI sounds, local to this client on the SFX bus. Nothing here is
## networked; each client hears only its own presses, menus and saves.
##
## Hooks (all here, so scenes only tag nodes with a group):
##   click      - any BaseButton press, found when the button enters the tree.
##   back       - a press on a button in the "ui_back" group (Back, Close,
##                Cancel) instead of click.
##   menu_open  - a Control in the "ui_menu" group becomes visible.
##   menu_close - a "ui_menu" Control stops being visible.
##   saved      - MapGen.map_saved, emitted when a map save succeeds.
##
## The press sound is connected ahead of the button's own handlers, so it
## starts before a handler that blocks (hosting builds the world) or changes
## the scene. This node is an autoload and outlives scene changes, so the
## sound keeps playing after the button is gone.

const BACK_GROUP := &"ui_back"
const MENU_GROUP := &"ui_menu"
const SOUNDS := {
	"click": [preload("res://art/audio/sfx/ui/click_01.wav")],
	"back": [preload("res://art/audio/sfx/ui/back_01.wav")],
	"menu_open": [preload("res://art/audio/sfx/ui/menu_open_01.wav")],
	"menu_close": [preload("res://art/audio/sfx/ui/menu_close_01.wav")],
	"saved": [preload("res://art/audio/sfx/ui/saved_01.wav")],
}
## The clips sit at about -22 dBFS RMS, 2 dB under the gameplay clips, so UI
## stays a little under combat (-8..-10 dB on -20 dBFS clips). The click is
## 65 ms, the shortest, so it gets 1 dB more.
const VOLUME_DB := {"click": -9.0, "back": -10.0, "menu_open": -10.0, "menu_close": -10.0, "saved": -10.0}
## Minimum seconds between two plays of the same event (stops a double fire
## in one frame, not a fast second press).
const COOLDOWN := {"click": 0.04, "back": 0.04, "menu_open": 0.1, "menu_close": 0.1, "saved": 0.3}

## Plays started per event (tests read this; playback is not observable headless).
var plays := {"click": 0, "back": 0, "menu_open": 0, "menu_close": 0, "saved": 0}
var _players := {}
var _last_ms := {}
var _menu_shown := {}  # Control instance id -> last is_visible_in_tree()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus can pause the game
	for event in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.name = event
		p.volume_db = VOLUME_DB[event]
		p.max_polyphony = 2
		p.bus = &"SFX"
		add_child(p)
		_players[event] = p
	get_tree().node_added.connect(_watch)
	_watch_tree(get_tree().root)
	var map_gen := get_node_or_null("/root/MapGen")
	if map_gen:
		map_gen.map_saved.connect(func(_path: String) -> void: play_event("saved"))


func players() -> Dictionary:
	return _players


static func sound_for(button: BaseButton) -> String:
	return "back" if button.is_in_group(BACK_GROUP) else "click"


func _watch_tree(node: Node) -> void:
	_watch(node)
	for child in node.get_children():
		_watch_tree(child)


func _watch(node: Node) -> void:
	if node is BaseButton:
		_watch_button(node)
	if node is CanvasItem and node.is_in_group(MENU_GROUP):
		var item := node as CanvasItem
		_menu_shown[item.get_instance_id()] = item.is_visible_in_tree()
		if not item.has_meta(&"ui_sfx_menu"):
			item.set_meta(&"ui_sfx_menu", true)
			item.visibility_changed.connect(_on_menu_visibility.bind(item))


func _watch_button(button: BaseButton) -> void:
	if button.has_meta(&"ui_sfx_button"):
		return  # re-entering the tree: already connected
	button.set_meta(&"ui_sfx_button", true)
	var cb := _on_button_pressed.bind(button)
	# Signals call in connection order, and the scene's own connections are
	# made before the button enters the tree: take them off, connect the
	# sound, and put them back after it.
	var others := button.pressed.get_connections()
	for c in others:
		button.pressed.disconnect(c["callable"])
	button.pressed.connect(cb)
	for c in others:
		button.pressed.connect(c["callable"], c["flags"])


func _on_button_pressed(button: BaseButton) -> void:
	play_event(sound_for(button))


func _on_menu_visibility(item: CanvasItem) -> void:
	var shown := item.is_visible_in_tree()
	var id := item.get_instance_id()
	if shown == _menu_shown.get(id, shown):
		return
	_menu_shown[id] = shown
	play_event("menu_open" if shown else "menu_close")


func play_event(event: String) -> bool:
	## Play `event` unless it played less than COOLDOWN ago. Returns true if it played.
	if not SOUNDS.has(event):
		return false
	var now := Time.get_ticks_msec()
	if _last_ms.has(event) and now - int(_last_ms[event]) < int(COOLDOWN[event] * 1000.0):
		return false
	_last_ms[event] = now
	var options: Array = SOUNDS[event]
	var p: AudioStreamPlayer = _players[event]
	p.stream = options[randi() % options.size()]
	p.play()
	plays[event] += 1
	return true
