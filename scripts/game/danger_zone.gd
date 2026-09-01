## The launch lane, watching for anything that settles in it (GAME_DESIGN.md §9).
##
## The rule is spatial and forgiving on purpose: a piece crossing the lane at speed is fine, and
## only a piece that comes to rest there runs down the grace period. The last second of that is
## spent pulsing red, so the run never ends without warning — the player can still shoot the
## offending piece out of the way.
##
## Frozen pieces are ignored, which is what exempts the one sitting on the launcher: it is
## holstered, so it is frozen and on no collision layer. Nothing has to be told about it.
class_name DangerZone
extends Area2D

## A piece has been resting in the lane past the grace period. The run is over.
signal triggered(piece: Piece)
## The worst danger level on the table, 0..1. The table's line pulses along with it.
signal danger_changed(intensity: float)

var _armed := true
## Piece instance id -> seconds it has been resting in the lane.
var _timers: Dictionary = {}
var _worst := 0.0


func _ready() -> void:
	collision_layer = Tuning.LAYER_DANGER_ZONE
	collision_mask = Tuning.LAYER_PIECES
	monitoring = true

	var lane := Rect2(
		Tuning.PLAYFIELD_RECT.position.x,
		Tuning.DANGER_LINE_Y,
		Tuning.PLAYFIELD_RECT.size.x,
		Tuning.LAUNCH_LANE_HEIGHT
	)
	var shape := RectangleShape2D.new()
	shape.size = lane.size

	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = lane.get_center()
	add_child(collider)


## Stops watching, and clears every warning. Called when a run ends or restarts.
func disarm() -> void:
	_armed = false
	_clear_all()


func rearm() -> void:
	_armed = true
	_clear_all()


## Seconds the given piece has been resting in the lane. For the F8 harness.
func resting_time(piece: Piece) -> float:
	return _timers.get(piece.get_instance_id(), 0.0)


func _clear_all() -> void:
	for id: int in _timers.keys():
		var piece := instance_from_id(id) as Piece
		if piece != null and is_instance_valid(piece):
			piece.set_danger(0.0)
	_timers.clear()
	_set_worst(0.0)


func _physics_process(delta: float) -> void:
	if not _armed:
		return

	var seen := {}
	var worst := 0.0
	var expired: Piece = null

	for body in get_overlapping_bodies():
		var piece := body as Piece
		if piece == null or not is_instance_valid(piece) or piece.freeze:
			continue

		var id := piece.get_instance_id()
		seen[id] = true

		# Passing through resets the clock; only settling counts.
		var elapsed := 0.0
		if piece.is_at_rest():
			elapsed = float(_timers.get(id, 0.0)) + delta
		_timers[id] = elapsed

		var intensity := _intensity(elapsed)
		piece.set_danger(intensity)
		worst = maxf(worst, intensity)

		if elapsed >= Tuning.DANGER_GRACE:
			expired = piece

	# Anything that left the lane, or was freed, stops warning.
	for id: int in _timers.keys():
		if seen.has(id):
			continue
		var piece := instance_from_id(id) as Piece
		if piece != null and is_instance_valid(piece):
			piece.set_danger(0.0)
		_timers.erase(id)

	_set_worst(worst)

	if expired != null:
		_armed = false
		triggered.emit(expired)


## Silent for the first stretch of the grace period, then ramps to full over the last second.
func _intensity(elapsed: float) -> float:
	if elapsed <= Tuning.DANGER_WARNING_AT:
		return 0.0
	var span := Tuning.DANGER_GRACE - Tuning.DANGER_WARNING_AT
	return clampf((elapsed - Tuning.DANGER_WARNING_AT) / span, 0.0, 1.0)


func _set_worst(value: float) -> void:
	if is_equal_approx(_worst, value):
		return
	_worst = value
	danger_changed.emit(_worst)
