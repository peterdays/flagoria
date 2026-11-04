class_name CutRateLimit
extends RefCounted
## The host's ceiling on cut requests (#355): Interaction.request_cut takes
## one token from the sending peer's bucket before any other check, and drops
## the request with no reply when the bucket is empty. Each peer has its own
## bucket; the host's own cuts do not use one.
##
## The numbers come from the fastest legitimate cutting, with 2x headroom:
## - A drag cuts every plant in reach at once. At most DRAG_CELLS cell centres
##   lie within Interaction.REACH (80 px) of a point on 16 px cells, so one
##   drag sends at most DRAG_CELLS requests.
## - Walking at the keyboard's top speed (MAX_SPEED, 130 px/s) brings at most
##   SWEEP_CELLS new cells a second into reach (a 2 * REACH wide strip), so
##   dragging nonstop through a forest with a plant on every cell sends at
##   most SWEEP_CELLS requests a second after the first drag. A tap's chop
##   (ChopAction.fell_at, 0.56 s) cuts one plant already in that reach.
## A full bucket also absorbs about 1 s of such requests that arrive at once
## after a network stall. test_cut_rate_numbers recounts both figures.

const TILE := 16.0  ## px per map cell (the tile set's tile_size)
const PlayerScript := preload("res://Scripts/player.gd")
const DRAG_CELLS := 81  ## most cell centres within Interaction.REACH of one point
const SWEEP_CELLS := 2.0 * Interaction.REACH * PlayerScript.MAX_SPEED / (TILE * TILE)  ## 81.25 cells/s
const HEADROOM := 2.0
const BURST := HEADROOM * DRAG_CELLS  ## tokens in a full bucket: 162
const RATE := HEADROOM * SWEEP_CELLS  ## tokens added per second: 162.5

## Seconds now; tests pin it.
var clock: Callable = func() -> float: return Time.get_ticks_usec() / 1000000.0
var _tokens := {}  ## peer id -> tokens left after its last request
var _last := {}  ## peer id -> time of its last request, s


func allow(peer: int) -> bool:
	## Take a token from `peer`'s bucket, refilled at RATE since its last
	## request up to BURST; false (and nothing taken) when it has none.
	var now: float = clock.call()
	var since := maxf(0.0, now - float(_last.get(peer, now)))
	var tokens := minf(BURST, float(_tokens.get(peer, BURST)) + since * RATE)
	var ok := tokens >= 1.0
	_tokens[peer] = tokens - 1.0 if ok else tokens
	_last[peer] = now
	return ok
