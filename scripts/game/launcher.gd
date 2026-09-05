## The launcher: where the next piece sits, and the whole place-aim-fire gesture.
##
## One continuous touch does two jobs (GAME_DESIGN.md §7). While the finger is inside the aim
## deadzone the launcher slides along the bottom edge to follow it, which is the placement half.
## Once the finger travels past the deadzone the launcher's x locks and the same drag becomes a
## slingshot: direction is opposite the drag, power grows with its length.
##
## The launcher does not own the piece supply. It asks for one with `needs_piece` and waits;
## F6's spawn queue answers. That keeps the queue's weighting and preview out of here.
class_name Launcher
extends Node2D

const PIECE_SCENE := preload("res://scenes/game/piece.tscn")

enum State {
	EMPTY,     ## Nothing loaded. Waiting on `needs_piece` to be answered.
	READY,     ## Loaded and idle, waiting for a touch.
	PLACING,   ## Finger down, still inside the deadzone: sliding along the lane.
	AIMING,    ## Past the deadzone: x is locked and the drag is a slingshot.
	COOLDOWN,  ## Just fired; reloading.
}

## A piece has been launched. `power` is 0..1.
signal fired(piece: Piece, direction: Vector2, power: float)
## The cooldown finished (or the launcher just started). Answer with `load_piece()`.
signal needs_piece
## Aim updated while AIMING. F4's guide draws from this; nothing else needs it.
signal aim_changed(origin: Vector2, direction: Vector2, power: float)
## Aiming stopped, whether by firing or by cancelling.
signal aim_ended

## Where fired pieces are parented. Defaults to this node's parent.
@export var pieces_root_path: NodePath

@onready var _guide: AimGuide = $AimGuide

var state: State = State.EMPTY

## False once the run is over: no gestures, no cooldown, no reloading.
var _active := true

var _loaded: Piece = null
var _touch_index := -1
var _touch_start := Vector2.ZERO
var _direction := Vector2.UP
var _power := 0.0
var _cooldown_left := 0.0


func _ready() -> void:
	position.y = Tuning.LAUNCHER_Y
	position.x = Tuning.PLAYFIELD_RECT.get_center().x
	# Deferred so an owner that connects in its own _ready() still hears the first request:
	# child _ready() runs before the parent's.
	needs_piece.emit.call_deferred()


## Puts a piece on the launcher. Only valid while EMPTY; ignored otherwise.
func load_piece(data: TierData) -> void:
	if state != State.EMPTY or data == null:
		return

	var piece := PIECE_SCENE.instantiate() as Piece
	_pieces_root().add_child(piece)
	piece.setup(data)
	piece.set_holstered(true)

	_loaded = piece
	state = State.READY
	_clamp_to_lane()
	_sync_piece()


## The piece currently sitting on the launcher, or null.
func loaded_piece() -> Piece:
	return _loaded


## Drops whatever is held, abandons any gesture in progress, and asks for a fresh piece. Called
## when a run restarts underneath the launcher — without this it goes on holding a piece that the
## restart has already freed.
func reset() -> void:
	_active = true
	if _loaded != null and is_instance_valid(_loaded):
		_loaded.queue_free()
	_loaded = null
	_touch_index = -1
	_cooldown_left = 0.0
	_guide.hide_aim()
	state = State.EMPTY
	needs_piece.emit.call_deferred()


## Abandons a gesture in progress without firing, leaving the launcher where it slid to.
##
## Pausing needs this. The tree stops, so the launcher never hears the finger lift, and it would
## come back from the pause still AIMING against a touch index that no longer exists — a state
## `_begin_gesture()` refuses to leave, because it only starts from READY. Changing the aim mode
## from that menu makes it worse: the half-finished drag would resolve under the other sign.
func cancel_aim() -> void:
	_touch_index = -1
	if state != State.PLACING and state != State.AIMING:
		return
	if state == State.AIMING:
		_guide.hide_aim()
		aim_ended.emit()
	state = State.READY


