class_name ExploredMap
extends RefCounted
## Which world cells have been explored, kept per 32 x 32 cell chunk as a
## 128-byte bitset (bit ly * 32 + lx of the chunk, low bit first). A cell is
## explored once it lies within REVEAL_RADIUS cells (Euclidean) of a hero.
## Chunks with no explored cell are not stored, so the data stays sparse.
## The chunk grid is fixed and independent of the map's generation window.

const CHUNK := 32
const CHUNK_BYTES := CHUNK * CHUNK / 8
const REVEAL_RADIUS := 10

var _chunks := {}  ## chunk (Vector2i) -> PackedByteArray of CHUNK_BYTES


static func chunk_of(cell: Vector2i) -> Vector2i:
	## The chunk holding cell.
	return Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))


func is_explored(cell: Vector2i) -> bool:
	var bits: PackedByteArray = _chunks.get(chunk_of(cell), PackedByteArray())
	if bits.is_empty():
		return false
	var i := _bit_index(cell)
	return bits[i >> 3] & (1 << (i & 7)) != 0


func reveal(center: Vector2i, radius: int = REVEAL_RADIUS) -> Array[Vector2i]:
	## Marks every cell within radius of center as explored. Returns the
	## chunks that gained at least one explored cell.
	var changed: Array[Vector2i] = []
	for cell in reveal_cells(center, radius):
		var chunk := chunk_of(cell)
		if not chunk in changed:
			changed.append(chunk)
	return changed


func reveal_cells(center: Vector2i, radius: int = REVEAL_RADIUS) -> Array[Vector2i]:
	## Like reveal, but returns the cells that were not explored before.
	var fresh: Array[Vector2i] = []
	var r2 := radius * radius
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			var cell := center + Vector2i(dx, dy)
			var chunk := chunk_of(cell)
			if not _chunks.has(chunk):
				var empty := PackedByteArray()
				empty.resize(CHUNK_BYTES)
				_chunks[chunk] = empty
			var i := _bit_index(cell)
			var bits: PackedByteArray = _chunks[chunk]
			var mask := 1 << (i & 7)
			if bits[i >> 3] & mask:
				continue
			bits[i >> 3] |= mask
			_chunks[chunk] = bits
			fresh.append(cell)
	return fresh


func explored_rect() -> Rect2i:
	## Smallest axis-aligned rectangle of explored cells; size zero when none.
	var any := false
	var lo := Vector2i.MAX
	var hi := Vector2i.MIN
	for chunk: Vector2i in _chunks:
		var bits: PackedByteArray = _chunks[chunk]
		for ly in CHUNK:
			for lx in CHUNK:
				var i := ly * CHUNK + lx
				if bits[i >> 3] & (1 << (i & 7)) == 0:
					continue
				var cell := chunk * CHUNK + Vector2i(lx, ly)
				lo = lo.min(cell)
				hi = hi.max(cell)
				any = true
	if not any:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func chunks() -> Array:
	## The chunks with at least one explored cell.
	return _chunks.keys()


func chunk_bits(chunk: Vector2i) -> PackedByteArray:
	## A copy of chunk's bitset, or an empty array when nothing in it is explored.
	return _chunks.get(chunk, PackedByteArray()).duplicate()


func explored_count() -> int:
	var n := 0
	for bits: PackedByteArray in _chunks.values():
		for b in bits:
			while b:
				n += b & 1
				b >>= 1
	return n


func clear() -> void:
	_chunks.clear()


func replace_chunks(chunks: Dictionary) -> void:
	## Replace the chart. `chunks` is chunk -> a CHUNK_BYTES bitset. A short
	## or empty bitset is dropped, which is the same as not explored.
	_chunks.clear()
	for chunk in chunks:
		if not chunk is Vector2i:
			continue
		var bits: PackedByteArray = chunks[chunk]
		if bits.size() != CHUNK_BYTES:
			continue
		var any := false
		for b in bits:
			if b != 0:
				any = true
				break
		if any:
			_chunks[chunk] = bits.duplicate()


static func _bit_index(cell: Vector2i) -> int:
	return posmod(cell.y, CHUNK) * CHUNK + posmod(cell.x, CHUNK)
