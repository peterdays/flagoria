class_name ConstructionPlacer
extends RefCounted
## Shared construction placement (#296): one API for every buildable kind.
## Checks, wood cost and the writer live here so bridges, walls and towers
## share the same path. The plank bridge is the first kind; walls (#276) and
## towers (#273) register as more kinds later. The placement UI (#225) only
## talks to this module.
## Host-alone first: while multiplayer is on nothing is placed (same gate as
## BuildCosts and StructurePlacer). Peer sync of placed blocks is #297.

const _WorldMap := preload("res://Scripts/TileMap.gd")

const WRONG_GROUND := "wrong ground"
const OCCUPIED := "occupied"
const NOT_ADJACENT := "not adjacent"
const NOT_STRAIGHT := "not straight"
const EMPTY_CELLS := "empty cells"
const NOT_ENOUGH_WOOD := BuildCosts.NOT_ENOUGH_WOOD
const MULTIPLAYER_ON := BuildCosts.MULTIPLAYER_ON
const UNKNOWN_KIND := BuildCosts.UNKNOWN_KIND

## Kinds this module can place. Each entry is one rule set; a new buildable
## adds a line here and a `_check_<kind>` / `_write_<kind>` pair.
const KINDS := {
	BuildCosts.PLANK: true,
}

const _REASON_ORDER := [
	EMPTY_CELLS, UNKNOWN_KIND, WRONG_GROUND, OCCUPIED, NOT_STRAIGHT, NOT_ADJACENT,
	NOT_ENOUGH_WOOD, MULTIPLAYER_ON,
]

var _map: _WorldMap


func _init(map: _WorldMap) -> void:
	_map = map


func can_place(kind: StringName, cells: Array[Vector2i], inventory: Inventory) -> Array[String]:
	## Why `kind` cannot go on `cells`; empty when it can. Each reason appears
	## once, in `_REASON_ORDER`. Wood and multiplayer come from BuildCosts.
	var found := {}
	if cells.is_empty():
		found[EMPTY_CELLS] = true
	if not KINDS.has(kind):
		found[UNKNOWN_KIND] = true
	else:
		match kind:
			BuildCosts.PLANK:
				_check_plank(cells, found)
	if not cells.is_empty() and KINDS.has(kind):
		var why := BuildCosts.refusal(inventory, kind, cells.size())
		if why != "":
			found[why] = true
	return _ordered(found)


func cost(kind: StringName, cells: Array) -> int:
	## Wood for placing `kind` on every cell in `cells`; -1 for an unknown kind.
	return BuildCosts.cost(kind, cells.size())


func place(kind: StringName, cells: Array[Vector2i], inventory: Inventory) -> bool:
	## Check, then buy through BuildCosts (spend then writer). True only when
	## the cells are written and the wood is taken. A refusal or a failed
	## charge writes nothing; a writer refusal puts the wood back (#380).
	if not can_place(kind, cells, inventory).is_empty():
		return false
	match kind:
		BuildCosts.PLANK:
			return _place_plank(cells, inventory)
	return false


func _place_plank(cells: Array[Vector2i], inventory: Inventory) -> bool:
	var ends := _straight_ends(cells)
	if ends.is_empty():
		return false
	var from: Vector2i = ends[0]
	var to: Vector2i = ends[1]
	var why := BuildCosts.buy(inventory, BuildCosts.PLANK, cells.size(), func() -> bool:
		return _map.build_bridge(from, to))
	return why == ""


func _check_plank(cells: Array[Vector2i], found: Dictionary) -> void:
	if cells.is_empty():
		return
	for cell in cells:
		if _map.has_bridge(cell):
			found[OCCUPIED] = true
		elif _map.predict_cell(cell)[0] != TileCatalog.WATER:
			found[WRONG_GROUND] = true
	if _straight_ends(cells).is_empty():
		found[NOT_STRAIGHT] = true
	elif not _run_touches_support(cells):
		found[NOT_ADJACENT] = true


func _run_touches_support(cells: Array[Vector2i]) -> bool:
	## True when at least one cell in the run touches land or an existing plank
	## (4-neighbour). A floating run over open water is refused (#296 update
	## 2026-11-02): no floating planks.
	for cell in cells:
		for n in _neighbours(cell):
			if _map.has_bridge(n) or _is_land(n):
				return true
	return false


func _is_land(cell: Vector2i) -> bool:
	## Walkable generated ground that is not already a plank.
	return not _map.has_bridge(cell) \
			and _map.ground_is_walkable(_map.predict_cell(cell)[0])


func _straight_ends(cells: Array[Vector2i]) -> Array[Vector2i]:
	## `[from, to]` for one contiguous axis-aligned run, or empty when the
	## cells are bent, gapped or duplicated. One cell is a run of itself.
	if cells.is_empty():
		return []
	var seen := {}
	for c in cells:
		if seen.has(c):
			return []
		seen[c] = true
	if cells.size() == 1:
		return [cells[0], cells[0]]
	var xs := {}
	var ys := {}
	for c in cells:
		xs[c.x] = true
		ys[c.y] = true
	var horizontal := ys.size() == 1 and xs.size() == cells.size()
	var vertical := xs.size() == 1 and ys.size() == cells.size()
	if not horizontal and not vertical:
		return []
	var ordered: Array[Vector2i] = cells.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if horizontal else a.y < b.y)
	var step := Vector2i.RIGHT if horizontal else Vector2i.DOWN
	for i in range(1, ordered.size()):
		if ordered[i] != ordered[0] + step * i:
			return []
	return [ordered[0], ordered[ordered.size() - 1]]


static func _neighbours(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.LEFT, cell + Vector2i.RIGHT,
		cell + Vector2i.UP, cell + Vector2i.DOWN,
	]


static func _ordered(found: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for reason in _REASON_ORDER:
		if found.has(reason):
			out.append(reason)
	return out
