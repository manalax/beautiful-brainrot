## The two-slot supply of pieces (GAME_DESIGN.md §9): one on the launcher, one shown in the HUD.
##
## The player sees current and next and must play them in order — there is no hold or swap (§3).
## Draws are weighted toward the low tiers and come from a seeded generator held for the whole
## run, so a bug is reproducible and a daily-seed mode stays possible later.
class_name SpawnQueue
extends Node

## The next-up piece changed. The HUD swatch listens.
signal next_changed(data: TierData)

## The seed actually in use, whether given or rolled. Worth recording with a score.
var run_seed: int = 0

var _tiers: TierSet = null
var _rng := RandomNumberGenerator.new()
var _current: TierData = null
var _next: TierData = null


func _ready() -> void:
	if _tiers == null:
		_tiers = TierSet.load_default()


## Begins a run. Pass a seed to reproduce a previous run; 0 rolls a fresh one.
##
## Only the next slot is filled: nothing is "current" until the launcher asks for a piece, which
## it does on the first frame. Filling both here would put the queue a slot ahead of itself and
## the HUD would advertise the piece *after* the one that actually loads next.
func start(seed_value: int = 0) -> void:
	if _tiers == null:
		_tiers = TierSet.load_default()

	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	run_seed = _rng.seed

	_current = null
	_next = _draw()


## The piece on the launcher right now, or null before the first `take()`.
func current() -> TierData:
	return _current


## What the HUD shows: exactly what the next `take()` will hand over. That equality is the whole
## contract of this class — the player is promised the piece they can see coming.
func peek_next() -> TierData:
	return _next


## Advances the queue: the previewed piece becomes current and a fresh one is previewed.
func take() -> TierData:
	_current = _next
	_next = _draw()
	next_changed.emit(_next)
	return _current


## Weighted pick across the spawn pool. Index 0 of the weights is tier 1.
func _draw() -> TierData:
	var total := 0
	for weight in Tuning.SPAWN_TIER_WEIGHTS:
		total += weight

	var roll := _rng.randi_range(1, total)
	var cumulative := 0
	for i in Tuning.SPAWN_TIER_WEIGHTS.size():
		cumulative += Tuning.SPAWN_TIER_WEIGHTS[i]
		if roll <= cumulative:
			return _tiers.get_tier(i + 1)

	return _tiers.get_tier(1)
