class_name TreeSprouts
extends RefCounted
## Trees that sprout on free cells (#361). Where the area around a player
## holds fewer trees of a biome than BiomeCatalog.TREE_SHARE asks for, and
## fewer than the map generates there, a tree grows on a free cell of that
## biome. A stump still counts as its tree, since it regrows (TreeCuts), so
## only trees gone for good (a structure built on their stumps) are made up
## for, and an untouched area never gets more trees than it generates.
## The host decides (due); a client adds the host's sprouts (add, through
## Interaction.apply_sprout_cells). Saves and joining peers get them in the
## cut list (TreeCuts.to_changes, "sprout" entries).

const _WorldMap := preload("res://Scripts/TileMap.gd")

## Seconds of play between two sprout passes on the host. Each pass, each
## missing tree sprouts with chance PASS_SECONDS / regrow delay, so a
## missing tree takes about one regrow delay to come back, like a stump.
const PASS_SECONDS := 5.0
const TREES: Array[Vector2i] = [TileCatalog.TREE, TileCatalog.TREE_BUSHY, TileCatalog.PINE]
## Side of the area around each player that a pass counts, in chunks: the
## player's chunk and its neighbours. One chunk is smaller than a forest
## patch, so a thinned biome would refill only where it was sparse.
const AREA_CHUNKS := 3
## Side, in cells, of the squares the untouched map is counted in
## (_block_table). Small, so a window off the square grid builds few cells
## it does not use (an area of 96 x 96 cells overlaps 13 x 13 squares).
const BLOCK := 8
## Most squares whose counts are kept (the area of 256 chunks); past it they
## are all dropped and built again as needed.
const MAX_BLOCK_TABLES := 4096

## Sprouted cell -> its tree atlas (sprout_tile).
var _sprouts: Dictionary = {}
var _next_pass := 0.0
var _rng := RandomNumberGenerator.new()
var _map: _WorldMap
## Square -> _block_table of the untouched map, for deficits.
var _tables: Dictionary = {}
## Cell -> _untouched(cell), for the changed cells deficits counts.
var _natural_at: Dictionary = {}
## Ground atlas -> TileMap.ground_is_walkable.
var _walkable_ground: Dictionary = {}


func _init(map: _WorldMap) -> void:
	_map = map


func has(cell: Vector2i) -> bool:
	return _sprouts.has(cell)


func tile_or(cell: Vector2i, fallback: Vector2i) -> Vector2i:
	## The sprouted tree on `cell`, or `fallback` (what the map puts there).
	return _sprouts.get(cell, fallback)


func size() -> int:
	return _sprouts.size()


func clear() -> void:
	_sprouts.clear()
	_tables.clear()
	_natural_at.clear()
	_next_pass = 0.0


func erase(cell: Vector2i) -> void:
	## Drop the sprout on `cell` (a structure now covers it), undrawn.
	_sprouts.erase(cell)


func sprout_tile(cell: Vector2i) -> Vector2i:
	## The tree the map would grow on `cell` at the highest items chance:
	## TREE, TREE_BUSHY or PINE, or NO_PLANT when it grows no tree there.
	var b := _map.biome_at(cell)
	var tile := _map.plant_tile(_map.cell_altitude(cell, b), _map.moisture.get_noise_2d(cell.x, cell.y), 1.0, b)
	return tile if tile in TREES else _WorldMap.NO_PLANT


func can_sprout(cell: Vector2i, blocked: Dictionary) -> Vector2i:
	## The tree that may sprout on `cell` now, or NO_PLANT: the ground is
	## walkable (not water) and not a beach with biomes on, there is no
	## structure, bridge, plant, stump or stones on it, it is not in
	## `blocked` (blocked_cells: under a mob or player, the spawn, the start
	## castle's gate), and the map grows a tree there (sprout_tile). The
	## cheap checks go first.
	var p := _map.predict_cell(cell)
	if p[1] != _WorldMap.NO_PLANT or blocked.has(cell):
		return _WorldMap.NO_PLANT
	if _map._structures.has_cell(cell) or _map._bridges.has_bridge(cell):
		return _WorldMap.NO_PLANT
	if not _walkable(p[0]) or (_map.biome_frequency > 0.0 and p[0] == TileCatalog.SAND):
		return _WorldMap.NO_PLANT
	return sprout_tile(cell)


