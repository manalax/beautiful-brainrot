## Dev harness for F7: checks the score model against the arithmetic written down in §10, by hand,
## then plays a real chain through the real play scene and confirms the total.
##
## Not part of the game. Run `res://scenes/game/score_test.tscn` directly. It embeds `game.tscn`,
## so after the automated pass it is simply the game — drag, aim, release, watch the score.
##
## Set F7_SHOT to a .png path to screenshot a scored table and exit.
extends Node2D

const SETTLE_TIMEOUT := 8.0

@onready var _game: Game = $Game

var _tiers: TierSet = null
var _failures := 0


func _ready() -> void:
	_tiers = TierSet.load_default()
	await get_tree().process_frame
	await _run_tests()
	await _capture_screenshot()


func _run_tests() -> void:
	print("\n=== F7 scoring ===")
	_check_reference_values()
	_check_multipliers()
	_check_worked_example()
	await _check_real_chain()
	print("%d checks failed\n" % _failures if _failures > 0 else "all checks passed\n")


## The reference values §10 lists, so a change to the model has to be a deliberate one.
func _check_reference_values() -> void:
	var expected := {2: 40, 5: 250, 8: 640, 12: 1440}
	for tier: int in expected:
		var points := GameState.points_for_merge(tier, 0)
		_check("tier %d merge is worth %d" % [tier, expected[tier]], points == expected[tier],
			"got %d" % points)

	var pop := GameState.points_for_annihilation(0)
	_check("a tier-12 pop is worth %d" % Tuning.TIER12_BONUS, pop == Tuning.TIER12_BONUS,
		"got %d" % pop)


func _check_multipliers() -> void:
	var expected := [1.0, 1.5, 2.0, 2.5, 3.0]
	var ok := true
	for depth in expected.size():
		ok = ok and is_equal_approx(GameState.chain_multiplier(depth), expected[depth])
	_check("the multiplier table matches §10", ok, "table diverged")

	_check("the multiplier caps rather than running away",
		is_equal_approx(GameState.chain_multiplier(9), expected[expected.size() - 1]),
		"depth 9 gave x%.2f" % GameState.chain_multiplier(9))


## The exact worked example from §10: 90 x1, then 160 x1.5, then 250 x2 — 830 for the shot.
func _check_worked_example() -> void:
	var first := GameState.points_for_merge(3, 0)
	var second := GameState.points_for_merge(4, 1)
	var third := GameState.points_for_merge(5, 2)

	_check("worked example, tier 3 at depth 0 is 90", first == 90, "got %d" % first)
	_check("worked example, tier 4 at depth 1 is 240", second == 240, "got %d" % second)
	_check("worked example, tier 5 at depth 2 is 500", third == 500, "got %d" % third)
	_check("worked example totals 830", first + second + third == 830,
		"got %d" % (first + second + third))


## The same arithmetic, but earned: one shot chaining two merges through the real scene.
##
## A tier-1 shot into a resting tier-1 makes a tier 2 at depth 0, worth 2*2*10 = 40. That tier 2
## carries on into a resting tier 2 and makes a tier 3 at depth 1, worth 3*3*10 x1.5 = 135.
## The run should end on 175.
func _check_real_chain() -> void:
	_game.start_run(20260831)
	await get_tree().process_frame

	_spawn(1, Vector2(540.0, 1300.0))
	_spawn(2, Vector2(540.0, 1050.0))
	await get_tree().physics_frame

	var shot := _spawn(1, Vector2(540.0, Tuning.LAUNCHER_Y))
	_game.resolver().reset_chain()
	GameState.register_shot()
	shot.launch(Vector2.UP * Tuning.SPEED_MAX * shot.mass)

	await _settle()

	_check("the chain scored 40 + 135", GameState.score == 175, "score %d" % GameState.score)
	_check("two merges were counted", GameState.total_merges == 2,
		"%d merges" % GameState.total_merges)
	_check("the longest chain was 2", GameState.longest_chain == 2,
		"longest %d" % GameState.longest_chain)
	_check("the highest tier reached was 3", GameState.highest_tier == 3,
		"highest %d" % GameState.highest_tier)
	_check("the HUD shows the score",
		_game.hud().shown_next_tier() == _game.spawn_queue().peek_next().tier,
		"swatch out of step with the queue")

	var summary := "  score %d from %d merges, longest chain %d, highest tier %d" % [
		GameState.score, GameState.total_merges, GameState.longest_chain, GameState.highest_tier]

	# A restart has to leave nothing of the last run behind — this is what F9's Retry will do.
	_game.start_run(20260901)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a restart clears the score", GameState.score == 0, "score %d" % GameState.score)
	_check("a restart clears the chain", _game.resolver().chain_depth == 0,
		"depth %d" % _game.resolver().chain_depth)
	_check("a restart clears the table", _game.pieces_root().get_child_count() == 1,
		"%d pieces" % _game.pieces_root().get_child_count())
	_check("a restart reloads the launcher", _game.launcher().loaded_piece() != null,
		"nothing held")
	_check("the reloaded piece is real",
		is_instance_valid(_game.launcher().loaded_piece()), "the held piece was freed")

	print(summary)


