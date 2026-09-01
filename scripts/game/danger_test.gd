## Dev harness for F8: checks that the launch lane is forgiving to anything passing through and
## fatal only to what settles there, that the warning arrives a full second early, and that the
## end of a run leaves the board still.
##
## Not part of the game. Run `res://scenes/game/danger_test.tscn` directly. Afterwards it is the
## game — park a shot in the lane and watch it start pulsing.
##
## Set F8_SHOT to a .png path to screenshot a piece mid-warning and exit.
extends Node2D

const TIMEOUT := 6.0

@onready var _game: Game = $Game

var _tiers: TierSet = null
var _failures := 0
var _ended := 0


func _ready() -> void:
	_tiers = TierSet.load_default()
	_game.run_ended.connect(func(_s: int, _b: bool) -> void: _ended += 1)
	await get_tree().process_frame
	await _run_tests()
	await _capture_screenshot()


func _run_tests() -> void:
	print("\n=== F8 danger zone ===")
	await _case_passing_through()
	await _case_resting_above_the_line()
	await _case_parked_in_the_lane()
	await _case_knocked_clear()
	await _case_holstered_piece_is_exempt()
	print("%d checks failed\n" % _failures if _failures > 0 else "all checks passed\n")


## Crossing the lane at speed must cost nothing.
func _case_passing_through() -> void:
	await _restart()
	var piece := _spawn(2, Vector2(120.0, 1760.0))
	piece.inherit_velocity(Vector2(1700.0, 0.0))

	var peak := 0.0
	var waited := 0.0
	while waited < 1.2:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		peak = maxf(peak, _game.danger_zone().resting_time(piece))

	_check("a piece crossing the lane never starts the clock", peak < 0.05,
		"clock reached %.2fs" % peak)
	_check("crossing the lane does not end the run", _ended == 0, "the run ended")


func _case_resting_above_the_line() -> void:
	await _restart()
	var piece := _spawn(3, Vector2(540.0, Tuning.DANGER_LINE_Y - 200.0))

	var waited := 0.0
	while waited < 2.6:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second

	_check("resting above the line is safe", _ended == 0, "the run ended")
	_check("and never warns", is_equal_approx(piece.danger, 0.0),
		"danger %.2f" % piece.danger)


## The rule itself: parked in the lane, warned for the last second, run over at the grace period.
func _case_parked_in_the_lane() -> void:
	await _restart()
	var piece := _spawn(2, Vector2(400.0, 1770.0))

	var warned_at := -1.0
	var ended_at := -1.0
	var elapsed := 0.0
	while elapsed < TIMEOUT and _ended == 0:
		await get_tree().physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
		if warned_at < 0.0 and is_instance_valid(piece) and piece.danger > 0.0:
			warned_at = elapsed
		if _ended > 0:
			ended_at = elapsed

	_check("parking in the lane ends the run", _ended == 1, "run ended %d times" % _ended)
	_check("it ends at the grace period",
		absf(ended_at - Tuning.DANGER_GRACE) < 0.15,
		"ended at %.2fs, grace is %.2fs" % [ended_at, Tuning.DANGER_GRACE])
	_check("the warning starts a full second early",
		absf(warned_at - Tuning.DANGER_WARNING_AT) < 0.15,
		"warned at %.2fs" % warned_at)
	_check("there is a full second of warning",
		ended_at - warned_at > 0.85, "only %.2fs of warning" % (ended_at - warned_at))
	print("  warned at %.2fs, ended at %.2fs" % [warned_at, ended_at])

	_check("the run is marked finished", not GameState.is_running(), "still running")
	_check("the board is frozen", _all_frozen(), "something is still loose")


## A piece rescued before the grace period runs out has to forget it was ever in trouble.
func _case_knocked_clear() -> void:
	await _restart()
	var piece := _spawn(2, Vector2(700.0, 1770.0))

	var waited := 0.0
	while waited < 1.4:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second

	var warned := piece.danger > 0.0
	piece.inherit_velocity(Vector2(0.0, -1500.0))

	waited = 0.0
	while waited < 1.5:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second

	_check("a piece in trouble does warn", warned, "it never warned")
	_check("shooting it clear saves the run", _ended == 0, "the run ended anyway")
	_check("and the clock resets",
		_game.danger_zone().resting_time(piece) < 0.05,
		"clock still at %.2fs" % _game.danger_zone().resting_time(piece))
	_check("and the warning clears", is_equal_approx(piece.danger, 0.0),
		"danger %.2f" % piece.danger)


## The piece waiting on the launcher lives in the lane by definition and must never count.
func _case_holstered_piece_is_exempt() -> void:
	await _restart()
	var held := _game.launcher().loaded_piece()
	_check("the launcher is holding a piece", held != null, "nothing held")

	var waited := 0.0
	while waited < Tuning.DANGER_GRACE + 0.8:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second

	_check("the held piece never ends the run", _ended == 0, "the run ended")
	if held != null:
		_check("the held piece never warns", is_equal_approx(held.danger, 0.0),
			"danger %.2f" % held.danger)


# --- helpers -------------------------------------------------------------------------------------

func _all_frozen() -> bool:
	for child in _game.pieces_root().get_children():
		var piece := child as Piece
		if piece != null and not piece.freeze:
			return false
	return true


func _spawn(tier: int, position: Vector2) -> Piece:
	var piece := MergeResolver.PIECE_SCENE.instantiate() as Piece
	piece.position = position
	_game.pieces_root().add_child(piece)
	piece.setup(_tiers.get_tier(tier))
	return piece


func _restart() -> void:
	_ended = 0
	_game.start_run(20260831)
	await get_tree().process_frame
	await get_tree().physics_frame


func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s (%s)" % [label, detail])


func _capture_screenshot() -> void:
	var path := OS.get_environment("F8_SHOT")
	if path.is_empty():
		return

	await _restart()
	_spawn(5, Vector2(620.0, 900.0))
	_spawn(3, Vector2(380.0, 1200.0))
	_spawn(4, Vector2(760.0, 1480.0))
	var doomed := _spawn(2, Vector2(330.0, 1770.0))

	# Hold until the warning is at its brightest, mid-pulse.
	while doomed.danger < 0.75:
		await get_tree().physics_frame
	while sin(Time.get_ticks_msec() / 1000.0 * TAU * Tuning.DANGER_PULSE_HZ) < 0.9:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("capture wrote %s (error %d)" % [path, error])
	get_tree().quit()
