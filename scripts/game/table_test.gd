## Dev harness for F1: proves the table's walls and friction behave the way GAME_DESIGN.md §6
## describes, and measures the numbers so tuning is done against data rather than vibes.
##
## Not part of the game. Run `res://scenes/game/table_test.tscn` directly. On start it fires a
## test puck straight up the table at several power levels and prints, for each: total path
## length, time to rest, wall bounces, and where it came to rest. Press SPACE to fire another at
## full power, 1-5 for fractional power, R to clear.
##
## Set the F1_SHOT environment variable to a .png path to have it fire a few pucks, screenshot
## the table and exit — handy for eyeballing the layout without a display.
##
## Keep this around through the F12 balance pass — it is the cheapest way to re-check friction
## after a constant changes. It can be deleted once the game is tuned.
extends Node2D

const TEST_RADIUS := 26.0  # Tier 1, so mass is exactly 1.0.
const MEASURE_TIMEOUT := 15.0

@onready var _readout: Label = $UI/Readout

var _pucks: Array[TestPuck] = []


## A minimal stand-in for a Piece. Carries the two-term friction model from §6; F2's piece.gd
## must implement `_integrate_forces` the same way.
class TestPuck extends RigidBody2D:
	var path_length := 0.0
	var elapsed := 0.0
	var bounces := 0
	var at_rest := false
	## Names of the walls this puck has touched, so the sweep can prove all four are solid.
	var walls_hit: Dictionary = {}

	var _last_position := Vector2.ZERO
	## The impulse lands a frame after spawn, so ignore the initial stationary frames and only
	## start looking for rest once the puck has actually got moving.
	var _has_moved := false

	func _init(radius: float) -> void:
		var shape := CircleShape2D.new()
		shape.radius = radius

		var collider := CollisionShape2D.new()
		collider.shape = shape
		add_child(collider)

		mass = pow(radius / Tuning.MASS_BASE_RADIUS, Tuning.MASS_EXPONENT)
		gravity_scale = 0.0
		# REPLACE, not COMBINE: Tuning is authoritative, and must not be added to the project's
		# default damping.
		linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
		linear_damp = Tuning.PIECE_LINEAR_DAMP
		angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
		angular_damp = Tuning.PIECE_ANGULAR_DAMP
		continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
		contact_monitor = true
		max_contacts_reported = Tuning.PIECE_MAX_CONTACTS_REPORTED
		collision_layer = Tuning.LAYER_PIECES
		collision_mask = Tuning.LAYER_PIECES | Tuning.LAYER_WALLS

		var material := PhysicsMaterial.new()
		material.friction = Tuning.PIECE_FRICTION
		material.bounce = Tuning.PIECE_BOUNCE
		physics_material_override = material

	func _ready() -> void:
		_last_position = global_position
		body_entered.connect(_on_body_entered)

	func _on_body_entered(body: Node) -> void:
		bounces += 1
		walls_hit[body.name] = true

	func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
		var velocity := state.linear_velocity
		var speed := velocity.length()

		# Coulomb friction: a constant deceleration that actually reaches zero, unlike the
		# viscous linear_damp term which only ever approaches it.
		if speed > 0.0:
			var drop := Tuning.PIECE_FRICTION_DECEL * state.step
			if drop >= speed:
				velocity = Vector2.ZERO
			else:
				velocity -= velocity / speed * drop

		if velocity.length() > Tuning.PIECE_MAX_SPEED:
			velocity = velocity.normalized() * Tuning.PIECE_MAX_SPEED

		state.linear_velocity = velocity

	func _physics_process(delta: float) -> void:
		if at_rest:
			return
		path_length += global_position.distance_to(_last_position)
		_last_position = global_position
		elapsed += delta

		if linear_velocity.length() >= Tuning.REST_SPEED:
			_has_moved = true
		elif _has_moved:
			at_rest = true

	func draw_color() -> Color:
		return Color("#E74C3C")

	func _draw() -> void:
		var radius: float = (get_child(0) as CollisionShape2D).shape.radius
		draw_circle(Vector2.ZERO, radius, draw_color())
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, draw_color().darkened(0.4), 3.0, true)


func _ready() -> void:
	_run_sweep()


## Fires one puck at each power level and reports the results against the §6 targets.
func _run_sweep() -> void:
	print("\n=== F1 coast measurements ===")
	print("linear_damp=%.3f  friction_decel=%.1f px/s^2  bounce: piece=%.2f wall=%.2f"
		% [Tuning.PIECE_LINEAR_DAMP, Tuning.PIECE_FRICTION_DECEL,
			Tuning.PIECE_BOUNCE, Tuning.WALL_BOUNCE])
	print("launcher y=%.0f  table y=%.0f..%.0f  mid-table y=%.0f"
		% [Tuning.LAUNCHER_Y, Tuning.PLAYFIELD_RECT.position.y, Tuning.PLAYFIELD_RECT.end.y,
			Tuning.PLAYFIELD_RECT.get_center().y])
	print("power  speed   path_px   time_s  bounces  rest_y")

	for power in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var puck := await _measure(power)
		print("%5.2f  %6.0f  %7.0f  %6.2f  %7d  %6.0f"
			% [power, _speed_for(power), puck.path_length, puck.elapsed,
				puck.bounces, puck.global_position.y])
		puck.queue_free()

	print("targets: min-power path ~250px | max-power rest_y ~%.0f | max-power time ~2.5s"
		% Tuning.PLAYFIELD_RECT.get_center().y)

	await _check_all_walls()
	await _capture_screenshot()


