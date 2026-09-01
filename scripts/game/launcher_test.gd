## Dev harness for F3 and F4: drives the launcher's place-aim-fire gesture with synthetic touch
## events and checks each transition, then checks the aim guide's prediction against where a shot
## really goes, then hands the table over for manual play.
##
## Not part of the game. Run `res://scenes/game/launcher_test.tscn` directly. After the automated
## pass, drag anywhere below the HUD band to place, drag past the deadzone to aim, release to
## fire. The readout reports the live state, so the deadzone lock and the cancel are visible.
##
## Set F3_SHOT or F4_SHOT to a .png path to screenshot a held bank-shot aim and exit.
extends Node2D

const MEASURE_TIMEOUT := 5.0

@onready var _launcher: Launcher = $Launcher
@onready var _pieces: Node2D = $Pieces
@onready var _readout: Label = $UI/Readout

var _tiers: TierSet = null
var _rng := RandomNumberGenerator.new()
var _last_touch := Vector2.ZERO
var _failures := 0


func _ready() -> void:
	_tiers = TierSet.load_default()
	# Fixed seed: the checks below assert on radii, so the harness must draw the same pieces
	# every run. The game itself seeds per run (§9).
	_rng.seed = 20260831
	_launcher.needs_piece.connect(_on_needs_piece)
	_launcher.aim_changed.connect(_on_aim_changed)
	await _run_gesture_tests()
	await _run_aim_guide_tests()
	await _capture_screenshot()


## Answers the launcher's request for something to fire. F6 replaces this with the real weighted
## two-slot queue; here it is a flat random draw from the spawn pool.
func _on_needs_piece() -> void:
	var tier := _rng.randi_range(1, Tuning.SPAWN_TIER_WEIGHTS.size())
	_launcher.load_piece(_tiers.get_tier(tier))


# --- automated gesture pass ---------------------------------------------------------------------

