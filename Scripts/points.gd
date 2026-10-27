class_name Points
extends Node
## Every player's point total, owned by the server.
##
## award() is the one place points are added: it only acts on the server
## (peer 1, which is also the only peer offline) and sends the new total to
## every peer through a reliable call_local RPC, so all peers agree. A peer
## that connects later gets every total from the server as it connects.
## Totals are keyed by peer id and stay after a player leaves.

## total_changed fires on every peer for each award; `reason` says where the
## points came from (for example "discovery" or "mob_kill").
signal total_changed(peer_id: int, total: int, amount: int, reason: String)
## The server's reply to a joining peer: every total so far, with no award.
signal totals_received

const SERVER_ID := 1

## Point values, tuned here and nowhere else.
const DISCOVERY_POINTS := 1  ## first player to stand in a map chunk (DiscoveryPoints)
## Paid to the player whose sword hit kills a mob, by mob type (Mob.take_hit).
const MOB_KILL_POINTS := {MobCatalog.SLIME: 5, MobCatalog.CRAB: 8, MobCatalog.PIGLET: 10}

var _totals := {}  ## peer id -> points


func _enter_tree() -> void:
	set_multiplayer_authority(SERVER_ID)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)


func total_of(peer_id: int) -> int:
	return _totals.get(peer_id, 0)


func award(peer_id: int, amount: int, reason: String) -> bool:
	## Server only: add `amount` points to `peer_id`'s total. Returns true
	## when the points were added.
	if not multiplayer.is_server() or peer_id <= 0 or amount <= 0:
		return false
	_apply_award.rpc(peer_id, total_of(peer_id) + amount, amount, reason)
	return true


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_receive_totals.rpc_id(peer_id, _totals)


@rpc("authority", "call_local", "reliable")
func _apply_award(peer_id: int, total: int, amount: int, reason: String) -> void:
	_totals[peer_id] = total
	total_changed.emit(peer_id, total, amount, reason)


@rpc("authority", "call_remote", "reliable")
func _receive_totals(totals: Dictionary) -> void:
	_totals = totals.duplicate()
	totals_received.emit()
