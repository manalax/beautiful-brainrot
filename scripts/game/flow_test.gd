## Dev harness for F9: walks the whole loop — menu, game, loss, retry, loss, menu — pressing the
## real buttons, and checks that nothing is left behind between runs.
##
## Not part of the game. Run `res://scenes/game/flow_test.tscn` directly. It embeds `main.tscn`,
## so after the automated pass it simply is the game, from the title screen down.
##
## Set F9_SHOT to a .png path to screenshot the game-over overlay and exit.
extends Node2D

const TIMEOUT := 8.0

@onready var _main: Node = $Main

var _tiers: TierSet = null
var _failures := 0


const TEST_SAVE := "user://save_flow_test.json"


func _ready() -> void:
	_tiers = TierSet.load_default()
	# Never write to the real save from a test run.
	if OS.has_environment("F10_MENU_SHOT"):
		SaveManager.use_path("user://save_menu_shot.json")
		SaveManager.clear()
		for row in [[8420, 10, 5, 61, 1], [6180, 9, 4, 44, 0], [3990, 8, 3, 31, 0],
				[1250, 6, 2, 12, 0]]:
			SaveManager.record_run(row[0], row[1], row[2], row[3], row[4])
	else:
		SaveManager.use_path(TEST_SAVE)
		SaveManager.clear()
	await get_tree().process_frame
	if await _capture_menu():
		return
	await _run_tests()
	await _capture_screenshot()


## F9_MENU_SHOT captures the title screen instead of running the pass.
func _capture_menu() -> bool:
	var path := OS.get_environment("F9_MENU_SHOT") if OS.has_environment("F9_MENU_SHOT") else OS.get_environment("F10_MENU_SHOT")
	if path.is_empty():
		return false
	# The menu built itself before this harness seeded anything, so tell it to look again.
	_menu().refresh()
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("capture wrote %s" % path)
	get_tree().quit()
	return true


func _run_tests() -> void:
	print("\n=== F9 scene flow ===")

	# Baseline taken after one full pass, so first-time allocations are not counted as leaks.
	await _round_trip(false)
	var baseline := _orphans()
	var nodes_before := _node_count()

	await _round_trip(true)
	await _round_trip(true)

	var leaked := _orphans() - baseline
	var grew := _node_count() - nodes_before
	print("  orphan nodes %+d, live nodes %+d across two more round trips" % [leaked, grew])
	_check("no orphan nodes accumulate", leaked <= 0, "%d orphaned" % leaked)
	_check("the node count does not creep", grew <= 0, "%d extra nodes" % grew)
	_check("back at the menu", _menu() != null, "not on the menu")
	_check("the tree is not left paused", not get_tree().paused, "still paused")
	SaveManager.clear()

	print("%d checks failed\n" % _failures if _failures > 0 else "all checks passed\n")


## menu -> play -> lose -> retry -> lose -> menu, pressing the real buttons throughout.
##
## The save is wiped at the top of each trip so every trip ends with the same two scores on the
## menu. Without that the node count grows legitimately — three nodes per score row — and the leak
## measurement below cannot tell real growth from a leak.
func _round_trip(verbose: bool) -> void:
	SaveManager.clear()
	if _menu() != null:
		_menu().refresh()
	_expect(verbose, "starts on the menu", _menu() != null, "no menu")

	_menu().play_button().pressed.emit()
	await get_tree().process_frame
	var game := _game()
	_expect(verbose, "play opens the game", game != null, "no game scene")
	if game == null:
		return
	_expect(verbose, "a run is under way", GameState.is_running(), "not running")

	await _lose(game)
	_expect(verbose, "losing ends the run", not GameState.is_running(), "still running")
	_expect(verbose, "the overlay appears", game.game_over_overlay().visible, "no overlay")
	_expect(verbose, "the pause button goes away",
		not game.hud().get_node("PauseButton").visible, "pause still offered")

	game.game_over_overlay().retry_button().pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(verbose, "retry starts a new run", GameState.is_running(), "not running")
	_expect(verbose, "retry hides the overlay", not game.game_over_overlay().visible,
		"overlay still up")
	_expect(verbose, "retry clears the score", GameState.score == 0,
		"score %d" % GameState.score)
	_expect(verbose, "retry stays in the same scene", _game() == game, "the scene was rebuilt")

	# Pause and resume on the way, so that path is exercised too.
	game.hud().pause_pressed.emit()
	await get_tree().process_frame
	_expect(verbose, "pause opens and pauses the tree",
		game.pause_menu().visible and get_tree().paused, "not paused")
	game.pause_menu().resume_button().pressed.emit()
	await get_tree().process_frame
	_expect(verbose, "resume unpauses", not get_tree().paused, "still paused")

	await _lose(game)
	game.game_over_overlay().menu_button().pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(verbose, "menu returns to the title", _menu() != null, "not on the menu")

	# Both losses in this trip should have been committed, and the menu should be listing them.
	_expect(verbose, "both runs were saved", int(SaveManager.stats["games_played"]) == 2,
		"%d games recorded" % int(SaveManager.stats["games_played"]))
	_expect(verbose, "the menu lists them",
		_menu().get_node("Panel/Scores").get_child_count() == 2,
		"%d rows" % _menu().get_node("Panel/Scores").get_child_count())
	_expect(verbose, "the best score persisted", SaveManager.best_score >= 0,
		"best %d" % SaveManager.best_score)


## Parks a piece in the launch lane and waits for the grace period to run out.
func _lose(game: Game) -> void:
	var piece := MergeResolver.PIECE_SCENE.instantiate() as Piece
	piece.position = Vector2(300.0, 1770.0)
	game.pieces_root().add_child(piece)
	piece.setup(_tiers.get_tier(2))

	var waited := 0.0
	while GameState.is_running() and waited < TIMEOUT:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
	await get_tree().process_frame


func _menu() -> MainMenu:
	return _main.current_scene() as MainMenu


func _game() -> Game:
	return _main.current_scene() as Game


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _expect(verbose: bool, label: String, passed: bool, detail: String) -> void:
	if verbose or not passed:
		_check(label, passed, detail)


func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s (%s)" % [label, detail])


func _capture_screenshot() -> void:
	var path := OS.get_environment("F9_SHOT")
	if path.is_empty():
		return

	_menu().play_button().pressed.emit()
	await get_tree().process_frame
	var game := _game()

	# Earn a score worth showing before losing.
	for pair in [[5, 430.0, 620.0], [5, 660.0, 620.0], [3, 520.0, 1000.0], [3, 700.0, 1010.0]]:
		var piece := MergeResolver.PIECE_SCENE.instantiate() as Piece
		piece.position = Vector2(pair[1], pair[2])
		game.pieces_root().add_child(piece)
		piece.setup(_tiers.get_tier(int(pair[0])))
	await get_tree().physics_frame
	for child in game.pieces_root().get_children():
		var piece := child as Piece
		if piece != null and not piece.freeze and piece.position.x > 600.0:
			piece.inherit_velocity(Vector2(-700.0, 0.0))

	for i in 90:
		await get_tree().physics_frame
	await _lose(game)
	# Fewer frames when we want the overlay caught part-way through its fade.
	for i in (4 if OS.has_environment("F11_MIDFADE") else 20):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("capture wrote %s (error %d)" % [path, error])
	get_tree().quit()
