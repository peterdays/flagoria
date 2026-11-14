class_name StructureRequests
extends Node
## Host-request pipeline for structures (#497, #498, #278). A client asks; the
## host checks reach and the solo footprint, writes, charges the placer, and
## tells peers. Towers and free-form walls are the kinds a client may ask for.
## A joining peer's starting castle is placed by the host and published here.
## Clients still cannot write: can_place reports multiplayer on for a raw
## structure place.

const REQUEST_KINDS := {
	BuildCosts.TOWER: true,
	BuildCosts.WALL_BLOCK: true,
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
	if kind == BuildCosts.WALL_BLOCK:
		return _host_wall(cells, peer_id)
	return false


func host_erase_wall(cell: Vector2i) -> bool:
	## Host removes one free-form wall and sends the chain and the cities.
	## A loop that opens dissolves on the host; peers receive that list.
	if not multiplayer.is_server():
		return false
	var gone: Array[Vector2i] = [cell]
	if not _map()._walls.erase_cells(gone):
		return false
	_publish()
	return true


func publish_structure(structure_name: String, owner: int, anchor: Vector2i) -> void:
	## Host: a castle placed for a peer who just joined. Peers already in the
	## match receive it. The joining peer receives it in the map snapshot that
	## follows on the same channel; a repeat of this call is ignored.
	if not multiplayer.is_server():
		return
	if not multiplayer.get_peers().is_empty():
		apply_structure.rpc(structure_name, owner, anchor)
	var cities := get_node_or_null("../Cities") as Cities
	if cities != null:
		cities.tick()


func sync_to_peer(peer_id: int) -> void:
	## Host: free-form walls and solved auto junction cells for a peer that
	## just joined. Cities are sent by Cities.sync_to_peer after this.
	if not multiplayer.is_server():
		return
	var snap := _wall_snapshot()
	apply_wall_state.rpc_id(peer_id, snap[0], snap[1])


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


func _host_wall(cells: Array[Vector2i], peer_id: int) -> bool:
	## Solo wall rules: land, a straight run, touching a wall or structure.
	## Two wood per cell. The host spends its own; a client is charged after
	## the write. Peers get the whole chain and the solved auto junctions.
	var placer := ConstructionPlacer.new(_map())
	if peer_id == multiplayer.get_unique_id():
		var inventory := get_node_or_null("../../Inventory") as Inventory
		if inventory == null:
			return false
		var why := BuildCosts.buy(inventory, BuildCosts.WALL_BLOCK, cells.size(), func() -> bool:
			return placer.write_wall(cells))
		if why != "":
			return false
	elif not placer.write_wall(cells):
		return false
	else:
		_interaction().rpc_id(peer_id, "receive_charge", BuildCosts.cost(BuildCosts.WALL_BLOCK, cells.size()))
	_publish()
	return true


func _publish() -> void:
	## Walls first, then Cities.tick, so a closed or opened loop is the host's
	## decision and leaves on the same reliable channel.
	var snap := _wall_snapshot()
	apply_wall_state.rpc(snap[0], snap[1])
	var cities := get_node_or_null("../Cities") as Cities
	if cities != null:
		cities.tick()


func _wall_snapshot() -> Array:
	## [free-form cells, auto junction entries [cell, solved tile name]].
	var map := _map()
	var free: Array = []
	for cell: Vector2i in map._walls._wall_cells:
		free.append(cell)
	var autos: Array = []
	for cell: Vector2i in map._structures.auto_cells():
		var name := WallBuilder._atlas_wall_name(map._structures.object_at(cell))
		if name != "":
			autos.append([cell, name])
	return [free, autos]


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
	## Applied only from peer 1, so ids follow the host's list. The same
	## castle arriving again (snapshot, then this call) is left as it is.
	if multiplayer.get_remote_sender_id() != 1:
		return
	var map := _map()
	for entry in map.placed_structures().values():
		if str(entry["name"]) == structure_name and int(entry["owner"]) == owner \
				and entry["anchor"] == anchor:
			return
	var structure := StructurePlacer.load_named(structure_name)
	if structure == null:
		return
	map._structures.place_from_host(structure, anchor, owner)


@rpc("authority", "reliable", "call_remote")
func apply_wall_state(free_cells: Array, autos: Array) -> void:
	## Free-form chain and solved auto junctions the host decided. A late
	## joiner and a live place both use this, so the pieces match.
	if multiplayer.get_remote_sender_id() != 1:
		return
	var map := _map()
	map._walls.replace_from_host(free_cells)
	for entry in autos:
		if entry is Array and entry.size() >= 2 and entry[0] is Vector2i \
				and entry[1] is String and str(entry[1]) != "":
			map._structures.apply_solved(entry[0], str(entry[1]))
