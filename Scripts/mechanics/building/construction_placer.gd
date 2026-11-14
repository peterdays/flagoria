class_name ConstructionPlacer
extends RefCounted
## Shared construction placement (#296): one API for every buildable kind.
## Checks, wood cost and the writer live here so bridges, walls and towers
## share the same path. Plank bridges, wooden towers (#273) and free-form
## wall blocks (#276) are registered. The placement UI (#225) only talks to
## this module.
## Plank bridges sync between peers (#297). Towers and free-form walls ask
## the host through StructureRequests (#497, #498).

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
	BuildCosts.TOWER: true,
	BuildCosts.CASTLE: true,
	BuildCosts.WALL_BLOCK: true,
}

const TOWER_STRUCTURE := "tower_wood"
const CASTLE_STRUCTURE := "castle"

const _REASON_ORDER := [
	EMPTY_CELLS, UNKNOWN_KIND, WRONG_GROUND, OCCUPIED, NOT_STRAIGHT, NOT_ADJACENT,
	NOT_ENOUGH_WOOD, MULTIPLAYER_ON,
]

var _map: _WorldMap
## The shipped tower definition is read-only and unchanged during play.
## Load once per placer, not once per footprint / preview check (#386).
var _tower: Structure
var _tower_loaded := false
var _castle: Structure
var _castle_loaded := false


func _init(map: _WorldMap) -> void:
	_map = map


func can_place(kind: StringName, cells: Array[Vector2i], inventory: Inventory, quarter_turns: int = 0) -> Array[String]:
	## Why `kind` cannot go on `cells`; empty when it can. Each reason appears
	## once, in `_REASON_ORDER`. Wood and multiplayer come from BuildCosts.
	## A tower takes exactly one cell (its anchor); a plank or wall run takes
	## every cell in `cells`.
	var found := {}
	if cells.is_empty():
		found[EMPTY_CELLS] = true
	if not KINDS.has(kind):
		found[UNKNOWN_KIND] = true
	else:
		match kind:
			BuildCosts.PLANK:
				_check_plank(cells, found)
			BuildCosts.TOWER:
				_check_tower(cells, found, quarter_turns)
			BuildCosts.CASTLE:
				_check_castle(cells, found, quarter_turns)
			BuildCosts.WALL_BLOCK:
				_check_wall(cells, found)
	if not cells.is_empty() and KINDS.has(kind):
		var units := _units(kind, cells)
		var why := BuildCosts.refusal(inventory, kind, units)
		if why != "":
			found[why] = true
	return _ordered(found)


func can_place_geometry(kind: StringName, cells: Array[Vector2i], quarter_turns: int = 0) -> Array[String]:
	## Why `kind` cannot go on `cells` from the map alone (no wood, no
	## multiplayer gate). The host uses this to check a peer's request (#297).
	var found := {}
	if cells.is_empty():
		found[EMPTY_CELLS] = true
	if not KINDS.has(kind):
		found[UNKNOWN_KIND] = true
	else:
		match kind:
			BuildCosts.PLANK:
				_check_plank(cells, found)
			BuildCosts.TOWER:
				_check_tower(cells, found, quarter_turns)
			BuildCosts.CASTLE:
				_check_castle(cells, found, quarter_turns)
			BuildCosts.WALL_BLOCK:
				_check_wall(cells, found)
	return _ordered(found)


func plank_ends(cells: Array[Vector2i]) -> Array[Vector2i]:
	## `[from, to]` for a straight contiguous run, or empty when bent.
	return _straight_ends(cells)


func write_plank(cells: Array[Vector2i]) -> Array[Vector2i]:
	## Write a plank run with no wood spend. Returns `[from, to]` when written,
	## or empty when geometry refuses or the writer fails. Used by the host
	## when placing for a remote peer (#297).
	if not can_place_geometry(BuildCosts.PLANK, cells).is_empty():
		return []
	var ends := _straight_ends(cells)
	if ends.is_empty() or not _map.build_bridge(ends[0], ends[1]):
		return []
	return ends