func blocked_cells() -> Dictionary:
	## The cells no tree may sprout on now (cell -> true), gathered once per
	## pass: under a mob's feet (TileMap.mob_cells) or a player's body box
	## (the cells TileMap.player_on_cell is true for), the spawn cell, and the
	## start castle's gate cell and the cell outside it (StartCastle).
	var out := _map.mob_cells()
	for node in _map.get_parent().get_children():
		var body := node.get_node_or_null("CollisionShape2D") as CollisionShape2D if node is CharacterBody2D else null
		if body and body.shape:
			_add_player_cells(body.global_transform * body.shape.get_rect(), out)
	out[_map.spawn_point] = true
	if _map._castle_front != null:
		out[_map._castle_front] = true
		out[_map._castle_front - StartCastle.GATE_FRONT] = true
	return out


func _add_player_cells(box: Rect2, out: Dictionary) -> void:
	## The cells whose rect (as in TileMap.player_on_cell) overlaps `box`.
	var a := _map.local_to_map(_map.to_local(box.position))
	var z := _map.local_to_map(_map.to_local(box.end))
	for y in range(mini(a.y, z.y) - 1, maxi(a.y, z.y) + 2):
		for x in range(mini(a.x, z.x) - 1, maxi(a.x, z.x) + 2):
			var cell := Vector2i(x, y)
			var rect := Rect2(_map.to_global(_map.map_to_local(cell) - Vector2(8, 8)), Vector2(16, 16) * _map.global_scale)
			if box.intersects(rect):
				out[cell] = true


func _walkable(ground: Vector2i) -> bool:
	## TileMap.ground_is_walkable, kept per ground tile (the tile set is fixed).
	if not _walkable_ground.has(ground):
		_walkable_ground[ground] = _map.ground_is_walkable(ground)
	return _walkable_ground[ground]


func add(cell: Vector2i) -> bool:
	## Sprout sprout_tile(cell) on `cell`, drawn or not. A client applies the
	## host's sprouts this way, without the host's checks. False when the
	## cell has a sprout already or the map grows no tree there.
	var tile := sprout_tile(cell)
	if tile == _WorldMap.NO_PLANT or _sprouts.has(cell):
		return false
	_sprouts[cell] = tile
	_map._predict_cache.erase(cell)
	if _map.get_cell_source_id(0, cell) != -1 and not _map._tree_cuts.has_cut(cell):
		_map.set_cell(1, cell, TileCatalog.SOURCE_ID, tile)
	return true


func deficits(window: Rect2i) -> Dictionary:
	## Biome id -> trees missing in `window`: the smaller of TREE_SHARE of its
	## land cells (rounded down) and the trees the map generates there
	## (counting cells under structures), less the trees, sprouts and tree
	## stumps it holds. Only biomes missing at least one are listed.
	## Counted without visiting every cell: the untouched map's counts come
	## from per-square tables (_block_table), and only the cells something
	## changed (a cut, sprout, structure or bridge) are counted one by one
	## (_count_cell) in place of their untouched counts.
	var land := {}
	var grown := {}
	_static_counts(window, land, grown)
	var now := grown.duplicate()
	var changed := {}
	for cells: Dictionary in [_map._tree_cuts._cut_cells, _sprouts, _map._structures._cells, _map._bridges._bridge_cells]:
		for cell: Vector2i in cells:
			if window.has_point(cell):
				changed[cell] = true
	for cell: Vector2i in changed:
		var n := _natural(cell)
		if n[1]:
			land[n[0]] -= 1
		if n[2]:
			grown[n[0]] -= 1
			now[n[0]] -= 1
		_count_cell(cell, land, grown, now)
	var out := {}
	for b in land:
		var missing: int = mini(floori(BiomeCatalog.tree_share(b) * land[b]), grown.get(b, 0)) - now.get(b, 0)
		if missing > 0:
			out[b] = missing
	return out


func _count_cell(cell: Vector2i, land: Dictionary, grown: Dictionary, now: Dictionary) -> void:
	## Add `cell` as the map holds it now to the per-biome counts of deficits:
	## land (not water or a bridge), trees, sprouts and tree stumps on it
	## (now), and whether the generated map has a tree there (grown).
	var p := _map.predict_cell(cell)
	if p[0] == TileCatalog.WATER or _map._bridges.has_bridge(cell):
		return
	var b := _map.biome_at(cell)
	land[b] = land.get(b, 0) + 1
	var stump := _map._tree_cuts.has_cut(cell) and _map._tree_cuts.cut_type(cell).id != "bush"
	if p[1] in TREES or stump:
		now[b] = now.get(b, 0) + 1
	if _generated_tree(cell, p, stump):
		grown[b] = grown.get(b, 0) + 1


func _natural(cell: Vector2i) -> Array:
	## _untouched(cell), kept per cell (only changed cells ask, so few).
	if not _natural_at.has(cell):
		_natural_at[cell] = _untouched(cell)
	return _natural_at[cell]


