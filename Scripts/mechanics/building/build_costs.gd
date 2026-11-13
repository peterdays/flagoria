class_name BuildCosts
extends RefCounted
## What each buildable costs in wood (#272), and buying one: check the wood,
## spend, then place. The shared construction placement module (#296) is
## calls buy; the placement UI (#225) talks only to that module. Tests also
## call buy directly for the cost table.
## Wood is local to each game (Inventory). Planks (#297), towers (#497) and
## walls (#498) are allowed while multiplayer is on: the host decides and the
## placer is charged. The starting castle still refuses.

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
## Spend refused after the refusal check (for example a stub inventory).
## Nothing is written (#380 item 3: charge before write, so a failed spend
## cannot leave tiles in place).
const SPEND_FAILED := "spend failed"


static func cost(kind: StringName, units := 1) -> int:
	## Wood for `units` of `kind`; -1 for a kind not in WOOD.
	return WOOD[kind] * units if WOOD.has(kind) else -1


static func refund(kind: StringName, units := 1) -> int:
	## Wood back for removing `units` of `kind` placed together: REFUND_SHARE
	## of their total cost, rounded down (one plank alone gives 0 back, a run
	## of four gives 2). 0 for a kind not in WOOD.
	return floori(cost(kind, units) * REFUND_SHARE) if WOOD.has(kind) else 0


## Kinds that stay host-alone. Towers (#497) and walls (#498) are requested
## on StructureRequests. The starting castle is still placed by the host alone.
const HOST_ALONE := {
	START_CASTLE: true,
}


static func refusal(inventory: Inventory, kind: StringName, units := 1) -> String:
	## Why buying `units` of `kind` is refused before placing; "" when it may
	## go ahead. Planks (#297), towers (#497) and walls (#498) are allowed in
	## multiplayer. The starting castle still refuses while peers are connected.
	if not WOOD.has(kind):
		return UNKNOWN_KIND
	if HOST_ALONE.has(kind) and Interaction.multiplayer_on(inventory.multiplayer):
		return MULTIPLAYER_ON
	if inventory.count_of(Inventory.WOOD) < cost(kind, units):
		return NOT_ENOUGH_WOOD
	return ""


static func buy(inventory: Inventory, kind: StringName, units: int, place: Callable) -> String:
	## Buy `units` of `kind`: when refusal gives no reason, take the wood
	## first, then call `place` (a writer such as build_bridge or
	## place_structure). Returns "" on success. A refused buy spends nothing
	## and writes nothing. If spend fails after the check, return spend failed
	## without writing. If the writer refuses after the spend, put the wood
	## back and return not placed — charge and write stay atomic (#380 item 3).
	var why := refusal(inventory, kind, units)
	if why != "":
		return why
	var wood := cost(kind, units)
	if not inventory.spend(Inventory.WOOD, wood):
		return SPEND_FAILED
	var placed: Variant = place.call()
	if (placed is bool and placed) or (placed is int and placed > 0):
		return ""
	inventory.add(Inventory.WOOD, wood)
	return NOT_PLACED