func _run_gesture_tests() -> void:
	print("\n=== F3 launcher gesture ===")
	await get_tree().process_frame  # let the deferred first needs_piece land

	# Synthetic touches are given in screen coordinates, which only equal design coordinates when
	# the viewport is the design size. Headless gives a square viewport, and the stretch transform
	# then skews every position — so the pass is meaningless there rather than merely failing.
	var viewport_size := get_viewport().get_visible_rect().size
	if not viewport_size.is_equal_approx(Tuning.DESIGN_SIZE):
		print("skipped: needs a %v viewport, got %v — run this windowed, not headless\n"
			% [Tuning.DESIGN_SIZE, viewport_size])
		return

	_check("starts loaded and ready", _launcher.state == Launcher.State.READY,
		"state=%s" % _state_name())

	# The HUD band is not aimable surface.
	await _touch(Vector2(540.0, 100.0), true)
	_check("touch on the HUD is ignored", _launcher.state == Launcher.State.READY,
		"state=%s" % _state_name())
	await _touch(Vector2(540.0, 100.0), false)

	# Touch down places the launcher under the finger.
	await _touch(Vector2(300.0, 1500.0), true)
	_check("touch enters PLACING", _launcher.state == Launcher.State.PLACING,
		"state=%s" % _state_name())
	_check("launcher snaps to the touch", is_equal_approx(_launcher.position.x, 300.0),
		"x=%.1f" % _launcher.position.x)

	# Inside the deadzone the launcher keeps following the finger.
	await _drag(Vector2(312.0, 1500.0))
	_check("small drag stays in PLACING", _launcher.state == Launcher.State.PLACING,
		"state=%s" % _state_name())
	_check("launcher still follows", is_equal_approx(_launcher.position.x, 312.0),
		"x=%.1f" % _launcher.position.x)

	# Crossing the deadzone locks x and starts aiming.
	var locked_x := _launcher.position.x
	await _drag(Vector2(300.0, 1600.0))
	_check("crossing the deadzone enters AIMING", _launcher.state == Launcher.State.AIMING,
		"state=%s" % _state_name())
	_check("launcher x locks", is_equal_approx(_launcher.position.x, locked_x),
		"x=%.1f, expected %.1f" % [_launcher.position.x, locked_x])

	var expected_power := (100.0 - Tuning.AIM_DEADZONE) / Tuning.DRAG_MAX
	_check("aims opposite the drag", _aim_direction().is_equal_approx(Vector2.UP),
		"dir=%v" % _aim_direction())
	_check("power ramps from zero at the deadzone",
		absf(_aim_power() - expected_power) < 0.01,
		"power=%.3f, expected %.3f" % [_aim_power(), expected_power])

	# Dragging back inside the deadzone cancels the shot.
	await _drag(Vector2(305.0, 1505.0))
	_check("dragging back cancels to PLACING", _launcher.state == Launcher.State.PLACING,
		"state=%s" % _state_name())
	_check("cancelled launcher follows again", is_equal_approx(_launcher.position.x, 305.0),
		"x=%.1f" % _launcher.position.x)

	# Long drag saturates power.
	await _drag(Vector2(300.0, 1900.0))
	_check("long drag saturates power", is_equal_approx(_aim_power(), 1.0),
		"power=%.3f" % _aim_power())

	var before := _pieces.get_child_count()
	await _touch(Vector2(300.0, 1900.0), false)
	_check("release fires", _launcher.state == Launcher.State.COOLDOWN,
		"state=%s" % _state_name())
	_check("the piece is now live", _pieces.get_child_count() == before,
		"%d pieces" % _pieces.get_child_count())

	await get_tree().physics_frame
	await get_tree().physics_frame
	var shot := _pieces.get_child(_pieces.get_child_count() - 1) as Piece
	_check("fired at full power", shot.linear_velocity.length() > Tuning.SPEED_MAX * 0.9,
		"speed=%.0f" % shot.linear_velocity.length())
	_check("fired along the aim", shot.linear_velocity.normalized().dot(Vector2.UP) > 0.99,
		"velocity=%v" % shot.linear_velocity)

	# Cooldown blocks input, then reloads.
	await _touch(Vector2(500.0, 1500.0), true)
	_check("cooldown ignores touches", _launcher.state == Launcher.State.COOLDOWN,
		"state=%s" % _state_name())
	await _touch(Vector2(500.0, 1500.0), false)

	await _wait(Tuning.SHOT_COOLDOWN + 0.2)
	_check("reloads after the cooldown", _launcher.state == Launcher.State.READY,
		"state=%s" % _state_name())
	_check("a new piece is holstered", _launcher.loaded_piece() != null, "none loaded")

	# A tap that never leaves the deadzone must not fire.
	var count := _pieces.get_child_count()
	await _touch(Vector2(400.0, 1500.0), true)
	await _touch(Vector2(400.0, 1500.0), false)
	_check("a tap does not fire", _launcher.state == Launcher.State.READY,
		"state=%s" % _state_name())
	_check("a tap leaves the piece holstered", _pieces.get_child_count() == count,
		"%d pieces, expected %d" % [_pieces.get_child_count(), count])

	# The loaded piece must stay fully inside the playfield.
	await _touch(Vector2(0.0, 1500.0), true)
	var radius := _launcher.loaded_piece().radius
	var left_limit := Tuning.PLAYFIELD_RECT.position.x + radius
	_check("clamps to the left wall", is_equal_approx(_launcher.position.x, left_limit),
		"x=%.1f, expected %.1f" % [_launcher.position.x, left_limit])
	await _touch(Vector2(0.0, 1500.0), false)

	print("%d checks failed\n" % _failures if _failures > 0 else "all checks passed\n")


