## The run: its score, its statistics, and its lifecycle. Registered as the `GameState` autoload.
##
## Scoring lives here rather than in the merge resolver because it is a property of the run, not
## of the physics. The resolver reports what happened; this decides what it was worth
## (GAME_DESIGN.md §10).
extends Node

signal score_changed(score: int)
signal run_started
signal run_ended(score: int, is_best: bool)
## The active piece set changed. Anything drawing a piece repaints on this.
signal piece_set_changed(piece_set: PieceSet)
## The aim mode changed (§7). Both buttons that offer it relabel on this, so whichever one the
## player did not touch is still telling the truth when they next see it.
signal invert_aim_changed(inverted: bool)

var score := 0
## Best across all runs, and the top-ten table the menu lists. Both are read straight from the
## save rather than mirrored here — one copy, so they cannot disagree.
var best_score: int:
	get:
		return SaveManager.best_score
var top_scores: Array[Dictionary]:
	get:
		return SaveManager.top_scores

## Which way a drag points the shot (§7). Read straight from the save for the same reason the
## scores are: one copy. Set it through `set_invert_aim()`.
var invert_aim: bool:
	get:
		return SaveManager.invert_aim

## Per-run statistics, for the game-over screen (§10).
var shots_fired := 0
var total_merges := 0
var highest_tier := 0
var longest_chain := 0
var tier12_pops := 0

var _running := false

## Both lazy: the registry is a resource load, and this is an autoload that is ready before the
## first scene. Cleared whenever the save is re-read, so the F10 harness swapping save files
## cannot leave a stale selection behind.
var _registry: PieceSetRegistry = null
var _active_set: PieceSet = null


func _ready() -> void:
	SaveManager.loaded.connect(_on_save_loaded)


# --- piece sets (§5.1) ---------------------------------------------------------------------------

## Every set this build ships. Never null on a sound project.
var piece_sets: PieceSetRegistry:
	get:
		if _registry == null:
			_registry = PieceSetRegistry.load_default()
			if _registry == null:
				push_error("piece sets: %s did not load" % Tuning.PIECE_SET_REGISTRY_PATH)
		return _registry

## The set pieces are currently drawn with. Falls back to classic when the save names a set this
## build does not have — an id that was renamed, or a set pulled from a later version.
var active_set: PieceSet:
	get:
		if _active_set == null and piece_sets != null:
			_active_set = piece_sets.get_set_or_default(SaveManager.selected_set)
		return _active_set


## True if the player may select this set: free sets are owned by definition, the rest are
## whatever the save has recorded.
func owns_set(id: StringName) -> bool:
	var piece_set: PieceSet = piece_sets.get_set(id) if piece_sets != null else null
	if piece_set == null:
		return false
	return piece_set.is_free() or id in SaveManager.owned_sets


## Switches the active set, if it exists and is owned. Returns false and changes nothing
## otherwise, so a shop that has not checked can never leave the game in a bad state.
func select_set(id: StringName) -> bool:
	if not owns_set(id):
		return false
	SaveManager.set_selected_set(id)
	_active_set = null
	piece_set_changed.emit(active_set)
	return true


## Grants a set outright. This is the seam a shop plugs into once there is a currency to charge
## (§16) — the price is on PieceSet already; nothing here spends it yet.
func unlock_set(id: StringName) -> bool:
	if piece_sets == null or piece_sets.get_set(id) == null:
		return false
	return SaveManager.grant_set(id)


## Ids the player can choose between right now.
func available_set_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if piece_sets == null:
		return out
	for piece_set in piece_sets.sets:
		if piece_set != null and owns_set(piece_set.id):
			out.append(piece_set.id)
	return out


func _on_save_loaded() -> void:
	var previous := _active_set
	_active_set = null
	if active_set != previous:
		piece_set_changed.emit(active_set)
	# Re-reading the save can change the aim mode under everything that is already showing it.
	invert_aim_changed.emit(invert_aim)


# --- aim mode (§7) -------------------------------------------------------------------------------

## Records the aim mode and tells everyone showing it. Safe to call with the value it already has.
func set_invert_aim(value: bool) -> void:
	if value == invert_aim:
		return
	SaveManager.set_invert_aim(value)
	invert_aim_changed.emit(value)


## Flips the mode and returns the one now in force.
func toggle_invert_aim() -> bool:
	set_invert_aim(not invert_aim)
	return invert_aim


## The label for a mode, for the two buttons that offer it. Names the mode you are in, so it reads
## as a state next to RESUME and QUIT, which are actions.
func aim_mode_label(inverted: bool) -> String:
	return Tuning.AIM_LABEL_PUSH if inverted else Tuning.AIM_LABEL_PULL


# --- the run -------------------------------------------------------------------------------------

func is_running() -> bool:
	return _running


func start_run() -> void:
	score = 0
	shots_fired = 0
	total_merges = 0
	highest_tier = 0
	longest_chain = 0
	tier12_pops = 0
	_running = true
	score_changed.emit(score)
	run_started.emit()


func end_run() -> void:
	if not _running:
		return
	_running = false
	# Committing the run is what promotes the best score and writes the file (§13).
	var is_best := SaveManager.record_run(
		score, highest_tier, longest_chain, total_merges, tier12_pops
	)
	run_ended.emit(score, is_best)


func register_shot() -> void:
	shots_fired += 1


## Scores a merge and returns what it was worth, so the caller can float the number.
func add_merge(tier: int, chain_depth: int) -> int:
	var points := points_for_merge(tier, chain_depth)
	_record(tier, chain_depth, points)
	return points


## Scores a tier-12 annihilation and returns what it was worth.
func add_annihilation(chain_depth: int) -> int:
	var points := points_for_annihilation(chain_depth)
	tier12_pops += 1
	_record(Tuning.MAX_TIER, chain_depth, points)
	return points


func _record(tier: int, chain_depth: int, points: int) -> void:
	score += points
	total_merges += 1
	highest_tier = maxi(highest_tier, tier)
	longest_chain = maxi(longest_chain, chain_depth + 1)
	score_changed.emit(score)


# --- the score model (§10) -----------------------------------------------------------------------

## Merging into tier N is worth N * N * SCORE_TIER_FACTOR, times the chain multiplier.
static func points_for_merge(tier: int, chain_depth: int) -> int:
	return int(tier * tier * Tuning.SCORE_TIER_FACTOR * chain_multiplier(chain_depth))


static func points_for_annihilation(chain_depth: int) -> int:
	return int(Tuning.TIER12_BONUS * chain_multiplier(chain_depth))


## Chain depth is counted within one shot and rewards merges that set off further merges. The
## last entry of the table is a cap, so a very long chain does not run away.
static func chain_multiplier(chain_depth: int) -> float:
	var table := Tuning.CHAIN_MULTIPLIERS
	return table[clampi(chain_depth, 0, table.size() - 1)]
