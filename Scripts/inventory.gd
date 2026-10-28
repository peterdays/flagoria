class_name Inventory
extends Node
## Resources the local player has gathered: resource name -> count. Wood is
## the only resource so far. The inventory is local to this game; it is not
## synced to other players and not kept in world saves yet.

signal changed(resource: StringName, count: int)

const WOOD := &"wood"

var _counts := {}


func add(resource: StringName, amount := 1) -> int:
	## Add `amount` of `resource` and return the new count.
	var count: int = _counts.get(resource, 0) + amount
	_counts[resource] = count
	changed.emit(resource, count)
	return count


func count_of(resource: StringName) -> int:
	return _counts.get(resource, 0)
