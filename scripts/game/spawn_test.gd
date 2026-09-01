## Dev harness for F6: proves the two-slot queue's central promise — whatever the HUD is showing
## is exactly what loads next — plus the draw weighting and seeding.
##
## Not part of the game. Run `res://scenes/game/spawn_test.tscn` directly. The queue is wired to
## the launcher the way the play scene will wire it, so the automated pass fires real shots and
## checks what turns up. Afterwards it is playable: drag, aim, release, and watch the swatch.
##
## Run windowed, not headless: the pass drives synthetic touches, which are in screen coordinates.
extends Node2D

const SHOTS_TO_CHECK := 10
const DISTRIBUTION_SAMPLES := 20000
const RELOAD_TIMEOUT := 3.0

@onready var _launcher: Launcher = $Launcher
@onready var _queue: SpawnQueue = $SpawnQueue
@onready var _preview: NextPreview = $UI/NextPreview
@onready var _readout: Label = $UI/Readout

var _last_touch := Vector2.ZERO
var _failures := 0
var _shots := 0


func _ready() -> void:
	_queue.next_changed.connect(_preview.show_tier)
	_launcher.needs_piece.connect(_on_needs_piece)
	_launcher.fired.connect(func(_p: Piece, _d: Vector2, _pow: float) -> void: _shots += 1)
	# The queue must be started before the launcher's deferred first request arrives.
	_queue.start(20260831)
	# The launcher requests its first piece deferred, so nothing is held until a frame has passed.
	await get_tree().process_frame
	await _run_tests()


## The wiring the play scene will use: the launcher asks, the queue answers.
func _on_needs_piece() -> void:
	_launcher.load_piece(_queue.take())


func _run_tests() -> void:
	print("\n=== F6 spawn queue ===")
	print("run seed: %d" % _queue.run_seed)

	_check("both slots fill once the first piece is taken",
		_queue.current() != null and _queue.peek_next() != null, "a slot was empty")
	_check("the launcher loaded the first piece", _launcher.loaded_piece() != null, "nothing held")
	_check("the swatch shows the next piece",
		_preview.shown_tier() == _queue.peek_next().tier,
		"swatch %d, queue %d" % [_preview.shown_tier(), _queue.peek_next().tier])

	_check_pool()
	_check_distribution()
	_check_seeding()
	await _check_preview_matches()

	print("%d checks failed\n" % _failures if _failures > 0 else "all checks passed\n")
	await _capture_screenshot()


func _capture_screenshot() -> void:
	var path := OS.get_environment("F6_SHOT")
	if path.is_empty():
		return
	await _await_ready()
	for i in 20:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("capture wrote %s (error %d)" % [path, error])
	get_tree().quit()


## Nothing outside the spawn pool may ever be drawn.
func _check_pool() -> void:
	var queue := SpawnQueue.new()
	add_child(queue)
	queue.start(7)

	var lowest := Tuning.MAX_TIER
	var highest := 0
	for i in 5000:
		var tier := queue.take().tier
		lowest = mini(lowest, tier)
		highest = maxi(highest, tier)

	_check("only the spawn pool is drawn",
		lowest == 1 and highest == Tuning.SPAWN_TIER_WEIGHTS.size(),
		"saw tiers %d..%d" % [lowest, highest])
	queue.queue_free()


## The draw should follow SPAWN_TIER_WEIGHTS, not be flat.
func _check_distribution() -> void:
	var queue := SpawnQueue.new()
	add_child(queue)
	queue.start(99)

	var counts := PackedInt32Array()
	counts.resize(Tuning.SPAWN_TIER_WEIGHTS.size() + 1)
	for i in DISTRIBUTION_SAMPLES:
		counts[queue.take().tier] += 1

	var total_weight := 0
	for weight in Tuning.SPAWN_TIER_WEIGHTS:
		total_weight += weight

	print("tier  expected  observed")
	var worst := 0.0
	for tier in range(1, Tuning.SPAWN_TIER_WEIGHTS.size() + 1):
		var expected := float(Tuning.SPAWN_TIER_WEIGHTS[tier - 1]) / float(total_weight)
		var observed := float(counts[tier]) / float(DISTRIBUTION_SAMPLES)
		worst = maxf(worst, absf(observed - expected))
		print("%4d  %7.1f%%  %7.1f%%" % [tier, expected * 100.0, observed * 100.0])

	_check("draws follow the configured weights", worst < 0.015,
		"worst tier is %.1f%% off" % (worst * 100.0))
	queue.queue_free()


## A seed has to reproduce a run exactly, and different seeds must not agree.
func _check_seeding() -> void:
	var first := _sequence(4242, 40)
	var same := _sequence(4242, 40)
	var other := _sequence(4243, 40)

	_check("the same seed replays the same run", first == same, "sequences diverged")
	_check("a different seed gives a different run", first != other, "sequences matched")


func _sequence(seed_value: int, count: int) -> PackedInt32Array:
	var queue := SpawnQueue.new()
	add_child(queue)
	queue.start(seed_value)
	var out := PackedInt32Array()
	for i in count:
		out.append(queue.take().tier)
	queue.queue_free()
	return out


## The acceptance criterion: fire repeatedly, and every time confirm the piece that arrives is the
## one the swatch was advertising before the shot.
func _check_preview_matches() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if not viewport_size.is_equal_approx(Tuning.DESIGN_SIZE):
		print("preview-matches check skipped: run windowed, not headless")
		return

	var mismatches := 0
	for i in SHOTS_TO_CHECK:
		await _await_ready()
		var advertised := _preview.shown_tier()
		var queued := _queue.peek_next().tier
		if advertised != queued:
			mismatches += 1

		await _fire()
		await _await_ready()

		var loaded := _launcher.loaded_piece()
		if loaded == null or loaded.tier != advertised:
			mismatches += 1
			printerr("  shot %d: swatch advertised %d, launcher loaded %s"
				% [i + 1, advertised, str(loaded.tier) if loaded != null else "nothing"])

	_check("the swatch always matches what loads next", mismatches == 0,
		"%d mismatches over %d shots" % [mismatches, SHOTS_TO_CHECK])
	_check("every shot actually fired", _shots == SHOTS_TO_CHECK,
		"%d shots for %d attempts" % [_shots, SHOTS_TO_CHECK])


func _await_ready() -> void:
	var waited := 0.0
	while _launcher.state != Launcher.State.READY and waited < RELOAD_TIMEOUT:
		await get_tree().process_frame
		waited += 1.0 / 60.0


func _fire() -> void:
	var start := Vector2(540.0, 1500.0)
	await _dispatch_touch(start, true)
	await _dispatch_drag(start + Vector2(0.0, Tuning.AIM_DEADZONE + 120.0))
	await _dispatch_touch(_last_touch, false)


func _dispatch_touch(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	_last_touch = position
	await _dispatch(event)


func _dispatch_drag(position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	event.relative = position - _last_touch
	_last_touch = position
	await _dispatch(event)


## Parsed events are buffered and flushed at the start of the next iteration, so one frame of
## waiting is not enough for the launcher to have seen them.
func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s (%s)" % [label, detail])


func _process(_delta: float) -> void:
	var held := _launcher.loaded_piece()
	_readout.text = "F6 spawn queue — drag, aim, release. seed %d\nheld: %s   next: %d   shots: %d" % [
		_queue.run_seed,
		str(held.tier) if held != null else "-",
		_preview.shown_tier(),
		_shots,
	]
