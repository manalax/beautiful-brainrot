## The only thing in the project that touches the filesystem (GAME_DESIGN.md §13).
##
## Everything here is best-effort. A missing file, unreadable JSON, a version from the future,
## a `top_scores` that is somehow a string — all of it loads as defaults with a warning. Play is
## never blocked on save I/O and a bad file never crashes the game.
##
## Writes go to a temporary file and are then renamed over the real one, so a write interrupted
## halfway cannot destroy a save that was already good.
extends Node

## The save was read (or found missing and defaulted). The menu refreshes on this.
signal loaded

const DEFAULT_STATS := {"games_played": 0, "total_merges": 0, "tier12_pops": 0}

var best_score := 0
var top_scores: Array[Dictionary] = []
var stats: Dictionary = DEFAULT_STATS.duplicate()

## The piece set the player has chosen, and the ids they have paid for (§5.1). Stored as written
## rather than checked against the registry: this layer validates *shape*, not meaning, so a set
## that has been renamed or dropped from a build is GameState's problem to fall back from.
## Free sets are owned implicitly and are not listed here.
var selected_set: StringName = Tuning.DEFAULT_PIECE_SET
var owned_sets: Array[StringName] = []

var save_path := Tuning.SAVE_PATH
var tmp_path := Tuning.SAVE_TMP_PATH


func _ready() -> void:
	load_game()


## Points the manager at a different file and reloads. Used by the F10 harness so that testing
## cannot wipe a real player's scores.
func use_path(path: String) -> void:
	save_path = path
	tmp_path = path + ".tmp"
	load_game()


## Files a finished run: promotes the best, slots it into the table, bumps the lifetime counters,
## and writes. Returns true if it was a new best.
func record_run(
	score: int, highest_tier: int, longest_chain: int, merges: int, tier12_pops: int
) -> bool:
	var is_best := score > best_score
	best_score = maxi(best_score, score)

	top_scores.append({
		"score": score,
		"highest_tier": highest_tier,
		"longest_chain": longest_chain,
		"timestamp": int(Time.get_unix_time_from_system()),
	})
	_sort_and_trim()

	stats["games_played"] = int(stats.get("games_played", 0)) + 1
	stats["total_merges"] = int(stats.get("total_merges", 0)) + merges
	stats["tier12_pops"] = int(stats.get("tier12_pops", 0)) + tier12_pops

	save()
	return is_best


func save() -> void:
	# StringName has no JSON representation, so ids go out as plain strings.
	var owned_out: Array[String] = []
	for id in owned_sets:
		owned_out.append(String(id))

	var payload := {
		"version": Tuning.SAVE_VERSION,
		"best_score": best_score,
		"top_scores": top_scores,
		"stats": stats,
		"selected_set": String(selected_set),
		"owned_sets": owned_out,
	}

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("save: could not open %s (%d)" % [tmp_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	var dir := DirAccess.open(save_path.get_base_dir())
	if dir == null:
		push_warning("save: could not open %s" % save_path.get_base_dir())
		return

	# Rename over the top. POSIX replaces atomically; if a platform refuses, fall back to
	# removing first — that leaves a hairline window with no save, which beats not saving at all.
	if dir.rename(tmp_path, save_path) != OK:
		dir.remove(save_path)
		if dir.rename(tmp_path, save_path) != OK:
			push_warning("save: could not move %s onto %s" % [tmp_path, save_path])


func load_game() -> void:
	_defaults()

	if not FileAccess.file_exists(save_path):
		loaded.emit()
		return

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("save: unreadable, using defaults (%d)" % FileAccess.get_open_error())
		loaded.emit()
		return

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("save: not valid JSON, using defaults")
		loaded.emit()
		return

	var data: Dictionary = parsed
	var version := int(data.get("version", 0))
	if version != Tuning.SAVE_VERSION:
		push_warning("save: version %d is not %d, using defaults"
			% [version, Tuning.SAVE_VERSION])
		loaded.emit()
		return

	best_score = maxi(0, _as_int(data.get("best_score", 0)))
	top_scores = _clean_scores(data.get("top_scores", []))
	stats = _clean_stats(data.get("stats", {}))

	# Added after SAVE_VERSION 1 shipped. Deliberately *not* a version bump: load_game() discards
	# the whole file on a version mismatch, so bumping would throw away every existing player's
	# high scores to add a cosmetic preference. A file without these keys simply defaults.
	selected_set = _clean_set_id(data.get("selected_set", ""))
	owned_sets = _clean_owned_sets(data.get("owned_sets", []))

	# A file could carry a best that no longer appears in the table, or the reverse.
	if not top_scores.is_empty():
		best_score = maxi(best_score, int(top_scores[0]["score"]))

	loaded.emit()


## Wipes the save and the file behind it.
func clear() -> void:
	_defaults()
	var dir := DirAccess.open(save_path.get_base_dir())
	if dir != null:
		dir.remove(save_path)
		dir.remove(tmp_path)


func _defaults() -> void:
	best_score = 0
	top_scores = []
	stats = DEFAULT_STATS.duplicate()
	selected_set = Tuning.DEFAULT_PIECE_SET
	owned_sets = []


## Records a set as paid for and writes. Idempotent, and free sets are never listed — they are
## owned by definition, so writing them would just bloat the file. Returns true if this changed
## anything. The currency this is eventually spent from does not exist yet (§16).
func grant_set(id: StringName) -> bool:
	if String(id).is_empty() or id in owned_sets:
		return false
	owned_sets.append(id)
	save()
	return true


## Persists the player's choice. GameState decides whether the choice is *allowed*; this only
## records it.
func set_selected_set(id: StringName) -> void:
	if id == selected_set:
		return
	selected_set = id
	save()


func _sort_and_trim() -> void:
	top_scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]))
	if top_scores.size() > Tuning.TOP_SCORES_COUNT:
		top_scores.resize(Tuning.TOP_SCORES_COUNT)


## Keeps only entries that look like scores, and fills in anything missing rather than trusting
## the file's shape.
func _clean_scores(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return out

	for entry: Variant in raw:
		if not (entry is Dictionary) or not entry.has("score"):
			continue
		out.append({
			"score": maxi(0, _as_int(entry.get("score", 0))),
			"highest_tier": clampi(_as_int(entry.get("highest_tier", 0)), 0, Tuning.MAX_TIER),
			"longest_chain": maxi(0, _as_int(entry.get("longest_chain", 0))),
			"timestamp": _as_int(entry.get("timestamp", 0)),
		})

	top_scores = out
	_sort_and_trim()
	return top_scores


func _clean_stats(raw: Variant) -> Dictionary:
	var out := DEFAULT_STATS.duplicate()
	if not (raw is Dictionary):
		return out
	for key: String in out:
		out[key] = maxi(0, _as_int((raw as Dictionary).get(key, 0)))
	return out


## A set id has to survive a hand-edited or corrupt file: anything that is not a usable string
## falls back to the default set rather than leaving the player with no face on their pieces.
func _clean_set_id(raw: Variant) -> StringName:
	if not (raw is String) or String(raw).is_empty():
		return Tuning.DEFAULT_PIECE_SET
	return StringName(raw)


## Keeps only entries that look like ids, and drops duplicates. Whether an id still exists in
## this build is not knowable here — GameState resolves that against the registry.
func _clean_owned_sets(raw: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if not (raw is Array):
		return out

	for entry: Variant in raw:
		if not (entry is String) or String(entry).is_empty():
			continue
		var id := StringName(entry)
		if id not in out:
			out.append(id)
	return out


## JSON gives every number back as a float, and a corrupt file can give back anything at all.
func _as_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String:
		return int(String(value).to_int())
	return 0
