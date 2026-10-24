class_name MobSpawner
extends Node2D
## Places a few mobs on each island near the player spawn, the same for a given
## map seed. The server decides; its MultiplayerSpawner sends each mob's
## spawn data to every peer, including peers that join later.
##
## An island is a 4-connected group of clear ground cells (walkable, no tree,
## bush or stones) inside a SCAN_RADIUS box around the spawn. Terrain comes from
## TileMap.predict_cell, so no tiles are generated and the map is unchanged.

const MOB_SCENE_PATH := "res://Mobs/mob.tscn"

const SCAN_RADIUS := 40  ## cells each side of the spawn cell
const MIN_ISLAND_CELLS := 40  ## smaller islands get no mobs
const CELLS_PER_MOB := 300  ## one mob per this many island cells...
const MAX_PER_ISLAND := 3  ## ...up to this many
const MAX_MOBS := 10
const SAFE_RADIUS := 6  ## cells: no mob starts this close to the player spawn
const MIN_GAP := 4  ## cells between two mobs' start cells
const MIN_BEACH_CELLS := 12  ## sand cells an island needs for a crab

const GRASS := [TileCatalog.GRASS_A, TileCatalog.GRASS_B, TileCatalog.GRASS_C, TileCatalog.GRASS_D]

@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner


func _ready() -> void:
	spawner.spawn_function = _make_mob


static func is_home_cell(world: TileMap, cell: Vector2i, home: int) -> bool:
	## Clear ground of the mob's home kind: sand for HOME_SAND, grass otherwise.
	if not world.predicted_clear(cell):
		return false
	var ground: Vector2i = world.predict_cell(cell)[0]
	if home == MobCatalog.HOME_SAND:
		return ground == TileCatalog.SAND
	return GRASS.has(ground)


static func plan(world: TileMap, origin: Vector2i, seed_value: int) -> Array:
	## [{type, cell}] for this map, largest island first. Same inputs,
	## same plan.
	var clear := {}
	for x in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
		for y in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
			var c := origin + Vector2i(x, y)
			if world.predicted_clear(c):
				clear[c] = true
	var islands := _islands(clear)
	islands.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())

	var out: Array = []
	var taken: Array[Vector2i] = []
	for island in islands:
		if island.size() < MIN_ISLAND_CELLS or out.size() >= MAX_MOBS:
			break
		var want := clampi(island.size() / CELLS_PER_MOB, 1, MAX_PER_ISLAND)
		var order: Array = island.filter(func(c: Vector2i) -> bool:
			return maxi(absi(c.x - origin.x), absi(c.y - origin.y)) > SAFE_RADIUS)
		order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _rank(a, seed_value) < _rank(b, seed_value))
		var sand: Array = order.filter(func(c: Vector2i) -> bool: return is_home_cell(world, c, MobCatalog.HOME_SAND))
		var grass: Array = order.filter(func(c: Vector2i) -> bool: return is_home_cell(world, c, MobCatalog.HOME_GRASS))
		for slot in want:
			if out.size() >= MAX_MOBS:
				break
			var type := MobCatalog.CRAB
			var pool := sand
			if slot > 0 or sand.size() < MIN_BEACH_CELLS:
				pool = grass
				type = MobCatalog.SLIME if (_rank(island[0], seed_value) + slot) % 2 == 0 else MobCatalog.PIGLET
			var cell = _first_free(pool, taken)
			if cell == null:
				continue
			taken.append(cell)
			out.append({"type": type, "cell": cell})
	return out


static func _islands(clear: Dictionary) -> Array:
	## 4-connected groups of `clear` cells, in scan order.
	var seen := {}
	var out: Array = []
	for start in clear.keys():
		if seen.has(start):
			continue
		seen[start] = true
		var group: Array[Vector2i] = [start]
		var head := 0
		while head < group.size():
			var cur: Vector2i = group[head]
			head += 1
			for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var n: Vector2i = cur + d
				if clear.has(n) and not seen.has(n):
					seen[n] = true
					group.append(n)
		out.append(group)
	return out


static func _rank(cell: Vector2i, seed_value: int) -> int:
	return hash(Vector3i(cell.x, cell.y, seed_value)) & 0x7FFFFFFF


static func _first_free(pool: Array, taken: Array[Vector2i]) -> Variant:
	for c in pool:
		var ok := true
		for t in taken:
			if maxi(absi(c.x - t.x), absi(c.y - t.y)) < MIN_GAP:
				ok = false
				break
		if ok:
			return c
	return null


func spawn_for_world(world: TileMap, origin: Vector2i, seed_value: int) -> int:
	## Server only: replace any mobs with this map's plan. Returns the count.
	if not multiplayer.is_server():
		return 0
	clear_mobs()
	var plans := plan(world, origin, seed_value)
	for i in plans.size():
		var p: Dictionary = plans[i]
		spawner.spawn({
			"name": "mob_%d" % i,
			"type": p["type"],
			"pos": world.map_to_local(p["cell"]),
			"seed": hash(Vector2i(seed_value, i)),
		})
	return plans.size()


func clear_mobs() -> void:
	for child in get_children():
		if child is Mob:
			remove_child(child)
			child.queue_free()


func mobs() -> Array:
	return get_children().filter(func(n: Node) -> bool: return n is Mob)


func _make_mob(data: Dictionary) -> Node:
	var mob: Mob = load(MOB_SCENE_PATH).instantiate()
	mob.name = data["name"]
	mob.setup(data["type"], data["pos"], data["seed"])
	return mob
