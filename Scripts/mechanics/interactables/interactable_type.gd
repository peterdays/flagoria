class_name InteractableType
extends Resource
## One kind of choppable plant (#264): the foliage tiles it matches, how
## many chop hits fell it, what it gives and leaves, and its effects. One
## file per type in data/interactables/, listed in InteractableCatalog.
## Tuning a type (wood, hits) is an edit to its .tres, not to code.

## Name of the type, e.g. "tree" or "bush".
@export var id := ""
## TileCatalog.TILES names of the foliage-layer tiles this type is.
@export var tiles: Array[String] = []
## Chop impacts until it falls (Interaction's timing is per hit).
@export var hits := 2
## Resources added to the inventory when it falls, e.g. {&"wood": 1}.
@export var yields: Dictionary[StringName, int] = {}
## TileCatalog.TILES name of the walkable ground decor it leaves.
@export var leaves := ""
## Played on each impact (one picked at random) and when it falls.
@export var hit_sounds: Array[AudioStream] = []
@export var fell_sounds: Array[AudioStream] = []
## Pick a hit sound other than the previous one (with 2 or more).
@export var hit_no_repeat := false
## Each slot below plays on its own sound player, over the ones above, and
## may be empty. With each hit sound (e.g. leaves):
@export var hit_layer_sounds: Array[AudioStream] = []
## With the last impact's hit sound:
@export var last_hit_sounds: Array[AudioStream] = []
## When its yields are added to the inventory:
@export var pickup_sounds: Array[AudioStream] = []
## Frames (16x16, left to right) drawn in place of the tile after each
## impact. A type with a hit sheet needs alternative tile
## Interaction.HIDDEN_ALT (invisible, same collision) in the TileSet.
@export var hit_sheet: Texture2D
## 4 frames (16x16) over the cell: 0-1 after each impact, 2-3 once it falls.
@export var fx_sheet: Texture2D
## Play the puff cloud (MobCatalog.PUFF_SHEET) over the cell when it falls.
@export var fell_puff := false


func leaves_atlas() -> Vector2i:
	return TileCatalog.TILES[leaves]["atlas"]


func amount_of(resource: StringName) -> int:
	return yields.get(resource, 0)
