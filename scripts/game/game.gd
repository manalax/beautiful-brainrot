## The play scene: the table, the launcher, the merge resolver, the spawn queue and the HUD, wired
## together. This is the run.
##
## Everything below is connection, not logic. The pieces each own their own rules — the queue
## decides what comes next, the resolver decides what merges, GameState decides what it is worth —
## and this holds the wires between them so none of them has to know about the others.
class_name Game
extends Node2D

## The run is over. The game-over overlay listens.
signal run_ended(score: int, is_best: bool)
## The player is done with this scene. Main switches back to the menu.
signal quit_to_menu

@onready var _pieces: Node2D = $Pieces
@onready var _resolver: MergeResolver = $MergeResolver
@onready var _launcher: Launcher = $Launcher
@onready var _queue: SpawnQueue = $SpawnQueue
@onready var _popups: ScorePopups = $ScorePopups
@onready var _sparks: HitSparks = $HitSparks
@onready var _hud: Hud = $UI/Hud
@onready var _table: Node2D = $Table
@onready var _danger: DangerZone = $DangerZone
@onready var _pause_menu: PauseMenu = $UI/PauseMenu
@onready var _game_over: GameOver = $UI/GameOver


func _ready() -> void:
	_queue.next_changed.connect(_hud.show_next)
	_launcher.needs_piece.connect(_on_needs_piece)
	_launcher.fired.connect(_on_fired)
	_resolver.merged.connect(_on_merged)
	_resolver.annihilated.connect(_on_annihilated)
	GameState.score_changed.connect(_hud.set_score)
	_danger.triggered.connect(_on_danger_triggered)
	_danger.danger_changed.connect(_table.set_danger_intensity)

	_hud.pause_pressed.connect(_pause_menu.open)
	_pause_menu.quit_pressed.connect(quit_to_menu.emit)
	_game_over.retry_pressed.connect(_on_retry)
	_game_over.menu_pressed.connect(quit_to_menu.emit)
	run_ended.connect(_game_over.open)
	GameState.run_ended.connect(_on_state_run_ended)

	start_run()


## Begins a fresh run. Pass a seed to replay one.
func start_run(seed_value: int = 0) -> void:
	# Order matters: the launcher lets go of its held piece before the table is emptied, or it
	# would be left holding a freed one. The chain has to reset too, or the first merge of the
	# new run scores at the multiplier the last run left behind.
	_launcher.reset()
	_resolver.reset_chain()
	for child in _pieces.get_children():
		child.queue_free()
	_popups.clear()
	_sparks.clear()

	# The queue must be ready before the launcher's deferred first request arrives.
	_queue.start(seed_value)
	_danger.rearm()
	_game_over.hide()
	_hud.set_pause_available(true)
	GameState.start_run()
	_hud.set_best(GameState.best_score)


## Ends the run: the lane stops watching, the launcher stops listening, and every piece is stopped
## where it is. The pieces are frozen individually rather than the tree being paused, so the HUD,
## the popups and F9's overlay all stay alive over a still board.
func _on_danger_triggered(_piece: Piece) -> void:
	end_run()


func end_run() -> void:
	if not GameState.is_running():
		return

	_danger.disarm()
	_launcher.set_active(false)
	for child in _pieces.get_children():
		var piece := child as Piece
		if piece != null:
			piece.freeze_in_place()
	_table.set_danger_intensity(0.0)
	_hud.set_pause_available(false)

	# GameState commits the run — which is what writes the save — and reports back whether it was
	# a best. Taking that from the signal rather than working it out here keeps one answer.
	GameState.end_run()


func _on_state_run_ended(score: int, is_best: bool) -> void:
	# The best has just been promoted if this beat it, so the HUD would otherwise still read the
	# old number behind an overlay announcing a new one.
	_hud.set_best(GameState.best_score)
	run_ended.emit(score, is_best)


func _on_retry() -> void:
	start_run()


func _on_needs_piece() -> void:
	_launcher.load_piece(_queue.take())


func _on_fired(_piece: Piece, _direction: Vector2, _power: float) -> void:
	# Chain depth belongs to the shot, so it resets here rather than on a timer: a shot that
	# ricochets and merges seconds later still counts toward that shot.
	_resolver.reset_chain()
	GameState.register_shot()


func _on_merged(tier: int, position: Vector2, chain_depth: int) -> void:
	_popups.show_points(position, GameState.add_merge(tier, chain_depth), chain_depth)
	if chain_depth > 0:
		_hud.punch_score()


func _on_annihilated(position: Vector2, chain_depth: int) -> void:
	_popups.show_points(position, GameState.add_annihilation(chain_depth), chain_depth)
	_hud.punch_score()


# --- accessors, for the harnesses and for F8/F9 --------------------------------------------------

func pieces_root() -> Node2D:
	return _pieces


func launcher() -> Launcher:
	return _launcher


func resolver() -> MergeResolver:
	return _resolver


func spawn_queue() -> SpawnQueue:
	return _queue


func hud() -> Hud:
	return _hud


func danger_zone() -> DangerZone:
	return _danger


func pause_menu() -> PauseMenu:
	return _pause_menu


func game_over_overlay() -> GameOver:
	return _game_over
