class_name InteractableCatalog
extends RefCounted
## Every choppable type, and which one a foliage tile is. A preload list,
## not a scan of data/interactables/: exported builds keep only .remap files
## there, and the list fails to parse when a file is missing.

const TYPES := [
	preload("res://data/interactables/tree.tres"),
	preload("res://data/interactables/pine.tres"),
	preload("res://data/interactables/bush.tres"),
]

# Only plain values here: a static var holding a resource outlives the
# script at exit.
static var _by_atlas := {}  # foliage atlas coords -> index in TYPES
static var _leftovers := {}  # atlas coords a cut type leaves -> true


static func _index() -> void:
	if not _by_atlas.is_empty():
		return
	for i in TYPES.size():
		for n in TYPES[i].tiles:
			_by_atlas[TileCatalog.TILES[n]["atlas"]] = i
		_leftovers[TYPES[i].leaves_atlas()] = true


static func type_at(atlas: Vector2i) -> InteractableType:
	## The type whose tile is `atlas`, or null when it is not choppable.
	_index()
	return TYPES[_by_atlas[atlas]] if _by_atlas.has(atlas) else null


static func by_id(id: String) -> InteractableType:
	for type: InteractableType in TYPES:
		if type.id == id:
			return type
	return null


static func is_leftover(atlas: Vector2i) -> bool:
	## True for what a cut type leaves (STUMP, BUSH_STUMP): walkable decor.
	_index()
	return _leftovers.has(atlas)
