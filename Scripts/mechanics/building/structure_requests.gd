class_name StructureRequests
extends Node
## Host-request pipeline for structures (#497). A client asks; the host checks
## reach and the solo footprint, writes, charges the placer, and tells peers.
## Towers are the first kind. A walls slice adds a kind here, not a new pipeline.
## Clients still cannot write: can_place reports multiplayer on.

const REQUEST_KINDS := {
	BuildCosts.TOWER: true,
}


func _map() -> TileMap:
	return get_node("../worldMap") as TileMap


func _interaction() -> Interaction:
	return get_node("../Interaction") as Interaction


func place(kind: StringName, cells: Array[Vector2i]) -> bool:
	## Alone, ConstructionPlacer spends and writes. With peers, the host decides
	## and a client only sends the request. A connecting client sends nothing.
	if cells.is_empty():
		return false
	if not Interaction.multiplayer_on(multiplayer):
		var inventory := get_node_or_null("../../Inventory") as Inventory
		if inventory == null:
			return false
		return ConstructionPlacer.new(_map()).place(kind, cells, inventory)
	if not REQUEST_KINDS.has(kind):
		return false
	if multiplayer.is_server():
		return host_place(kind, cells, multiplayer.get_unique_id())
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	request_place.rpc_id(1, String(kind), cells)
	return true


func host_place(kind: StringName, cells: Array[Vector2i], peer_id: int) -> bool:
	## Host accepts `peer_id`'s request, or places for itself. False charges nothing.
	if not multiplayer.is_server() or not REQUEST_KINDS.has(kind) or cells.is_empty():
		return false
	if kind == BuildCosts.TOWER and cells.size() != 1:
		return false
	var body := get_node_or_null("../" + str(peer_id)) as Node2D
	if body == null or Interaction.player_dead(body):
		return false
	var interaction := _interaction()
	for cell in cells:
		if body.global_position.distance_to(interaction.cell_center(cell)) > Interaction.REACH + Interaction.REACH_SLACK:
			return false
	if kind == BuildCosts.TOWER:
		return _host_tower(cells[0], peer_id)
	return false


func _host_tower(anchor: Vector2i, peer_id: int) -> bool:
	## Solo footprint rules. The host spends its own wood; a client is charged
	## with receive_charge after the write, same order as a plank (#297).
	var placer := ConstructionPlacer.new(_map())
	if peer_id == multiplayer.get_unique_id():
		var inventory := get_node_or_null("../../Inventory") as Inventory
		if inventory == null:
			return false
		var why := BuildCosts.buy(inventory, BuildCosts.TOWER, 1, func() -> int:
			return placer.write_tower(anchor, peer_id))
		if why != "":
			return false
	elif placer.write_tower(anchor, peer_id) <= 0:
		return false
	else:
		_interaction().rpc_id(peer_id, "receive_charge", BuildCosts.cost(BuildCosts.TOWER, 1))
	apply_structure.rpc(ConstructionPlacer.TOWER_STRUCTURE, peer_id, anchor)
	return true


@rpc("any_peer", "reliable", "call_remote")
func request_place(kind: String, cells: Array) -> void:
	if not multiplayer.is_server():
		return
	var parsed: Array[Vector2i] = []
	for cell in cells:
		if cell is Vector2i:
			parsed.append(cell)
	host_place(StringName(kind), parsed, multiplayer.get_remote_sender_id())


@rpc("authority", "reliable", "call_remote")
func apply_structure(structure_name: String, owner: int, anchor: Vector2i) -> void:
	## Applied only from peer 1, so ids follow the host's list.
	if multiplayer.get_remote_sender_id() != 1:
		return
	var structure := StructurePlacer.load_named(structure_name)
	if structure == null:
		return
	_map()._structures.place_from_host(structure, anchor, owner)