## F4: the guide has to agree with the physics, most of all on the bank shot it exists to help
## with. Each case aims precisely by computing the drag that produces the wanted direction and
## power, reads the prediction, then fires and compares.
func _run_aim_guide_tests() -> void:
	print("=== F4 aim guide ===")

	var viewport_size := get_viewport().get_visible_rect().size
	if not viewport_size.is_equal_approx(Tuning.DESIGN_SIZE):
		print("skipped: needs a real window, same as the gesture pass\n")
		return

	var guide := _launcher.aim_guide()
	await _measure_wall_restitution()

	# --- open table: the line is just the length power asks for -------------------------------
	await _clear_pieces()
	await _reload()
	await _aim(540.0, Vector2.UP, 0.0)
	var path := guide.predicted_path()
	_check("open aim is a single segment", path.size() == 2, "%d points" % path.size())
	var expected_length := lerpf(
		Tuning.AIM_LINE_MIN_LENGTH, Tuning.AIM_LINE_MAX_LENGTH, _aim_pow)
	_check("line length tracks power",
		absf(path[0].distance_to(path[1]) - expected_length) < 2.0,
		"%.1f px, expected %.1f at power %.3f"
			% [path[0].distance_to(path[1]), expected_length, _aim_pow])
	_check("min drag is near zero power", _aim_pow < 0.01, "power=%.3f" % _aim_pow)
	_check("nothing is targeted", guide.predicted_target() == null, "a target was found")
	await _release()

	# --- a piece in the way: stop there and ring it --------------------------------------------
	await _wait(Tuning.SHOT_COOLDOWN + 0.1)
	await _clear_pieces()
	await _reload()
	var blocker := _spawn_blocker(Vector2(540.0, 1400.0), 6)
	await get_tree().physics_frame
	await _aim(540.0, Vector2.UP, 1.0)
	_check("targets the piece in the way", guide.predicted_target() == blocker,
		"target=%s" % guide.predicted_target())
	path = guide.predicted_path()
	var gap: float = path[path.size() - 1].distance_to(blocker.global_position)
	# Same cast_motion backoff as the wall-plane check below.
	_check("stops a radius short of it",
		absf(gap - (blocker.radius + _launcher.loaded_piece().radius)) < 5.0,
		"gap=%.1f px" % gap)
	await _release()
	blocker.queue_free()

	# --- the bank shot -------------------------------------------------------------------------
	await _wait(Tuning.SHOT_COOLDOWN + 0.1)
	await _clear_pieces()
	await _reload()
	var direction := Vector2(0.6, -0.8).normalized()
	await _aim(540.0, direction, 1.0)

	path = guide.predicted_path()
	_check("bank shot predicts a bounce", path.size() == 3,
		"%d points, state=%s power=%.3f" % [path.size(), _state_name(), _aim_pow])
	if path.size() != 3:
		print("")
		return

	var predicted_bounce := path[1]
	var predicted_after := (path[2] - path[1]).normalized()
	var shot := _launcher.loaded_piece()
	var wall_plane := Tuning.PLAYFIELD_RECT.end.x - shot.radius
	# cast_motion's safe fraction backs off a hair so the shapes never actually overlap.
	_check("bounce sits on the wall plane", absf(predicted_bounce.x - wall_plane) < 5.0,
		"x=%.1f, wall plane %.1f" % [predicted_bounce.x, wall_plane])

	await _release()

	# Fly it and find where it actually turned around. At 2600 px/s the piece covers ~43 px per
	# physics step, so sampling alone cannot locate the contact; instead take the last position
	# before the turn and run it forward along the incoming heading to the wall plane.
	var last_approaching := shot.global_position
	var actual_after := Vector2.ZERO
	var waited := 0.0
	while waited < MEASURE_TIMEOUT:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		if shot.linear_velocity.x < -1.0:
			actual_after = shot.linear_velocity.normalized()
			break
		last_approaching = shot.global_position

	var to_wall := (wall_plane - last_approaching.x) / direction.x
	var actual_bounce := last_approaching + direction * to_wall
	var bounce_error := actual_bounce.distance_to(predicted_bounce)
	var direction_dot := predicted_after.dot(actual_after)
	print("  predicted bounce %v, actual %v — %.1f px apart" % [
		predicted_bounce, actual_bounce, bounce_error])
	print("  predicted rebound %v, actual %v — dot %.4f" % [
		predicted_after, actual_after, direction_dot])
	_check("bounce point matches the real one", bounce_error < 10.0,
		"%.1f px apart" % bounce_error)
	_check("rebound direction matches", direction_dot > 0.99, "dot=%.4f" % direction_dot)

	print("%d checks failed\n" % _failures if _failures > 0 else "all checks passed\n")


## The guide's rebound model needs the restitution the engine actually applies, which is a
## combination of the piece's and the wall's materials rather than either one alone. Fire straight
## at a wall and read it off, so the constant the guide uses is pinned to measured behaviour.
func _measure_wall_restitution() -> void:
	await _clear_pieces()
	var piece := _spawn_blocker(Vector2(540.0, 1200.0), 1)
	await get_tree().physics_frame
	piece.launch(Vector2.UP * 1500.0 * piece.mass)

	var before := 0.0
	var after := 0.0
	var waited := 0.0
	while waited < MEASURE_TIMEOUT:
		var previous := piece.linear_velocity.y
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		if previous < 0.0 and piece.linear_velocity.y > 0.0:
			before = absf(previous)
			after = absf(piece.linear_velocity.y)
			break

	var restitution := after / before if before > 0.0 else 0.0
	print("  effective wall restitution: %.3f (piece %.2f + wall %.2f, Tuning says %.3f)" % [
		restitution, Tuning.PIECE_BOUNCE, Tuning.WALL_BOUNCE, Tuning.WALL_RESTITUTION])
	_check("Tuning's restitution matches the engine",
		absf(restitution - Tuning.WALL_RESTITUTION) < 0.03,
		"measured %.3f, Tuning %.3f" % [restitution, Tuning.WALL_RESTITUTION])
	await _clear_pieces()


