## The aim guide: a dotted line showing where the shot goes, one predicted wall bounce, a ring on
## whatever it would hit, and a power arc around the held piece. Drawn only while AIMING.
##
## The line's length is what communicates power (GAME_DESIGN.md §7) — it is deliberately not the
## full trajectory. A full-power shot travels far past the end of the guide.
##
## Runs `top_level`, so everything here is in global coordinates even though the node rides along
## with the launcher.
class_name AimGuide
extends Node2D

var _active := false
var _origin := Vector2.ZERO
var _direction := Vector2.UP
var _power := 0.0
var _radius := 0.0

var _path := PackedVector2Array()
## Index into `_path` of the vertex where the bounce happens, or -1 when there is no bounce.
var _bounce_index := -1
var _target: Piece = null

var _shape := CircleShape2D.new()
var _dirty := false


func _ready() -> void:
	top_level = true
	z_index = 10
	visible = false


## Show the guide for the current aim. Cheap: the physics queries are deferred to the next
## physics frame, which also throttles them to 60Hz.
func show_aim(origin: Vector2, direction: Vector2, power: float, radius: float) -> void:
	_origin = origin
	_direction = direction
	_power = power
	_radius = radius
	_active = true
	_dirty = true
	visible = true


func hide_aim() -> void:
	_active = false
	_dirty = false
	visible = false
	_path.clear()
	_bounce_index = -1
	_target = null


## The predicted polyline in global coordinates: origin, then each hit, then the end.
func predicted_path() -> PackedVector2Array:
	return _path


## The piece the shot is currently pointed at, or null.
func predicted_target() -> Piece:
	return _target


# Space queries belong in the physics step, so the recompute waits for one rather than running
# straight out of the input event that moved the aim.
func _physics_process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false
	_recompute()
	queue_redraw()


func _recompute() -> void:
	_path = PackedVector2Array([_origin])
	_bounce_index = -1
	_target = null

	_shape.radius = _radius

	var remaining := lerpf(Tuning.AIM_LINE_MIN_LENGTH, Tuning.AIM_LINE_MAX_LENGTH, _power)
	var from := _origin
	var direction := _direction
	var bounces := 0

	while remaining > 0.0:
		var hit := _cast(from, direction, remaining)

		if hit.is_empty():
			_path.append(from + direction * remaining)
			return

		var point: Vector2 = hit["point"]
		_path.append(point)
		remaining -= from.distance_to(point)

		var piece := hit["piece"] as Piece
		if piece != null:
			_target = piece
			return

		if bounces >= Tuning.AIM_MAX_BOUNCES:
			return

		_bounce_index = _path.size() - 1
		direction = _reflect(direction, hit["normal"])
		bounces += 1
		# Step off the contact point so the next cast does not start already overlapping.
		from = point + direction * 0.5


## How the wall actually sends a piece back, not a mirror. Restitution is applied to the normal
## component of the velocity while the tangential component carries on, so the rebound is
## shallower than a mirrored one. Note this uses WALL_RESTITUTION, the combined piece-and-wall
## value the engine really applies — using WALL_BOUNCE alone predicts a far flatter bounce than
## happens, which would make the guide lie on exactly the shot it exists to help with.
func _reflect(direction: Vector2, normal: Vector2) -> Vector2:
	var along_normal := direction.dot(normal) * normal
	var along_wall := direction - along_normal
	return (along_wall - along_normal * Tuning.WALL_RESTITUTION).normalized()


## Sweeps the piece's own circle rather than a ray: a ray from the centre would clip corners and
## put the bounce at the wall face instead of a radius short of it.
func _cast(from: Vector2, direction: Vector2, length: float) -> Dictionary:
	var space := get_world_2d().direct_space_state

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _shape
	params.transform = Transform2D(0.0, from)
	params.motion = direction * length
	params.collision_mask = Tuning.LAYER_PIECES | Tuning.LAYER_WALLS

	var fractions := space.cast_motion(params)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return {}

	var safe: float = fractions[0]
	var unsafe: float = fractions[1]

	# Probe at the unsafe fraction, where the shapes actually touch, for the normal and collider.
	params.transform = Transform2D(0.0, from + direction * length * unsafe)
	params.motion = Vector2.ZERO
	var rest := space.get_rest_info(params)
	if rest.is_empty():
		return {}

	var collider: Object = instance_from_id(rest["collider_id"])
	return {
		"point": from + direction * length * safe,
		"normal": rest["normal"] as Vector2,
		"piece": collider as Piece,
	}


func _draw() -> void:
	if not _active or _path.size() < 2:
		return

	_draw_dots()
	if _target != null:
		draw_arc(
			_target.global_position,
			_target.radius + Tuning.AIM_TARGET_RING_GAP,
			0.0,
			TAU,
			48,
			Tuning.COLOR_AIM_TARGET,
			Tuning.AIM_TARGET_RING_WIDTH,
			true
		)
	_draw_power_arc()


## Dots are walked along the whole polyline rather than per segment, so the spacing carries
## evenly through the bounce instead of restarting at the corner.
func _draw_dots() -> void:
	var distance := Tuning.AIM_DOT_SPACING
	for i in range(1, _path.size()):
		var from := _path[i - 1]
		var to := _path[i]
		var segment := from.distance_to(to)
		if segment <= 0.0:
			continue

		var direction := (to - from) / segment
		var color := (
			Tuning.COLOR_AIM_DOT_BOUNCED
			if _bounce_index >= 0 and i > _bounce_index
			else Tuning.COLOR_AIM_DOT
		)

		while distance < segment:
			draw_circle(from + direction * distance, Tuning.AIM_DOT_RADIUS, color)
			distance += Tuning.AIM_DOT_SPACING
		distance -= segment


func _draw_power_arc() -> void:
	if _power <= 0.0:
		return
	draw_arc(
		_origin,
		_radius + Tuning.POWER_ARC_GAP,
		-PI * 0.5,
		-PI * 0.5 + TAU * _power,
		48,
		Tuning.COLOR_POWER_LOW.lerp(Tuning.COLOR_POWER_HIGH, _power),
		Tuning.POWER_ARC_WIDTH,
		true
	)
