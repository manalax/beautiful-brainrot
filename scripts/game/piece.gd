## One object on the table. A circle that slides, bounces, and merges with its own kind.
##
## Pieces are built from a TierData (GAME_DESIGN.md §5) via `setup()`, which is what fixes their
## radius, mass, colour and physics. A Piece that has not been set up is inert and draws nothing.
##
## Placeholder rendering lives in `_draw()`: filled circle, darker outline, and the face the
## active piece set puts on this tier (§5.1) — a tier number in the classic set, an emoji in
## another. The set is read at draw time, so switching sets restyles pieces already on the table.
class_name Piece
extends RigidBody2D

## Emitted the first time this piece settles after moving. F8's danger check and F5's merge
## bookkeeping both care about pieces coming to rest.
signal came_to_rest

## Shared across every piece; there is no per-piece variation, so allocating one per body would
## be waste at 40 bodies on the table.
static var _material: PhysicsMaterial = null

var data: TierData = null
var tier: int = 0
var radius: float = 0.0

## Claimed by the MergeResolver the instant a pair is queued, which is what stops the same pair
## being resolved twice (both bodies report the contact) and stops a third piece pairing with
## either of them in the same frame. See GAME_DESIGN.md §8.
var merging := false
## Physics frames left before this piece may merge again. A freshly merged piece gets one, so a
## cascade cannot resolve inside a single frame — chains happen on subsequent ticks instead.
var merge_cooldown := 0

## 0 when safe, ramping to 1 as the grace period in the launch lane runs out (§9). Drives the
## red pulse that warns the player before the run ends.
var danger := 0.0

## A wall was struck hard enough to be worth marking. Carries the pre-impact speed, because by
## the time anything downstream sees this the bounce has already been solved.
signal hit_wall(position: Vector2, normal: Vector2, speed: float)

var _moving := false
## Merge flash and spawn pop, both purely visual — see GAME_DESIGN.md §12 F11.
var _flash := 0.0
var _pop_age := INF
var _touching_wall := false
var _previous_speed := 0.0


## Applies a tier to this piece. Must be called before the piece is of any use.
func setup(tier_data: TierData) -> void:
	data = tier_data
	tier = tier_data.tier
	radius = tier_data.radius

	var shape := CircleShape2D.new()
	shape.radius = radius
	($CollisionShape2D as CollisionShape2D).shape = shape

	mass = tier_data.mass
	gravity_scale = 0.0
	# REPLACE, not COMBINE: Tuning is authoritative and must not stack with the project default.
	linear_damp_mode = DAMP_MODE_REPLACE
	linear_damp = Tuning.PIECE_LINEAR_DAMP
	angular_damp_mode = DAMP_MODE_REPLACE
	angular_damp = Tuning.PIECE_ANGULAR_DAMP
	can_sleep = true
	contact_monitor = true
	max_contacts_reported = Tuning.PIECE_MAX_CONTACTS_REPORTED
	collision_layer = Tuning.LAYER_PIECES
	collision_mask = Tuning.LAYER_PIECES | Tuning.LAYER_WALLS
	physics_material_override = _shared_material()

	_set_moving(false)
	set_process(false)
	queue_redraw()


## A holstered piece is inert: frozen where it is put, and colliding with nothing. That is what
## a piece sitting on the launcher is, so that sliding the launcher along the lane cannot bulldoze
## whatever is already resting there.
func set_holstered(holstered: bool) -> void:
	# STATIC, not KINEMATIC: a kinematic-frozen body derives a velocity from being moved, so
	# sliding the launcher would leak the slide into the shot as sideways drift.
	freeze_mode = FREEZE_MODE_STATIC
	freeze = holstered
	if holstered:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = Tuning.LAYER_PIECES
		collision_mask = Tuning.LAYER_PIECES | Tuning.LAYER_WALLS


## Gives a freshly merged piece the motion it inherited. Not `launch()`, which zeroes velocity
## first because a shot must start from rest.
func inherit_velocity(velocity: Vector2) -> void:
	linear_velocity = velocity
	_set_moving(velocity.length() >= Tuning.REST_SPEED)


## True when this piece is available to merge.
func can_merge() -> bool:
	return not merging and merge_cooldown <= 0 and not freeze


## Takes the piece out of play immediately, then frees it. Clearing the collision layers here
## rather than relying on queue_free matters: queue_free does not take effect until the end of
## the frame, and a dying body would otherwise shove the piece that just replaced it.
func despawn() -> void:
	merging = true
	collision_layer = 0
	collision_mask = 0
	queue_free()


## Fires the piece. `impulse` is already mass-scaled by the caller.
func launch(impulse: Vector2) -> void:
	# A launch starts from rest: whatever the piece was doing before must not bias the shot.
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_set_moving(true)
	apply_central_impulse(impulse)


## True once the piece has slowed below the rest threshold (§9).
func is_at_rest() -> bool:
	return not _moving