## Frees everything on the table except the holstered piece, and waits for the physics server to
## catch up — otherwise the next shape query still finds the bodies that are on their way out.
func _clear_pieces() -> void:
	for child in _pieces.get_children():
		if child != _launcher.loaded_piece():
			child.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


## Aims at an exact direction and power by working backwards to the drag that produces them.
func _aim(launcher_x: float, direction: Vector2, power: float) -> void:
	var start := Vector2(launcher_x, 1500.0)
	await _touch(start, true)
	# A hair past the deadzone, never exactly on it: the window is scaled to fit the screen, so a
	# drag of exactly AIM_DEADZONE rounds to either side of the threshold from run to run.
	var distance := Tuning.AIM_DEADZONE + 1.0 + power * Tuning.DRAG_MAX
	await _drag(start - direction * distance)
	# The guide recomputes on the physics step after the event lands, so poll for the prediction
	# rather than betting on a frame count.
	var waited := 0.0
	while _launcher.aim_guide().predicted_path().is_empty() and waited < 1.0:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second


func _release() -> void:
	await _touch(_last_touch, false)


## Waits until the launcher has something holstered again.
func _reload() -> void:
	var waited := 0.0
	while _launcher.state != Launcher.State.READY and waited < MEASURE_TIMEOUT:
		await get_tree().process_frame
		waited += 1.0 / 60.0


func _spawn_blocker(position: Vector2, tier: int) -> Piece:
	var piece := preload("res://scenes/game/piece.tscn").instantiate() as Piece
	piece.position = position
	_pieces.add_child(piece)
	piece.setup(_tiers.get_tier(tier))
	return piece


func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s (%s)" % [label, detail])


func _state_name() -> String:
	return Launcher.State.keys()[_launcher.state]


# The launcher keeps its aim private; the harness listens for the last reported values.
var _aim_dir := Vector2.UP
var _aim_pow := 0.0


func _aim_direction() -> Vector2:
	return _aim_dir


func _aim_power() -> float:
	return _aim_pow


func _on_aim_changed(_origin: Vector2, direction: Vector2, power: float) -> void:
	_aim_dir = direction
	_aim_pow = power


# --- synthetic input -----------------------------------------------------------------------------

func _touch(position: Vector2, pressed: bool, index := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	_last_touch = position
	await _dispatch(event)


func _drag(position: Vector2, index := 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = position - _last_touch
	_last_touch = position
	await _dispatch(event)


## Parsed events are buffered and flushed at the start of the *next* iteration, so a single frame
## of waiting is not enough for the launcher to have seen them.
func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Sets up a bank shot with a piece in the rebound path, holds the aim, and shoots the frame —
## so the screenshot shows the dotted line, the bounce, the target ring and the power arc at once.
func _capture_screenshot() -> void:
	var path := OS.get_environment("F3_SHOT") if OS.has_environment("F3_SHOT") else OS.get_environment("F4_SHOT")
	if path.is_empty():
		return
	print("capturing to %s" % path)

	await _wait(Tuning.SHOT_COOLDOWN + 0.1)
	await _clear_pieces()
	await _reload()
	_spawn_blocker(Vector2(700.0, 900.0), 7)
	_spawn_blocker(Vector2(330.0, 1180.0), 4)
	await get_tree().physics_frame
	await _aim(540.0, Vector2(0.62, -0.78).normalized(), 1.0)

	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("capture wrote %s (error %d)" % [path, error])
	get_tree().quit()


func _process(_delta: float) -> void:
	var loaded := _launcher.loaded_piece()
	_readout.text = "F3/F4 launcher + aim guide — drag to place, past %dpx to aim, release to fire\n%s  x=%.0f  tier=%s  aim=%.2f  live=%d" % [
		int(Tuning.AIM_DEADZONE),
		_state_name(),
		_launcher.position.x,
		str(loaded.tier) if loaded != null else "-",
		_aim_pow,
		_pieces.get_child_count(),
	]
