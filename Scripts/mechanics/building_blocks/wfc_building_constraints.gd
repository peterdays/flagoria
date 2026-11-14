class_name WfcBuildingConstraints
extends RefCounted
## Building-shaped WFC: pre-seed the ring/roof band, then reject layouts that fail
## per-cell rules (#25). Each rule is one function for isolated tests.

const MIN_INTERIOR_FLOORS := 4
const BUILDING_SOLVE_ATTEMPTS := 64

const WALL_RING_IDS: Array[String] = [
	"wall_straight", "door", "window",
]
const ROOF_IDS: Array[String] = ["roof_edge", "roof_fill"]
const RING_PIECE_IDS: Array[String] = [
	"wall_straight", "door", "window", "roof_edge", "roof_fill", "wall_corner",
]
const ROOF_ROW := 0

const WALKABLE_IDS: Array[String] = ["floor", "door"]


static func solve_building(
		width: int,
		height: int,
		seed: int,
		pieces: Array = [],
		max_attempts: int = BUILDING_SOLVE_ATTEMPTS,
) -> Dictionary:
	if pieces.is_empty():
		for piece: BuildingBlockPiece in BuildingBlockCatalog.all():
			pieces.append(piece)
	var interior := interior_floor_count(width, height)
	if interior < MIN_INTERIOR_FLOORS:
		return _fail("building %dx%d interior %d < %d" % [
				width, height, interior, MIN_INTERIOR_FLOORS,
		])
	var allowed := build_cell_allowed(width, height)
	for attempt in max_attempts:
		var result := WfcSolver.solve(
				width, height, pieces, seed + attempt * 0x9E3779B9, 1, allowed)
		if not result.ok:
			continue
		var err := validate_all(result.grid)
		if err == "":
			result.attempts = attempt + 1
			return result
	var fail := _fail("no valid building within %d attempts" % max_attempts)
	fail.attempts = max_attempts
	return fail


static func interior_floor_count(width: int, height: int) -> int:
	if width < 3 or height < 3:
		return 0
	return maxi(0, width - 2) * maxi(0, height - 2)


static func door_cell_for_seed(width: int, height: int, seed: int) -> Vector2i:
	var candidates := door_ring_cells(width, height)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func door_ring_cells(width: int, height: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in ring_cells(width, height):
		if is_north_roof_strip(cell.x, cell.y, width, height):
			continue
		out.append(cell)
	return out


static func ring_cells(width: int, height: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in height:
		for x in width:
			if is_ring_cell(x, y, width, height):
				out.append(Vector2i(x, y))
	return out


static func is_ring_cell(x: int, y: int, width: int, height: int) -> bool:
	return x == 0 or y == 0 or x == width - 1 or y == height - 1


static func is_north_roof_strip(x: int, y: int, width: int, height: int) -> bool:
	return y == ROOF_ROW and x > 0 and x < width - 1


static func build_cell_allowed(width: int, height: int) -> Array:
	var allowed: Array = []
	for y in height:
		var row: Array = []
		for x in width:
			if not is_ring_cell(x, y, width, height):
				row.append(["floor"])
			else:
				row.append(RING_PIECE_IDS.duplicate())
		allowed.append(row)
	return allowed


static func validate_all(grid: Array) -> String:
	var checks: Array = [
		rule_outer_ring_walls,
		rule_one_door_on_ring,
		rule_floor_reachable_from_door,
		rule_roof_over_interior,
		rule_min_interior_size,
	]
	for check: Callable in checks:
		var err: String = check.call(grid)
		if err != "":
			return err
	return ""


static func rule_outer_ring_walls(grid: Array) -> String:
	var h := grid.size()
	if h == 0:
		return "empty grid"
	var w: int = grid[0].size()
	for y in h:
		for x in w:
			var id: String = grid[y][x]
			if is_ring_cell(x, y, w, h):
				if id not in RING_PIECE_IDS:
					return "ring %d,%d is %s" % [x, y, id]
			elif id != "floor":
				return "interior %d,%d is %s" % [x, y, id]
	return ""


static func rule_one_door_on_ring(grid: Array) -> String:
	var h := grid.size()
	if h == 0:
		return "empty grid"
	var w: int = grid[0].size()
	var count := 0
	for y in h:
		for x in w:
			if grid[y][x] == "door" and is_ring_cell(x, y, w, h):
				count += 1
	if count != 1:
		return "door count on ring %d" % count
	return ""


static func rule_floor_reachable_from_door(grid: Array) -> String:
	var h := grid.size()
	if h == 0:
		return "empty grid"
	var w: int = grid[0].size()
	var start := Vector2i(-1, -1)
	for y in h:
		for x in w:
			if grid[y][x] == "door":
				start = Vector2i(x, y)
				break
		if start.x >= 0:
			break
	if start.x < 0:
		return "no door"
	var seen := {}
	seen[start] = true
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in WfcSolver.STEPS:
			var nx: int = cell.x + step.x
			var ny: int = cell.y + step.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var at := Vector2i(nx, ny)
			if seen.has(at):
				continue
			var id: String = grid[ny][nx]
			if id not in WALKABLE_IDS:
				continue
			seen[at] = true
			queue.append(at)
	for y in h:
		for x in w:
			if grid[y][x] == "floor" and not seen.has(Vector2i(x, y)):
				return "floor %d,%d unreachable" % [x, y]
	return ""


static func rule_roof_over_interior(grid: Array) -> String:
	var h := grid.size()
	if h == 0:
		return "empty grid"
	var w: int = grid[0].size()
	for x in range(1, w - 1):
		var column_has_floor := false
		for y in range(1, h):
			if grid[y][x] == "floor":
				column_has_floor = true
				break
		if not column_has_floor:
			continue
		var has_roof := false
		for y in h:
			if grid[y][x] in ROOF_IDS:
				has_roof = true
				break
		if not has_roof:
			return "column %d missing roof" % x
	return ""


static func rule_min_interior_size(grid: Array) -> String:
	var h := grid.size()
	if h == 0:
		return "empty grid"
	var w: int = grid[0].size()
	var count := 0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if grid[y][x] == "floor":
				count += 1
	if count < MIN_INTERIOR_FLOORS:
		return "interior floor count %d < %d" % [count, MIN_INTERIOR_FLOORS]
	return ""


static func _fail(message: String, attempts: int = 0) -> Dictionary:
	return {"ok": false, "error": message, "attempts": attempts}