func write_wall(cells: Array[Vector2i]) -> bool:
	## Write a free-form run with no wood spend. False when geometry refuses.
	## The host uses this for a peer's wall request (#498).
	if not can_place_geometry(BuildCosts.WALL_BLOCK, cells).is_empty():
		return false
	return _map.place_wall_cells(cells)


func write_castle(anchor: Vector2i, owner: int, quarter_turns: int = 0) -> int:
	## Write one castle for `owner` with no wood spend. Returns the placement
	## id, or -1 when the footprint refuses or the write fails.
	var one: Array[Vector2i] = [anchor]
	if not can_place_geometry(BuildCosts.CASTLE, one, quarter_turns).is_empty():
		return -1
	var structure := _load_castle()
	if structure == null:
		return -1
	return _map._structures.place_from_host(structure, anchor, owner, quarter_turns)


func write_tower(anchor: Vector2i, owner: int, quarter_turns: int = 0) -> int:
	## Write one wooden tower for `owner` with no wood spend. Returns the
	## placement id, or -1 when the footprint refuses or the write fails.
	## The host uses this for a peer's request (#497). The multiplayer refuse
	## on StructurePlacer.can_place is not a footprint failure.
	var one: Array[Vector2i] = [anchor]
	if not can_place_geometry(BuildCosts.TOWER, one, quarter_turns).is_empty():
		return -1
	var structure := _load_tower()
	if structure == null:
		return -1
	return _map._structures.place_from_host(structure, anchor, owner, quarter_turns)


func cost(kind: StringName, cells: Array) -> int:
	## Wood for placing `kind` on `cells`; -1 for an unknown kind. A tower is
	## always one unit (10 wood) regardless of footprint size; a wall block is
	## one unit per cell (2 wood each).
	if not KINDS.has(kind) and not BuildCosts.WOOD.has(kind):
		return -1
	return BuildCosts.cost(kind, _units(kind, cells))


func place(kind: StringName, cells: Array[Vector2i], inventory: Inventory, quarter_turns: int = 0) -> bool:
	## Check, then buy through BuildCosts (spend then writer). True only when
	## the cells are written and the wood is taken. A refusal or a failed
	## charge writes nothing; a writer refusal puts the wood back (#380).
	if not can_place(kind, cells, inventory, quarter_turns).is_empty():
		return false
	match kind:
		BuildCosts.PLANK:
			return _place_plank(cells, inventory)
		BuildCosts.TOWER:
			return _place_tower(cells, inventory, quarter_turns)
		BuildCosts.CASTLE:
			return _place_castle(cells, inventory, quarter_turns)
		BuildCosts.WALL_BLOCK:
			return _place_wall(cells, inventory)
	return false


func _load_tower() -> Structure:
	if not _tower_loaded:
		_tower = StructurePlacer.load_named(TOWER_STRUCTURE)
		_tower_loaded = true
	return _tower


func _load_castle() -> Structure:
	if not _castle_loaded:
		_castle = StructurePlacer.load_named(CASTLE_STRUCTURE)
		_castle_loaded = true
	return _castle


func tower_footprint(anchor_cell: Vector2i, quarter_turns: int = 0) -> Array[Vector2i]:
	## Map cells the wooden tower would cover with its anchor on `anchor_cell`.
	var structure := _load_tower()
	if structure == null:
		return []
	structure = Structure.rotated(structure, quarter_turns)
	var out: Array[Vector2i] = []
	for cell: Vector2i in StructurePlacer.footprint(structure, anchor_cell):
		out.append(cell)
	return out


func castle_footprint(anchor_cell: Vector2i, quarter_turns: int = 0) -> Array[Vector2i]:
	## Map cells an extra castle would cover with its anchor on `anchor_cell`.
	var structure := _load_castle()
	if structure == null:
		return []
	structure = Structure.rotated(structure, quarter_turns)
	var out: Array[Vector2i] = []
	for cell: Vector2i in StructurePlacer.footprint(structure, anchor_cell):
		out.append(cell)
	return out