func _pieces_root() -> Node:
	if not pieces_root_path.is_empty():
		var node := get_node_or_null(pieces_root_path)
		if node != null:
			return node
	return get_parent()


## Switches the launcher off at the end of a run, or back on for a new one.
func set_active(value: bool) -> void:
	_active = value
	if _active:
		return
	_touch_index = -1
	_guide.hide_aim()
	if state == State.PLACING or state == State.AIMING:
		state = State.READY


func _process(delta: float) -> void:
	if not _active or state != State.COOLDOWN:
		return
	_cooldown_left -= delta
	if _cooldown_left <= 0.0:
		state = State.EMPTY
		needs_piece.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_begin_gesture(event.index, _to_world(event.position))
	elif event.index == _touch_index:
		_end_gesture()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _touch_index:
		return
	_update_gesture(_to_world(event.position))


func _begin_gesture(index: int, world: Vector2) -> void:
	if not _active or state != State.READY:
		return
	# The HUD band is not aimable surface.
	if world.y < Tuning.HUD_BAND_HEIGHT:
		return

	_touch_index = index
	_touch_start = world
	state = State.PLACING
	_slide_to(world.x)


func _update_gesture(world: Vector2) -> void:
	if state != State.PLACING and state != State.AIMING:
		return

	# The one difference between the two aim modes (§7): pull-back fires opposite the drag, swipe
	# fires along it. Everything downstream — the deadzone, the power ramp, the cancel rule — is
	# measured from `distance`, which the flip does not touch, so both modes feel identical apart
	# from the direction.
	var drag := world - _touch_start if GameState.invert_aim else _touch_start - world
	var distance := drag.length()

	if distance < Tuning.AIM_DEADZONE:
		# Inside the deadzone: placement, whether we were placing or are cancelling a shot.
		if state == State.AIMING:
			state = State.PLACING
			_guide.hide_aim()
			aim_ended.emit()
		_slide_to(world.x)
		return

	state = State.AIMING
	_direction = drag / distance
	# Subtract the deadzone so power starts at zero exactly where aiming begins, rather than
	# jumping to whatever the crossing distance happened to be.
	_power = clampf((distance - Tuning.AIM_DEADZONE) / Tuning.DRAG_MAX, 0.0, 1.0)
	_guide.show_aim(global_position, _direction, _power, _loaded.radius)
	aim_changed.emit(global_position, _direction, _power)


func _end_gesture() -> void:
	_touch_index = -1
	match state:
		State.AIMING:
			_guide.hide_aim()
			aim_ended.emit()
			_fire()
		State.PLACING:
			# A tap that never left the deadzone only repositions the launcher.
			state = State.READY
		_:
			pass


func _fire() -> void:
	var piece := _loaded
	_loaded = null

	piece.global_position = global_position
	piece.set_holstered(false)

	var speed := lerpf(
		Tuning.SPEED_MIN, Tuning.SPEED_MAX, pow(_power, Tuning.POWER_CURVE_EXPONENT)
	)
	piece.launch(_direction * speed * piece.mass)

	state = State.COOLDOWN
	_cooldown_left = Tuning.SHOT_COOLDOWN
	fired.emit(piece, _direction, _power)


## Moves the launcher along the lane, keeping the loaded piece fully inside the playfield.
func _slide_to(x: float) -> void:
	position.x = x
	_clamp_to_lane()
	_sync_piece()


func _clamp_to_lane() -> void:
	var radius := _loaded.radius if _loaded != null else 0.0
	position.x = clampf(
		position.x,
		Tuning.PLAYFIELD_RECT.position.x + radius,
		Tuning.PLAYFIELD_RECT.end.x - radius
	)


func _sync_piece() -> void:
	if _loaded != null:
		_loaded.global_position = global_position


## The aim guide the launcher owns. F4's harness reads its prediction; nothing else needs it.
func aim_guide() -> AimGuide:
	return _guide


## Screen space to world space. Identity today, but correct if a camera is ever added.
func _to_world(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen
