## Dev harness for F10: the save's shape, its resilience to a mangled file, and — across two
## separate launches of the engine — that scores actually survive a restart.
##
## Not part of the game. Run `res://scenes/game/save_test.tscn` directly for the in-process pass.
## The restart proof needs two runs and is driven by the F10_PHASE environment variable:
##
##     F10_PHASE=write godot --path . res://scenes/game/save_test.tscn
##     F10_PHASE=read  godot --path . res://scenes/game/save_test.tscn
##
## Everything here points SaveManager at a scratch file, so running it can never wipe a real save.
extends Node

const TEST_PATH := "user://save_test.json"
const RESTART_SCORE := 4820
const RESTART_TIER := 9
const RESTART_CHAIN := 4

var _failures := 0


func _ready() -> void:
	match OS.get_environment("F10_PHASE"):
		"write":
			_phase_write()
		"read":
			_phase_read()
		_:
			_run_tests()
	get_tree().quit(1 if _failures > 0 else 0)


# --- the restart proof, across two launches ------------------------------------------------------

func _phase_write() -> void:
	print("\n=== F10 restart, phase 1: writing ===")
	SaveManager.use_path(TEST_PATH)
	SaveManager.clear()
	SaveManager.record_run(RESTART_SCORE, RESTART_TIER, RESTART_CHAIN, 37, 2)
	SaveManager.record_run(1200, 6, 2, 11, 0)
	print("  wrote best %d, %d scores" % [SaveManager.best_score, SaveManager.top_scores.size()])


func _phase_read() -> void:
	print("\n=== F10 restart, phase 2: reading in a fresh process ===")
	SaveManager.use_path(TEST_PATH)

	_check("the best score survived a restart", SaveManager.best_score == RESTART_SCORE,
		"best is %d" % SaveManager.best_score)
	_check("the score table survived", SaveManager.top_scores.size() == 2,
		"%d scores" % SaveManager.top_scores.size())
	if SaveManager.top_scores.size() == 2:
		var top: Dictionary = SaveManager.top_scores[0]
		_check("the top entry kept its detail",
			int(top["score"]) == RESTART_SCORE
				and int(top["highest_tier"]) == RESTART_TIER
				and int(top["longest_chain"]) == RESTART_CHAIN,
			"top entry is %s" % str(top))
	_check("lifetime stats survived",
		int(SaveManager.stats["games_played"]) == 2
			and int(SaveManager.stats["total_merges"]) == 48
			and int(SaveManager.stats["tier12_pops"]) == 2,
		"stats %s" % str(SaveManager.stats))
	_check("GameState reads the same best", GameState.best_score == RESTART_SCORE,
		"GameState says %d" % GameState.best_score)

	print("%d checks failed\n" % _failures if _failures > 0 else "restart checks passed\n")


# --- in-process pass -----------------------------------------------------------------------------

func _run_tests() -> void:
	print("\n=== F10 persistence ===")
	SaveManager.use_path(TEST_PATH)

	_case_defaults()
	_case_ordering_and_trimming()
	_case_atomic_write()
	_case_corrupt_file()
	_case_truncated_file()
	_case_wrong_version()
	_case_hostile_shapes()

	SaveManager.clear()
	print("%d checks failed\n" % _failures if _failures > 0 else "all checks passed\n")


func _case_defaults() -> void:
	SaveManager.clear()
	SaveManager.load_game()
	_check("a missing file loads as defaults",
		SaveManager.best_score == 0 and SaveManager.top_scores.is_empty(),
		"best %d, %d scores" % [SaveManager.best_score, SaveManager.top_scores.size()])


## The table holds ten, sorted best first, and drops the worst when a better one arrives.
func _case_ordering_and_trimming() -> void:
	SaveManager.clear()
	for i in 15:
		SaveManager.record_run(100 * (i + 1), 3, 1, 2, 0)

	_check("the table keeps only the top ten",
		SaveManager.top_scores.size() == Tuning.TOP_SCORES_COUNT,
		"%d entries" % SaveManager.top_scores.size())

	var descending := true
	for i in range(1, SaveManager.top_scores.size()):
		if int(SaveManager.top_scores[i - 1]["score"]) < int(SaveManager.top_scores[i]["score"]):
			descending = false
	_check("the table is sorted best first", descending, "out of order")
	_check("the worst entries were dropped",
		int(SaveManager.top_scores[SaveManager.top_scores.size() - 1]["score"]) == 600,
		"lowest kept is %d" % int(SaveManager.top_scores[-1]["score"]))
	_check("the best is the best", SaveManager.best_score == 1500,
		"best %d" % SaveManager.best_score)
	_check("games played counts every run",
		int(SaveManager.stats["games_played"]) == 15,
		"%d games" % int(SaveManager.stats["games_played"]))


## The temporary file must not be left lying around.
func _case_atomic_write() -> void:
	SaveManager.save()
	_check("the save file exists", FileAccess.file_exists(TEST_PATH), "no file")
	_check("no temporary file is left behind",
		not FileAccess.file_exists(TEST_PATH + ".tmp"), "the .tmp survived")


func _case_corrupt_file() -> void:
	_write_raw("this is not JSON at all {{{")
	SaveManager.load_game()
	_check("garbage loads as defaults, not a crash",
		SaveManager.best_score == 0 and SaveManager.top_scores.is_empty(),
		"best %d" % SaveManager.best_score)


## Exactly what an interrupted write used to look like before the rename dance.
func _case_truncated_file() -> void:
	_write_raw('{"version": 1, "best_score": 900, "top_sc')
	SaveManager.load_game()
	_check("a half-written file loads as defaults", SaveManager.best_score == 0,
		"best %d" % SaveManager.best_score)


func _case_wrong_version() -> void:
	_write_raw('{"version": 99, "best_score": 5000, "top_scores": [], "stats": {}}')
	SaveManager.load_game()
	_check("a save from the future is not trusted", SaveManager.best_score == 0,
		"best %d" % SaveManager.best_score)


## Right version, right keys, wrong types throughout — nothing here may throw.
func _case_hostile_shapes() -> void:
	_write_raw('{"version": 1, "best_score": "lots", "top_scores": "nope", "stats": 7}')
	SaveManager.load_game()
	_check("a string best score becomes zero", SaveManager.best_score == 0,
		"best %d" % SaveManager.best_score)
	_check("a non-array score table becomes empty", SaveManager.top_scores.is_empty(),
		"%d scores" % SaveManager.top_scores.size())
	_check("non-dictionary stats become defaults",
		int(SaveManager.stats["games_played"]) == 0, "stats %s" % str(SaveManager.stats))

	_write_raw('{"version": 1, "best_score": 300, "top_scores": [1, "two", {"nope": 1], "stats": {}}')
	SaveManager.load_game()
	_check("a malformed table does not crash the load", SaveManager.top_scores.is_empty(),
		"%d scores" % SaveManager.top_scores.size())

	_write_raw('{"version": 1, "best_score": 0, "top_scores": [{"score": 700}], "stats": {}}')
	SaveManager.load_game()
	_check("a partial entry is filled in", SaveManager.top_scores.size() == 1
		and int(SaveManager.top_scores[0]["highest_tier"]) == 0, "entry lost")
	_check("a best score behind the table is corrected upward", SaveManager.best_score == 700,
		"best %d" % SaveManager.best_score)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s (%s)" % [label, detail])