func _units(kind: StringName, cells: Array) -> int:
	return 1 if kind == BuildCosts.TOWER or kind == BuildCosts.CASTLE else cells.size()


func _place_wall(cells: Array[Vector2i], inventory: Inventory) -> bool:
	## Spend 2 wood per cell, then WallBuilder writes plain palisade pieces.
	## With peers connected, StructureRequests asks the host instead of writing.
	if Interaction.multiplayer_on(_map.multiplayer):
		var requests := _map.get_node_or_null("../StructureRequests")
		return requests != null and requests.place(BuildCosts.WALL_BLOCK, cells)
	var why := BuildCosts.buy(inventory, BuildCosts.WALL_BLOCK, cells.size(), func() -> bool:
		return _map.place_wall_cells(cells))
	return why == ""


func _check_wall(cells: Array[Vector2i], found: Dictionary) -> void:
	## Land only; refuse structures, existing walls, players, mobs, trees and
	## bushes. A multi-cell run must be one contiguous H/V segment (no gaps,
	## no bends). Every placement must 4-touch an existing wall, tower or
	## castle so the first block cannot float free (design decision for #276);
	## tip adjacency is still enforced by BuildPlacement before place.
	if cells.is_empty():
		return
	if cells.size() > 1 and _straight_ends(cells).is_empty():
		found[NOT_STRAIGHT] = true
	if not _run_touches_wall_or_structure(cells):
		found[NOT_ADJACENT] = true
	for cell in cells:
		if _map.has_wall(cell) or _map._structures.has_cell(cell):
			found[OCCUPIED] = true
			continue
		var p: Array = _map.predict_cell(cell)
		if not _map.ground_is_walkable(p[0]) or _map.has_bridge(cell):
			found[WRONG_GROUND] = true
			continue
		if p[1] == TileCatalog.TREE or p[1] == TileCatalog.TREE_BUSHY \
			or p[1] == TileCatalog.PINE or p[1] == TileCatalog.BUSH:
			found[OCCUPIED] = true
		elif _map.player_on_cell(cell) or _map.mob_on_cell(cell):
			found[OCCUPIED] = true


func _place_plank(cells: Array[Vector2i], inventory: Inventory) -> bool:
	var ends := _straight_ends(cells)
	if ends.is_empty():
		return false
	var from: Vector2i = ends[0]
	var to: Vector2i = ends[1]
	var why := BuildCosts.buy(inventory, BuildCosts.PLANK, cells.size(), func() -> bool:
		return _map.build_bridge(from, to))
	return why == ""


func _place_castle(cells: Array[Vector2i], inventory: Inventory, quarter_turns: int = 0) -> bool:
	## One castle: spend 50 wood, then StructurePlacer writes structures/castle
	## owned by the local peer (#527). With peers connected, StructureRequests
	## asks the host instead of writing here.
	if cells.size() != 1:
		return false
	if Interaction.multiplayer_on(_map.multiplayer):
		var requests := _map.get_node_or_null("../StructureRequests")
		return requests != null and requests.place(BuildCosts.CASTLE, cells, quarter_turns)
	var structure := _load_castle()
	if structure == null:
		return false
	var anchor: Vector2i = cells[0]
	var owner := inventory.multiplayer.get_unique_id()
	var turns := quarter_turns
	var why := BuildCosts.buy(inventory, BuildCosts.CASTLE, 1, func() -> bool:
		return _map.place_structure(structure, anchor, owner, turns) > 0)
	return why == ""


