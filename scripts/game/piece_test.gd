## Dev harness for F2: an interactive sandbox for the twelve tiers, plus the checks that prove
## the tier set is sound and that pieces carry the right size, mass and physics.
##
## Not part of the game. Run `res://scenes/game/piece_test.tscn` directly.
##
##   click       spawn the selected tier where you clicked
##   1-9 0 - =   select tier 1-9, 10, 11, 12
##   A           lay out all twelve tiers, to compare sizes at a glance
##   SPACE       fire the selected tier up the table from the launcher at full power
##   R           clear the table
##
## Set the F2_SHOT environment variable to a .png path to lay out all twelve, screenshot and
## exit. This supersedes the interactive half of table_test.tscn, which is now purely the
## automated friction-measurement scene.
extends Node2D

const PIECE_SCENE := preload("res://scenes/game/piece.tscn")
const MEASURE_TIMEOUT := 15.0

@onready var _readout: Label = $UI/Readout

var _tiers: TierSet = null
var _selected := 1
var _pieces: Array[Piece] = []


func _ready() -> void:
	_tiers = TierSet.load_default()
	_report_tier_table()
	await _measure_nudge()
	await _capture_screenshot()


## Prints the authored tier set and checks it against the rules in §5: twelve entries, strictly
## growing radii, mass derived from radius, and a readable label colour.
func _report_tier_table() -> void:
	print("\n=== F2 tier table ===")

	var problems := _tiers.validate()
	if problems.is_empty():
		print("tier set valid: %d tiers, radii strictly increasing" % _tiers.tiers.size())
	else:
		for problem in problems:
			printerr("INVALID: %s" % problem)

	print("tier  radius  ratio   mass   colour     lum   label")
	var previous := 0.0
	for tier in range(1, Tuning.MAX_TIER + 1):
		var data := _tiers.get_tier(tier)
		var luminance := data.color.get_luminance()
		print("%4d  %6.0f  %5s  %5.2f  #%s  %.2f  %s" % [
			data.tier,
			data.radius,
			"-" if previous == 0.0 else "%.3f" % (data.radius / previous),
			data.mass,
			data.color.to_html(false).to_upper(),
			luminance,
			"dark" if luminance > Tuning.PIECE_LABEL_DARK_ABOVE_LUMINANCE else "light",
		])
		previous = data.radius


## Closes the check §6 left open at F1: how far does a full-power tier-1 shove a resting tier-8?
## Measured at two ranges, because the answer depends almost entirely on impact speed.
##
## Both numbers come from the tier-8's own motion, polled frame by frame — deriving them from the
## shot's velocity around the collision proved unreliable, since the contact resolves inside a
## physics step and the reading is a frame late either way.
func _measure_nudge() -> void:
	print("\n=== F2 tier-1 into a resting tier-8 ===")
	print("range         gap_px  tier8_peak_px/s  tier8_moved_px")

	var target_y := Tuning.PLAYFIELD_RECT.get_center().y
	var ranges := {
		"across table": Tuning.LAUNCHER_Y,
		"point blank": target_y + 65.0 + 26.0 + 20.0,
	}

	for label: String in ranges:
		var start_y: float = ranges[label]
		var centre_x := Tuning.PLAYFIELD_RECT.get_center().x

		var target := _spawn(8, Vector2(centre_x, target_y))
		var shot := _spawn(1, Vector2(centre_x, start_y))
		var origin := target.global_position

		# Let the pair settle before firing, so the measurement is of the impact alone.
		for i in 10:
			await get_tree().physics_frame

		shot.launch(Vector2.UP * Tuning.SPEED_MAX * shot.mass)

		var peak := 0.0
		var struck := false
		var waited := 0.0
		while waited < MEASURE_TIMEOUT:
			await get_tree().physics_frame
			waited += 1.0 / Engine.physics_ticks_per_second

			peak = maxf(peak, target.linear_velocity.length())
			struck = struck or not target.is_at_rest()
			if struck and target.is_at_rest() and shot.is_at_rest():
				break

		print("%-12s  %6.0f  %15.0f  %14.0f" % [
			label,
			start_y - target_y - 65.0 - 26.0,
			peak,
			origin.distance_to(target.global_position),
		])
		_clear()

	print("§6 target was 30-60px; see the F2 notes in §12.\n")


func _spawn(tier: int, position: Vector2) -> Piece:
	var data := _tiers.get_tier(tier)
	if data == null:
		return null
	var piece := PIECE_SCENE.instantiate() as Piece
	piece.position = position
	add_child(piece)
	piece.setup(data)
	_pieces.append(piece)
	return piece


func _clear() -> void:
	for piece in _pieces:
		if is_instance_valid(piece):
			piece.queue_free()
	_pieces.clear()


## Every tier at once, in two rows, so their relative sizes can be judged by eye.
func _spawn_all() -> void:
	_clear()
	var rows: Array[Array] = [[1, 2, 3, 4, 5, 6, 7, 8], [9, 10, 11, 12]]
	var y := 560.0
	for row: Array in rows:
		var total := 0.0
		for tier: int in row:
			total += _tiers.get_tier(tier).radius * 2.0
		var gap: float = (Tuning.PLAYFIELD_RECT.size.x - total) / (row.size() + 1)

		var x: float = Tuning.PLAYFIELD_RECT.position.x + gap
		for tier: int in row:
			var radius := _tiers.get_tier(tier).radius
			_spawn(tier, Vector2(x + radius, y))
			x += radius * 2.0 + gap
		y += 340.0


func _capture_screenshot() -> void:
	if not OS.has_environment("F2_SHOT"):
		return
	_spawn_all()
	for i in 90:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("F2_SHOT"))
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT:
			_spawn(_selected, get_global_mouse_position())
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match (event as InputEventKey).keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_selected = (event as InputEventKey).keycode - KEY_0
		KEY_0:
			_selected = 10
		KEY_MINUS:
			_selected = 11
		KEY_EQUAL:
			_selected = 12
		KEY_A:
			_spawn_all()
		KEY_R:
			_clear()
		KEY_SPACE:
			var launcher := Vector2(Tuning.PLAYFIELD_RECT.get_center().x, Tuning.LAUNCHER_Y)
			var piece := _spawn(_selected, launcher)
			if piece != null:
				piece.launch(Vector2.UP * Tuning.SPEED_MAX * piece.mass)


func _process(_delta: float) -> void:
	var data := _tiers.get_tier(_selected)
	var live := 0
	for piece in _pieces:
		if is_instance_valid(piece):
			live += 1
	_readout.text = "F2 piece harness — click spawn | 1-9 0 - = tier | A all | SPACE fire | R clear\ntier %d: r=%.0f mass=%.2f | pieces: %d" % [
		data.tier, data.radius, data.mass, live
	]
