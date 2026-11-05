class_name Inventory
extends Node
## Resources the local player has gathered: resource name -> count. Wood is
## the only resource so far. The inventory is local to this game; it is not
## synced to other players and not kept in world saves yet. In two-player play
## the host decides each cut and sends the cutter its wood
## (Interaction.receive_yields). Building spends wood through spend
## (BuildCosts.buy, #272).

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


func spend(resource: StringName, amount: int) -> bool:
	## Take `amount` of `resource` and emit `changed`. False, and nothing
	## taken or emitted, when the count is below `amount` or `amount` is
	## negative. Spending 0 always succeeds.
	var count := count_of(resource)
	if amount < 0 or count < amount:
		return false
	_counts[resource] = count - amount
	changed.emit(resource, count - amount)
	return true