func _place_tower(cells: Array[Vector2i], inventory: Inventory, quarter_turns: int = 0) -> bool:
	## One tower: spend 10 wood, then StructurePlacer writes tower_wood owned
	## by the local peer so TowerCapture can take it (#274). With peers
	## connected, StructureRequests asks the host instead of writing here.
	if cells.size() != 1:
		return false
	if Interaction.multiplayer_on(_map.multiplayer):
		var requests := _map.get_node_or_null("../StructureRequests")
		return requests != null and requests.place(BuildCosts.TOWER, cells, quarter_turns)
	var structure := _load_tower()
	if structure == null:
		return false
	var anchor: Vector2i = cells[0]
	var owner := inventory.multiplayer.get_unique_id()
	var turns := quarter_turns
	var why := BuildCosts.buy(inventory, BuildCosts.TOWER, 1, func() -> bool:
		return _map.place_structure(structure, anchor, owner, turns) > 0)
	return why == ""


func _check_plank(cells: Array[Vector2i], found: Dictionary) -> void:
	## Water only; an existing plank, wall or structure cell, or a player or
	## mob overlapping a cell, is occupied (#380 item 2).
	if cells.is_empty():
		return
	for cell in cells:
		if _map.has_bridge(cell) or _map.has_wall(cell) or _map._structures.has_cell(cell):
			found[OCCUPIED] = true
		elif _map.predict_cell(cell)[0] != TileCatalog.WATER:
			found[WRONG_GROUND] = true
		elif _map.player_on_cell(cell) or _map.mob_on_cell(cell):
			found[OCCUPIED] = true
	if _straight_ends(cells).is_empty():
		found[NOT_STRAIGHT] = true
	elif not _run_touches_support(cells):
		found[NOT_ADJACENT] = true


func _check_castle(cells: Array[Vector2i], found: Dictionary, quarter_turns: int = 0) -> void:
	if cells.size() != 1:
		found[EMPTY_CELLS] = true
		return
	var structure := _load_castle()
	if structure == null:
		found[UNKNOWN_KIND] = true
		return
	for reason in _map.can_place_structure(structure, cells[0], quarter_turns):
		if reason == StructurePlacer.MULTIPLAYER_ON:
			continue
		match reason:
			StructurePlacer.WATER, StructurePlacer.OUT_OF_MAP:
				found[WRONG_GROUND] = true
			StructurePlacer.TREE, StructurePlacer.BUSH, \
			StructurePlacer.OVERLAPS_STRUCTURE, StructurePlacer.OVERLAPS_PLAYER, \
			StructurePlacer.OVERLAPS_MOB:
				found[OCCUPIED] = true
			StructurePlacer.MULTIPLAYER_ON:
				found[MULTIPLAYER_ON] = true


func _check_tower(cells: Array[Vector2i], found: Dictionary, quarter_turns: int = 0) -> void:
	## Anchor must be exactly one cell; StructurePlacer reasons map onto the
	## shared vocabulary (land only, no overlap with structures/players/mobs).
	if cells.size() != 1:
		found[EMPTY_CELLS] = true
		return
	var structure := _load_tower()
	if structure == null:
		found[UNKNOWN_KIND] = true
		return
	for reason in _map.can_place_structure(structure, cells[0], quarter_turns):
		if reason == StructurePlacer.MULTIPLAYER_ON:
			continue  # StructureRequests is the multiplayer gate (#497).
		match reason:
			StructurePlacer.WATER, StructurePlacer.OUT_OF_MAP:
				found[WRONG_GROUND] = true
			StructurePlacer.TREE, StructurePlacer.BUSH, \
			StructurePlacer.OVERLAPS_STRUCTURE, StructurePlacer.OVERLAPS_PLAYER, \
			StructurePlacer.OVERLAPS_MOB:
				found[OCCUPIED] = true
			StructurePlacer.MULTIPLAYER_ON:
				found[MULTIPLAYER_ON] = true



func _run_touches_wall_or_structure(cells: Array[Vector2i]) -> bool:
	## True when at least one cell in the run 4-touches an existing wall or
	## structure (tower / castle). Used so the first wall block cannot float.
	for cell in cells:
		for n in _neighbours(cell):
			if _map.has_wall(n) or _map._structures.has_cell(n):
				return true
	return false


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
