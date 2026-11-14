class_name Points
extends Node
## Every player's point total, owned by the server.
##
## award() and award_kill() are the places points are added. set_land() is the
## place a player's land count is set, including when it falls. All three act
## only on the server (peer 1, which is also the only peer offline) and tell
## every peer through a reliable call_local RPC, so all peers agree. A peer
## that connects later gets every total, and the mob ids already paid, after
## the map for that join is queued. Totals are keyed by peer id and stay
## after a player leaves.
##
## A mob kill is keyed by that mob's id. The server may send the award again,
## and a peer may receive it again: the second copy changes nothing.

## total_changed fires on every peer for each award; `reason` says where the
## points came from (for example "discovery" or "mob_kill").
signal total_changed(peer_id: int, total: int, amount: int, reason: String)
## The server's reply to a joining peer: every total so far, with no award.
signal totals_received

const SERVER_ID := 1

## Point values, tuned here and nowhere else.
const DISCOVERY_POINTS := 1  ## first player to stand in a map chunk (DiscoveryPoints)
const FLAGS_HELD_POINTS := 1  ## per owned flag tower each FlagsHeldPoints tick (#275)
## Paid to the player whose sword hit kills a mob, by mob type (Mob.take_hit).
const MOB_KILL_POINTS := {MobCatalog.SLIME: 5, MobCatalog.CRAB: 8, MobCatalog.PIGLET: 10}

var _totals := {}  ## peer id -> points, land included
var _land := {}  ## peer id -> land cells currently included in that total
var _kill_sent := {}  ## mob id -> true once the server has awarded that kill
var _kill_applied := {}  ## mob id -> true once this peer added its points


func _enter_tree() -> void:
	set_multiplayer_authority(SERVER_ID)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)


func total_of(peer_id: int) -> int:
	return _totals.get(peer_id, 0)


func earned_of(peer_id: int) -> int:
	## Points other than the live land count. A save stores this. Loading it
	## back and letting LandScore set the land again does not count the city
	## twice.
	return maxi(0, total_of(peer_id) - int(_land.get(peer_id, 0)))


func set_land(peer_id: int, cells: int) -> bool:
	## Server only: make `peer_id`'s land contribution `cells`. The displayed
	## total moves by the difference, so losing land removes it and other
	## awards stay. Reason `land`. Returns true when the total changed.
	if not multiplayer.is_server() or peer_id <= 0 or cells < 0:
		return false
	var prev := int(_land.get(peer_id, 0))
	if prev == cells:
		return false
	var delta := cells - prev
	var total := total_of(peer_id) + delta
	_land[peer_id] = cells
	_apply_award.rpc(peer_id, total, delta, "land")
	return true


func award(peer_id: int, amount: int, reason: String) -> bool:
	## Server only: add `amount` points to `peer_id`'s total. Returns true
	## when the points were added. Not for mob kills: those go through
	## award_kill(), which ignores a second message for the same mob id.
	if not multiplayer.is_server() or peer_id <= 0 or amount <= 0:
		return false
	_apply_award.rpc(peer_id, total_of(peer_id) + amount, amount, reason)
	return true


func award_kill(peer_id: int, mob_id: String, amount: int) -> bool:
	## Server only: pay `amount` for killing `mob_id`. Returns true the first
	## time that id is awarded. A later call sends the same message again and
	## returns false; every peer, this one included, adds the points only once.
	if not multiplayer.is_server() or peer_id <= 0 or amount <= 0 or mob_id.is_empty():
		return false
	var repeat := _kill_sent.has(mob_id)
	_kill_sent[mob_id] = true
	_apply_kill.rpc(peer_id, mob_id, amount)
	return not repeat


func clear_kill_credits() -> void:
	## Server only: forget which mobs have paid, so a freshly spawned set
	## (the same mob ids again) can pay. Peers already in the match are told.
	## With none yet, the clear stays local so server startup does not put a
	## packet on the wire ahead of the first join.
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		_kill_sent.clear()
		_kill_applied.clear()
		return
	_clear_kill_credits.rpc()


func restore_total(peer_id: int, total: int) -> void:
	## Server only: set `peer_id`'s total to `total`, as a loaded save does.
	## Not an award: the amount on the signal is 0 and the reason is "load".
	if not multiplayer.is_server() or peer_id <= 0 or total < 0:
		return
	## The saved number is earned points. Land is applied again after load.
	if total_of(peer_id) == total and int(_land.get(peer_id, 0)) == 0:
		return
	_land[peer_id] = 0
	_apply_award.rpc(peer_id, total, 0, "load")


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		# After this handler returns, the player spawn and the map run (they are
		# connected later). The snapshot goes out only once those are queued.
		_send_join_snapshot.bind(peer_id).call_deferred()


func _send_join_snapshot(peer_id: int) -> void:
	## Totals and the mob ids already paid, so a later copy of an old kill
	## message does not add points on top of this snapshot.
	if not multiplayer.is_server() or not multiplayer.get_peers().has(peer_id):
		return
	_receive_totals.rpc_id(peer_id, _totals.duplicate(), _kill_ids())


func _kill_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for mob_id in _kill_applied.keys():
		ids.append(str(mob_id))
	return ids


@rpc("authority", "call_local", "reliable")
func _apply_award(peer_id: int, total: int, amount: int, reason: String) -> void:
	_totals[peer_id] = total
	total_changed.emit(peer_id, total, amount, reason)


@rpc("authority", "call_local", "reliable")
func _apply_kill(peer_id: int, mob_id: String, amount: int) -> void:
	## One kill award. A second delivery for `mob_id` returns without touching
	## the total or emitting total_changed.
	if peer_id <= 0 or amount <= 0 or mob_id.is_empty() or _kill_applied.has(mob_id):
		return
	_kill_applied[mob_id] = true
	var total := total_of(peer_id) + amount
	_totals[peer_id] = total
	total_changed.emit(peer_id, total, amount, "mob_kill")


@rpc("authority", "call_local", "reliable")
func _clear_kill_credits() -> void:
	_kill_sent.clear()
	_kill_applied.clear()


@rpc("authority", "call_remote", "reliable")
func _receive_totals(totals: Dictionary, kills: PackedStringArray) -> void:
	_totals = totals.duplicate()
	_kill_applied.clear()
	for mob_id in kills:
		_kill_applied[str(mob_id)] = true
	totals_received.emit()