static func _shared_material() -> PhysicsMaterial:
	if _material == null:
		_material = PhysicsMaterial.new()
		_material.friction = Tuning.PIECE_FRICTION
		_material.bounce = Tuning.PIECE_BOUNCE
	return _material


func _physics_process(_delta: float) -> void:
	if merge_cooldown > 0:
		merge_cooldown -= 1

	var moving := linear_velocity.length() >= Tuning.REST_SPEED
	if moving == _moving:
		return
	_set_moving(moving)
	if not moving:
		came_to_rest.emit()


## Continuous collision detection is only worth its cost while the piece is actually travelling
## fast enough to tunnel; a resting piece does not need it. See §6.
func _set_moving(moving: bool) -> void:
	_moving = moving
	continuous_cd = CCD_MODE_CAST_SHAPE if moving else CCD_MODE_DISABLED


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var velocity := state.linear_velocity
	var speed := velocity.length()

	# Coulomb friction: a constant deceleration that actually reaches zero, unlike the viscous
	# linear_damp term which only ever approaches it. See GAME_DESIGN.md §6.
	if speed > 0.0:
		var drop := Tuning.PIECE_FRICTION_DECEL * state.step
		if drop >= speed:
			velocity = Vector2.ZERO
		else:
			velocity -= velocity / speed * drop

	if velocity.length() > Tuning.PIECE_MAX_SPEED:
		velocity = velocity.normalized() * Tuning.PIECE_MAX_SPEED

	state.linear_velocity = velocity
	_watch_for_wall_impact(state)


## Reports the first frame of each wall contact, with the speed the piece was carrying going in.
## The speed has to come from the previous frame: by the time a contact is visible here, the
## bounce that killed most of that speed has already happened.
func _watch_for_wall_impact(state: PhysicsDirectBodyState2D) -> void:
	var touching := false
	var point := Vector2.ZERO
	var normal := Vector2.ZERO

	for i in state.get_contact_count():
		if state.get_contact_collider_object(i) is StaticBody2D:
			touching = true
			point = state.get_contact_local_position(i)
			normal = state.get_contact_local_normal(i)
			break

	if touching and not _touching_wall and _previous_speed >= Tuning.SPARK_MIN_SPEED:
		hit_wall.emit(point, normal, _previous_speed)

	_touching_wall = touching
	_previous_speed = state.linear_velocity.length()


## Flares the piece white and grows it into place. Called on a piece produced by a merge; it is
## drawing only, and touches neither the collision shape nor the body.
func play_merge_effect() -> void:
	_flash = 1.0
	_pop_age = 0.0
	_refresh_processing()


## Sets how close this piece is to ending the run. Processing is switched on only while it is
## actually in danger, so the pulse costs nothing for the pieces that are fine.
func set_danger(value: float) -> void:
	if is_equal_approx(danger, value):
		return
	danger = value
	_refresh_processing()
	queue_redraw()


## Stops the piece dead where it is, for the end of a run.
func freeze_in_place() -> void:
	freeze_mode = FREEZE_MODE_STATIC
	freeze = true
	set_danger(0.0)


## Only runs while something is actually animating, so the great majority of pieces cost nothing.
func _refresh_processing() -> void:
	set_process(danger > 0.0 or _flash > 0.0 or _pop_age < Tuning.PIECE_POP_TIME)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / Tuning.PIECE_FLASH_TIME)
	if _pop_age < Tuning.PIECE_POP_TIME:
		_pop_age += delta
	_refresh_processing()
	queue_redraw()


func _draw() -> void:
	if data == null:
		return

	# Starts from the active set's colour for this tier, not the tier's own: the danger pulse and
	# the merge flash are lerps *from* whatever the piece is actually drawn in.
	var fill := PieceRender.base_fill(data, GameState.active_set)

	# A steady tint would read as a colour change; the oscillation is what says "act now".
	if danger > 0.0:
		var phase := Time.get_ticks_msec() / 1000.0 * TAU * Tuning.DANGER_PULSE_HZ
		fill = fill.lerp(
			Tuning.COLOR_DANGER_WARNING, danger * (0.5 + 0.5 * sin(phase))
		)

	if _flash > 0.0:
		fill = fill.lerp(Tuning.COLOR_MERGE_FLASH, _flash)

	PieceRender.draw_piece(
		self, Vector2.ZERO, radius * _pop_scale(), data, GameState.active_set, fill
	)


## Grows from PIECE_POP_FROM to full size, swelling a little past it on the way. Applied to the
## drawn radius alone — the collision circle never changes, so this is invisible to the physics.
func _pop_scale() -> float:
	if _pop_age >= Tuning.PIECE_POP_TIME:
		return 1.0
	var t := clampf(_pop_age / Tuning.PIECE_POP_TIME, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var overshoot := sin(t * PI) * (Tuning.PIECE_POP_OVERSHOOT - 1.0)
	return lerpf(Tuning.PIECE_POP_FROM, 1.0, eased) + overshoot
