class_name WfcSolver
extends RefCounted
## Pure GDScript wave function collapse on a rectangular grid (#24). No scenes.
## Input: grid size, a piece set (BuildingBlockPiece resources), seed, and an
## optional attempt cap. Output: piece ids per cell or a deterministic failure.

const DEFAULT_MAX_ATTEMPTS := 64

const STEPS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]


static func adjacency_table(pieces: Array) -> Dictionary:
	var table := {}
	for pa: BuildingBlockPiece in pieces:
		table[pa.id] = {}
		for side: String in BuildingBlockCatalog.SIDES:
			var fits := {}
			for pb: BuildingBlockPiece in pieces:
				if BuildingBlockCatalog.edge_compatible(pa, side, pb):
					fits[pb.id] = true
			table[pa.id][side] = fits
	return table


static func solve(
		width: int,
		height: int,
		pieces: Array,
		seed: int,
		max_attempts: int = DEFAULT_MAX_ATTEMPTS,
) -> Dictionary:
	if width < 1 or height < 1:
		return _fail("grid size must be positive")
	if pieces.is_empty():
		return _fail("piece set is empty")
	var piece_ids: Array[String] = []
	for piece: BuildingBlockPiece in pieces:
		if piece == null or piece.id == "":
			return _fail("every piece needs an id")
		if piece.id in piece_ids:
			return _fail("duplicate piece id %s" % piece.id)
		piece_ids.append(piece.id)
	var adjacency: Dictionary = adjacency_table(pieces)
	var all_opts: Array = piece_ids.duplicate()
	for attempt in max_attempts:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(seed + attempt * 0x9E3779B9)
		var wave: Array = []
		for _y in height:
			var row: Array = []
			for _x in width:
				row.append(all_opts.duplicate())
			wave.append(row)
		if not _collapse(wave, width, height, adjacency, rng):
			continue
		return {"ok": true, "grid": _grid_from_wave(wave), "attempts": attempt + 1}
	var fail: Dictionary = _fail("no solution within %d attempts" % max_attempts)
	fail.attempts = max_attempts
	return fail


static func _fail(message: String, attempts: int = 0) -> Dictionary:
	return {"ok": false, "error": message, "attempts": attempts}


static func _collapse(
		wave: Array,
		width: int,
		height: int,
		adjacency: Dictionary,
		rng: RandomNumberGenerator,
) -> bool:
	while true:
		if _has_contradiction(wave):
			return false
		var pick := _pick_cell(wave, width, height)
		if pick.x < 0:
			return true
		var y: int = pick.y
		var x: int = pick.x
		var opts: Array = wave[y][x]
		var choice: String = opts[rng.randi_range(0, opts.size() - 1)]
		wave[y][x] = [choice]
		var queue: Array[Vector2i] = [Vector2i(x, y)]
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			for i in STEPS.size():
				var nx: int = cell.x + STEPS[i].x
				var ny: int = cell.y + STEPS[i].y
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				if _revise(wave, cell.x, cell.y, nx, ny, BuildingBlockCatalog.SIDES[i], adjacency):
					queue.append(Vector2i(nx, ny))
			if _has_contradiction(wave):
				return false
	return false


static func _has_contradiction(wave: Array) -> bool:
	for row: Array in wave:
		for opts: Array in row:
			if opts.is_empty():
				return true
	return false


static func _pick_cell(wave: Array, width: int, height: int) -> Vector2i:
	var best := -1
	var at := Vector2i(-1, -1)
	for y in height:
		for x in width:
			var n: int = wave[y][x].size()
			if n <= 1:
				continue
			if best < 0 or n < best or (n == best and (y < at.y or (y == at.y and x < at.x))):
				best = n
				at = Vector2i(x, y)
	return at


static func _revise(
		wave: Array,
		ax: int,
		ay: int,
		bx: int,
		by: int,
		side_on_a: String,
		adjacency: Dictionary,
) -> bool:
	var changed := false
	changed = _filter_toward(wave, ax, ay, bx, by, side_on_a, adjacency) or changed
	var opp: String = BuildingBlockCatalog.OPPOSITE[side_on_a]
	changed = _filter_toward(wave, bx, by, ax, ay, opp, adjacency) or changed
	return changed


static func _filter_toward(
		wave: Array,
		from_x: int,
		from_y: int,
		to_x: int,
		to_y: int,
		side_on_from: String,
		adjacency: Dictionary,
) -> bool:
	var from_opts: Array = wave[from_y][from_x]
	var to_opts: Array = wave[to_y][to_x]
	var keep: Array = []
	for b in to_opts:
		var ok := false
		for a in from_opts:
			if adjacency[a][side_on_from].has(b):
				ok = true
				break
		if ok:
			keep.append(b)
	if keep.size() == to_opts.size():
		return false
	wave[to_y][to_x] = keep
	return true


static func _grid_from_wave(wave: Array) -> Array:
	var out: Array = []
	for row: Array in wave:
		var line: Array[String] = []
		for opts: Array in row:
			line.append(str(opts[0]))
		out.append(line)
	return out