func _capture_screenshot() -> void:
	if not OS.has_environment("F1_SHOT"):
		return
	for power in [0.35, 0.6, 0.85]:
		_spawn(power, Vector2(randf_range(-0.5, 0.5), -1.0))
		for i in 20:
			await get_tree().physics_frame
	for i in 180:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("F1_SHOT"))
	get_tree().quit()


## Fires one puck from the table centre at each wall in turn. Each must register a contact,
## rebound (velocity reverses along the axis of travel), and never leave the playfield.
func _check_all_walls() -> void:
	print("full-power shots at each wall (collider depth %.0fpx)" % Tuning.WALL_COLLIDER_DEPTH)
	print("wall  contact       rebounded  max_sink_px  rests_inside")

	var directions := {
		"WallTop": Vector2.UP,
		"WallBottom": Vector2.DOWN,
		"WallLeft": Vector2.LEFT,
		"WallRight": Vector2.RIGHT,
	}

	for expected: String in directions:
		var direction: Vector2 = directions[expected]
		var puck := TestPuck.new(TEST_RADIUS)
		puck.position = Tuning.PLAYFIELD_RECT.get_center()
		add_child(puck)
		puck.apply_central_impulse(direction * _speed_for(1.0) * puck.mass)

		var rebounded := false
		# Deepest the puck's edge ever got past the inner face of a wall. A few px of contact
		# penetration is normal; anything large means a puck can tunnel out of the table.
		var deepest := 0.0
		var bounds := Tuning.PLAYFIELD_RECT.grow(-TEST_RADIUS)
		var waited := 0.0
		while waited < MEASURE_TIMEOUT and not puck.at_rest:
			await get_tree().physics_frame
			waited += 1.0 / Engine.physics_ticks_per_second
			if puck.linear_velocity.dot(direction) < -Tuning.REST_SPEED:
				rebounded = true

			var p := puck.global_position
			deepest = maxf(deepest, bounds.position.x - p.x)
			deepest = maxf(deepest, p.x - bounds.end.x)
			deepest = maxf(deepest, bounds.position.y - p.y)
			deepest = maxf(deepest, p.y - bounds.end.y)

		print("%-5s %-13s %-10s %-11.2f %s" % [
			direction_name(direction),
			"yes" if puck.walls_hit.has(expected) else "MISSING",
			"yes" if rebounded else "NO",
			deepest,
			"yes" if bounds.has_point(puck.global_position) else "ESCAPED",
		])
		puck.queue_free()

	print("")


func direction_name(direction: Vector2) -> String:
	if direction == Vector2.UP:
		return "top"
	if direction == Vector2.DOWN:
		return "bot"
	return "left" if direction == Vector2.LEFT else "right"


func _speed_for(power: float) -> float:
	return lerpf(Tuning.SPEED_MIN, Tuning.SPEED_MAX, pow(power, Tuning.POWER_CURVE_EXPONENT))


## Fires a puck straight up the table and waits for it to come to rest.
func _measure(power: float) -> TestPuck:
	var puck := _spawn(power, Vector2.UP)
	var waited := 0.0
	while not puck.at_rest and waited < MEASURE_TIMEOUT:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
	return puck


func _spawn(power: float, direction: Vector2) -> TestPuck:
	var puck := TestPuck.new(TEST_RADIUS)
	puck.position = Vector2(Tuning.PLAYFIELD_RECT.get_center().x, Tuning.LAUNCHER_Y)
	add_child(puck)
	puck.apply_central_impulse(direction.normalized() * _speed_for(power) * puck.mass)
	_pucks.append(puck)
	return puck


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_spawn(1.0, Vector2.UP)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			var step := (event as InputEventKey).keycode - KEY_1
			_spawn(step / 4.0, Vector2.UP)
		KEY_R:
			for puck in _pucks:
				if is_instance_valid(puck):
					puck.queue_free()
			_pucks.clear()


func _process(_delta: float) -> void:
	var live := 0
	var moving := 0
	for puck in _pucks:
		if not is_instance_valid(puck):
			continue
		live += 1
		if not puck.at_rest:
			moving += 1
	_readout.text = "F1 table harness\nSPACE fire | 1-5 power | R clear\npucks: %d (%d moving)" % [live, moving]