func _untouched(cell: Vector2i) -> Array:
	## [biome, land, tree] of `cell` on the untouched map (no cuts, sprouts,
	## structures or bridges): what _count_cell adds for it there.
	var b := _map.biome_at(cell)
	var alt := _map.cell_altitude(cell, b)
	var moist := _map.moisture.get_noise_2d(cell.x, cell.y)
	var chance := _map.items_chance.get_noise_2d(cell.x, cell.y)
	var ground := _map.ground_tile(alt, moist, chance, b)
	var tree := _walkable(ground) and (_map.biome_frequency <= 0.0 or ground != TileCatalog.SAND) \
			and _map.plant_tile(alt, moist, chance, b) in TREES
	return [b, ground != TileCatalog.WATER, tree]


func _static_counts(window: Rect2i, land: Dictionary, grown: Dictionary) -> void:
	## Add the untouched map's land and tree cells in `window` per biome, from
	## the summed-area tables of the squares it overlaps.
	const W := BLOCK + 1
	var first := Vector2i(floori(window.position.x / float(BLOCK)), floori(window.position.y / float(BLOCK)))
	var last := Vector2i(floori((window.end.x - 1) / float(BLOCK)), floori((window.end.y - 1) / float(BLOCK)))
	for by in range(first.y, last.y + 1):
		for bx in range(first.x, last.x + 1):
			var origin := Vector2i(bx, by) * BLOCK
			var part := window.intersection(Rect2i(origin, Vector2i(BLOCK, BLOCK)))
			if not part.has_area():
				continue
			var a := part.position - origin
			var z := part.end - origin
			var tables := _block_table(Vector2i(bx, by))
			for b in tables:
				var t: PackedInt32Array = tables[b]
				for k in 2:
					var n: int = t[(z.y * W + z.x) * 2 + k] - t[(a.y * W + z.x) * 2 + k] \
							- t[(z.y * W + a.x) * 2 + k] + t[(a.y * W + a.x) * 2 + k]
					var out := land if k == 0 else grown
					out[b] = out.get(b, 0) + n


func _block_table(square: Vector2i) -> Dictionary:
	## Biome id -> summed-area table of the BLOCK x BLOCK cells from
	## square * BLOCK on the untouched map: entry (y * (BLOCK + 1) + x) * 2
	## counts the land cells above and left of local (x, y), the next entry
	## the tree cells. Built once per square and kept until the map params
	## change (clear); at most MAX_BLOCK_TABLES.
	if _tables.has(square):
		return _tables[square]
	if _tables.size() >= MAX_BLOCK_TABLES:
		_tables.clear()
	const W := BLOCK + 1
	var cells := []
	var biomes := {}
	for y in BLOCK:
		for x in BLOCK:
			var n := _untouched(square * BLOCK + Vector2i(x, y))
			cells.append(n)
			biomes[n[0]] = true
	var tables := {}
	for b in biomes:
		var t := PackedInt32Array()
		t.resize(W * W * 2)
		for y in BLOCK:
			for x in BLOCK:
				var n: Array = cells[y * BLOCK + x]
				var at := ((y + 1) * W + x + 1) * 2
				for k in 2:
					var v := 1 if n[0] == b and n[k + 1] else 0
					t[at + k] = v + t[at + k - 2] + t[at + k - W * 2] - t[at + k - (W + 1) * 2]
		tables[b] = t
	_tables[square] = tables
	return tables


func _generated_tree(cell: Vector2i, p: Array, stump: bool) -> bool:
	## True when the generated map (no cuts, sprouts or structures) has a
	## tree on `cell`.
	if _sprouts.has(cell):
		return false
	if not _map._structures.has_cell(cell):
		return stump or (p[1] in TREES and not _map._tree_cuts.has_cut(cell))
	return _natural(cell)[2]


func candidates(window: Rect2i) -> Dictionary:
	## Biome id -> every cell in `window` where a tree may sprout now
	## (can_sprout), in row order. sprout_pass looks lazily instead
	## (_pick_free); this full list is for checks.
	var blocked := blocked_cells()
	var out := {}
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var cell := Vector2i(x, y)
			if can_sprout(cell, blocked) != _WorldMap.NO_PLANT:
				var b := _map.biome_at(cell)
				if not out.has(b):
					out[b] = []
				out[b].append(cell)
	return out


func sprout_pass(window: Rect2i, chance: float, blocked: Variant = null) -> Array[Vector2i]:
	## For each tree `window` is missing (deficits), sprout one with
	## probability `chance` on a random free cell of that biome (_pick_free,
	## with `blocked`, blocked_cells when null). Returns the cells that
	## sprouted.
	var out: Array[Vector2i] = []
	var missing := deficits(window)
	var want := {}
	for b in missing:
		var n := 0
		for i in missing[b]:
			if _rng.randf() < chance:
				n += 1
		if n > 0:
			want[b] = n
	if want.is_empty():
		return out
	for cell in _pick_free(window, want, blocked_cells() if blocked == null else blocked):
		if add(cell):
			out.append(cell)
	return out