func _spawn(tier: int, position: Vector2) -> Piece:
	var piece := MergeResolver.PIECE_SCENE.instantiate() as Piece
	piece.position = position
	_game.pieces_root().add_child(piece)
	piece.setup(_tiers.get_tier(tier))
	return piece


func _settle() -> void:
	var waited := 0.0
	var still := 0
	while waited < SETTLE_TIMEOUT:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		var moving := false
		for child in _game.pieces_root().get_children():
			var piece := child as Piece
			if piece != null and not piece.is_at_rest():
				moving = true
				break
		still = still + 1 if not moving else 0
		if still > 12:
			return


func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s (%s)" % [label, detail])


## Catches the merge flash with the spawn pop, and the wall spark on the frame after impact.
## Both are brief by design, so these are timed rather than waited out.
func _capture_juice() -> void:
	var merge_path := OS.get_environment("F11_SHOT")
	var spark_path := OS.get_environment("F11_SPARK_SHOT")
	if merge_path.is_empty() and spark_path.is_empty():
		return

	if not spark_path.is_empty():
		_game.start_run(20260831)
		await get_tree().process_frame
		var struck := [false]
		var runner := _spawn(4, Vector2(460.0, 1350.0))
		runner.hit_wall.connect(func(_p: Vector2, _n: Vector2, _s: float) -> void:
			struck[0] = true)
		runner.launch(Vector2(0.72, -0.69).normalized() * Tuning.SPEED_MAX * runner.mass)
		var waited := 0.0
		while not struck[0] and waited < 4.0:
			await get_tree().physics_frame
			waited += 1.0 / Engine.physics_ticks_per_second
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(spark_path)
		print("capture wrote %s (struck %s)" % [spark_path, struck[0]])

	if not merge_path.is_empty():
		_game.start_run(20260831)
		await get_tree().process_frame
		_spawn(7, Vector2(360.0, 760.0))
		_spawn(9, Vector2(730.0, 1230.0))
		var left := _spawn(5, Vector2(470.0, 1020.0))
		var right := _spawn(5, Vector2(640.0, 1020.0))
		right.inherit_velocity(Vector2(-900.0, 0.0))
		left.inherit_velocity(Vector2(200.0, 0.0))

		var seen := GameState.total_merges
		var waited := 0.0
		while GameState.total_merges == seen and waited < 4.0:
			await get_tree().physics_frame
			waited += 1.0 / Engine.physics_ticks_per_second
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(merge_path)
		print("capture wrote %s" % merge_path)

	get_tree().quit()


## Scores a few merges across the table so the shot shows the HUD and a popup at once.
func _capture_screenshot() -> void:
	await _capture_juice()
	var path := OS.get_environment("F7_SHOT")
	if path.is_empty():
		return

	_game.start_run(20260831)
	await get_tree().process_frame
	_spawn(4, Vector2(360.0, 780.0))
	_spawn(6, Vector2(720.0, 980.0))
	_spawn(3, Vector2(470.0, 1240.0))

	var left := _spawn(5, Vector2(430.0, 560.0))
	var right := _spawn(5, Vector2(700.0, 560.0))
	right.inherit_velocity(Vector2(-500.0, 0.0))
	left.inherit_velocity(Vector2(300.0, 0.0))

	for i in 26:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("capture wrote %s (error %d)" % [path, error])
	get_tree().quit()
