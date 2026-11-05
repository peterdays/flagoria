class_name BuildCosts
extends RefCounted
## What each buildable costs in wood (#272), and buying one: check the wood,
## place, then spend. The shared construction placement module (#296) is
## meant to call buy; until then only tests do, because no in-game build
## action exists yet.
## Wood is local to each game (Inventory) and not synced yet, so buy refuses
## while multiplayer is on, as StructurePlacer does. Per-player wood for
## connected peers is #278.

const PLANK := &"plank"
const WALL_BLOCK := &"wall_block"
const TOWER := &"tower"
const START_CASTLE := &"start_castle"

## Kind -> wood for one unit: a plank is one bridge cell, a wall block one
## wall cell, a tower one tower. The starting castle each player gets is free.
const WOOD := {
	PLANK: 1,
	WALL_BLOCK: 2,
	TOWER: 10,
	START_CASTLE: 0,
}
## Share of the cost given back when a build is removed. Nothing removes a
## build yet; removal reads refund when it lands.
const REFUND_SHARE := 0.5

const NOT_ENOUGH_WOOD := "not enough wood"
const MULTIPLAYER_ON := "multiplayer on"
const UNKNOWN_KIND := "unknown kind"
const NOT_PLACED := "not placed"


static func cost(kind: StringName, units := 1) -> int:
	## Wood for `units` of `kind`; -1 for a kind not in WOOD.
	return WOOD[kind] * units if WOOD.has(kind) else -1


static func refund(kind: StringName, units := 1) -> int:
	## Wood back for removing `units` of `kind` placed together: REFUND_SHARE
	## of their total cost, rounded down (one plank alone gives 0 back, a run
	## of four gives 2). 0 for a kind not in WOOD.
	return floori(cost(kind, units) * REFUND_SHARE) if WOOD.has(kind) else 0


static func refusal(inventory: Inventory, kind: StringName, units := 1) -> String:
	## Why buying `units` of `kind` is refused before placing; "" when it may
	## go ahead.
	if not WOOD.has(kind):
		return UNKNOWN_KIND
	if Interaction.multiplayer_on(inventory.multiplayer):
		return MULTIPLAYER_ON
	if inventory.count_of(Inventory.WOOD) < cost(kind, units):
		return NOT_ENOUGH_WOOD
	return ""


static func buy(inventory: Inventory, kind: StringName, units: int, place: Callable) -> String:
	## Buy `units` of `kind`: when refusal gives no reason, call `place` (a
	## writer such as build_bridge or place_structure) and spend the cost only
	## when it placed (true, or an id above 0). Returns "" on success, else
	## the reason; a refused or failed placement spends nothing.
	var why := refusal(inventory, kind, units)
	if why != "":
		return why
	var placed: Variant = place.call()
	if not ((placed is bool and placed) or (placed is int and placed > 0)):
		return NOT_PLACED
	inventory.spend(Inventory.WOOD, cost(kind, units))
	return ""