func _pick_free(window: Rect2i, want: Dictionary, blocked: Dictionary) -> Array[Vector2i]:
	## Up to want[b] cells of each biome b in `window` where a tree may
	## sprout (can_sprout), looked at in a random order (a random start and a
	## random step coprime to the cell count, so each cell comes once) until
	## every want is met. `want` is used up.
	var out: Array[Vector2i] = []
	var count := window.size.x * window.size.y
	if count <= 0:
		return out
	var step := _rng.randi_range(1, count)
	while _gcd(step, count) != 1:
		step += 1
	var i := _rng.randi_range(0, count - 1)
	for k in count:
		var cell := window.position + Vector2i(i % window.size.x, i / window.size.x)
		i = (i + step) % count
		if _map.predict_cell(cell)[1] != _WorldMap.NO_PLANT:
			continue
		var b := _map.biome_at(cell)
		if want.get(b, 0) > 0 and can_sprout(cell, blocked) != _WorldMap.NO_PLANT:
			out.append(cell)
			want[b] -= 1
			if want[b] == 0:
				want.erase(b)
				if want.is_empty():
					break
	return out


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return a


func due() -> Array[Vector2i]:
	## Host (or alone): every PASS_SECONDS of play, one sprout_pass on the
	## AREA_CHUNKS area around each player, with chance PASS_SECONDS over the tree
	## regrow delay (the map's regrow_delay when set; 0 = never). Emits the
	## map's trees_sprouted with the cells. A client never sprouts on its own.
	## The blocked cells are gathered once for all players.
	var out: Array[Vector2i] = []
	if Interaction.multiplayer_on(_map.multiplayer) and not _map.multiplayer.is_server():
		return out
	if _map.play_time < _next_pass:
		return out
	_next_pass = _map.play_time + PASS_SECONDS
	var delay: float = _map.regrow_delay if _map.regrow_delay >= 0.0 else InteractableCatalog.by_id("tree").regrow_delay
	if delay <= 0.0:
		return out
	var size_v := Vector2i(_map.chunk_width, _map.chunk_height) * AREA_CHUNKS
	var blocked := blocked_cells()
	for node in _map.get_parent().get_children():
		if node is CharacterBody2D and str(node.name).is_valid_int():
			var at := _map.local_to_map(_map.to_local(node.global_position))
			out.append_array(sprout_pass(Rect2i(at - size_v / 2, size_v), minf(1.0, PASS_SECONDS / delay), blocked))
	if not out.is_empty():
		_map.trees_sprouted.emit(out)
	return out


func to_changes(out: Dictionary) -> void:
	## Add the sprouts to `out` (TreeCuts.to_changes entries): each sprouted
	## cell's entry gets "sprout", the save_key of its tree's type.
	for cell: Vector2i in _sprouts:
		var chunk := WorldSave.chunk_key(cell)
		if not out.has(chunk):
			out[chunk] = {}
		var key := WorldSave.cell_key(cell)
		if not out[chunk].has(key):
			out[chunk][key] = {}
		out[chunk][key]["sprout"] = InteractableCatalog.type_at(_sprouts[cell]).save_key


func restore(changes: Dictionary) -> int:
	## Add the sprouts in to_changes entries ("sprout"). A sprout is dropped
	## when the map no longer grows that type of tree on its cell. Returns
	## how many were added.
	var added := 0
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			var cell = WorldSave.parse_cell(str(key))
			if not entry is Dictionary or not entry.has("sprout") or cell == null:
				continue
			var tile := sprout_tile(cell)
			if tile != _WorldMap.NO_PLANT and InteractableCatalog.type_at(tile).save_key == str(entry["sprout"]) and add(cell):
				added += 1
	return added


func replace(changes: Dictionary) -> Array[Vector2i]:
	## Make the sprouts exactly the ones in `changes`: restore them, and drop
	## each one not listed. Returns the dropped cells, for TreeCuts to drop
	## their cuts and draw them again.
	var listed := {}
	for chunk in changes:
		for key in changes[chunk]:
			var entry = changes[chunk][key]
			if entry is Dictionary and entry.has("sprout"):
				listed[WorldSave.parse_cell(str(key))] = true
	var dropped: Array[Vector2i] = []
	for cell: Vector2i in _sprouts.keys():
		if not listed.has(cell):
			_sprouts.erase(cell)
			dropped.append(cell)
	restore(changes)
	return dropped
