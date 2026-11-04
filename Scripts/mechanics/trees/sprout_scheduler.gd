class_name SproutScheduler
extends RefCounted
## Runs TreeSprouts' passes over the due() calls (#361), so that no call
## pays for a fresh area or a whole pass: each call does at most about
## WORK_MS of work, counting squares not yet counted around the players or
## going on with the pass in progress square by square.

const _WorldMap := preload("res://Scripts/TileMap.gd")

## Milliseconds of work a due() call may start: counting squares not yet
## counted around the players (_count_squares), or the next squares of the
## pass in progress (_step). It checks before each square, so a call ends
## at most one square later.
const WORK_MS := 2.0

var _next_pass := 0.0
## The pass in progress (_step): windows still to do, the chance, and for
## the first: its squares left, the [land, grown, now] counts while they
## are counted (TreeSprouts.deficits), then the trees still wanted per biome.
var _todo: Array[Rect2i] = []
var _chance := 0.0
var _left: Array[Vector2i] = []
var _counts: Array = []
var _want: Dictionary = {}
var _sprouts: TreeSprouts
var _map: _WorldMap


func _init(sprouts: TreeSprouts, map: _WorldMap) -> void:
	_sprouts = sprouts
	_map = map


func clear() -> void:
	_next_pass = 0.0
	_todo.clear()
	_left.clear()
	_counts = []
	_want.clear()


func busy() -> bool:
	## True while a pass is in progress.
	return not _todo.is_empty()


func due() -> Array[Vector2i]:
	## TreeSprouts.due: every PASS_SECONDS of play, a pass that runs
	## TreeSprouts.sprout_pass on the AREA_CHUNKS area around each player,
	## with chance PASS_SECONDS over the tree regrow delay (the map's
	## regrow_delay when set; 0 = never). Emits the map's trees_sprouted with the cells each
	## call adds. A client never sprouts on its own.
	## Each call does up to WORK_MS of work: while a pass is in progress, its
	## next squares (_step); otherwise it counts squares around the players
	## (_count_squares), and starts a pass only on a call that found them all
	## counted, so it waits a few calls in an area not counted yet.
	var out: Array[Vector2i] = []
	if Interaction.multiplayer_on(_map.multiplayer) and not _map.multiplayer.is_server():
		return out
	var delay: float = _map.regrow_delay if _map.regrow_delay >= 0.0 else InteractableCatalog.by_id("tree").regrow_delay
	if delay <= 0.0:
		_todo.clear()
		return out
	var start := Time.get_ticks_usec()
	if _todo.is_empty():
		var size_v := Vector2i(_map.chunk_width, _map.chunk_height) * TreeSprouts.AREA_CHUNKS
		var windows: Array[Rect2i] = []
		for node in _map.get_parent().get_children():
			if node is CharacterBody2D and str(node.name).is_valid_int():
				windows.append(Rect2i(_map.local_to_map(_map.to_local(node.global_position)) - size_v / 2, size_v))
		if not _count_squares(windows, start) or _map.play_time < _next_pass or windows.is_empty():
			return out
		_next_pass = _map.play_time + TreeSprouts.PASS_SECONDS
		_todo = windows
		_chance = minf(1.0, TreeSprouts.PASS_SECONDS / delay)
	out = _step(start)
	if not out.is_empty():
		_map.trees_sprouted.emit(out)
	return out


func _step(start: int) -> Array[Vector2i]:
	## Go on with the pass in progress until WORK_MS from `start` (usec):
	## for each window in turn, count its squares (_count_square), roll how
	## many trees sprout (_roll), then look for free cells square by square
	## in a random order (_pick_in) and sprout them, until its wants are met.
	## The blocked cells are gathered once per call. Returns the sprouted
	## cells.
	var out: Array[Vector2i] = []
	var blocked := _sprouts.blocked_cells()
	while not _todo.is_empty() and Time.get_ticks_usec() - start < WORK_MS * 1000.0:
		var window := _todo[0]
		if _left.is_empty() and _counts.is_empty() and _want.is_empty():
			_left = _sprouts._squares(window)
			_counts = [{}, {}, {}]
		elif not _counts.is_empty():
			_sprouts._count_square(_left.pop_back(), window, _counts)
			if _left.is_empty():
				_want = _sprouts._roll(_sprouts._missing(_counts), _chance)
				_counts = []
				_left = _sprouts._squares(window)
				_left.shuffle()
		else:
			for cell in _sprouts._pick_in(_left.pop_back(), window, _want, blocked):
				if _sprouts.add(cell):
					out.append(cell)
		if _counts.is_empty() and (_want.is_empty() or _left.is_empty()):
			_todo.pop_front()
			_left.clear()
			_want.clear()
	return out


func _count_squares(windows: Array[Rect2i], start: int) -> bool:
	## Build the _block_table of squares `windows` overlap that are not
	## counted yet, until WORK_MS from `start` (usec). True when they all
	## were counted before this call.
	var ready := true
	for window in windows:
		for square in _sprouts._squares(window):
			if not _sprouts._tables.has(square):
				ready = false
				if Time.get_ticks_usec() - start >= WORK_MS * 1000.0:
					return false
				_sprouts._block_table(square)
	return ready
