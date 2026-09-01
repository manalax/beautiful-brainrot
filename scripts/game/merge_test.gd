## Dev harness for F5: exercises the merge rules and the §8 guarantees, then leaves the table
## playable so chains can be watched happening.
##
## Not part of the game. Run `res://scenes/game/merge_test.tscn` directly. After the automated
## pass: drag to place, past the deadzone to aim, release to fire — the table is seeded with
## pairs so shots chain. `1-9 0 - =` picks a tier and clicking drops one, `R` clears.
##
## Set F5_SHOT to a .png path to screenshot a seeded table and exit.
extends Node2D

const MEASURE_TIMEOUT := 8.0

@onready var _launcher: Launcher = $Launcher
@onready var _resolver: MergeResolver = $MergeResolver
@onready var _pieces: Node2D = $Pieces
@onready var _readout: Label = $UI/Readout

var _tiers: TierSet = null
var _rng := RandomNumberGenerator.new()
var _selected := 1
var _failures := 0

var _merges: Array[Dictionary] = []
var _annihilations := 0


func _ready() -> void:
	_tiers = TierSet.load_default()
	_rng.seed = 20260831
	_launcher.needs_piece.connect(_on_needs_piece)
	_launcher.fired.connect(_on_fired)
	_resolver.merged.connect(_on_merged)
	_resolver.annihilated.connect(_on_annihilated)
	await _run_merge_tests()
	await _seed_playable_table()
	await _capture_screenshot()


func _on_needs_piece() -> void:
	_launcher.load_piece(_tiers.get_tier(_rng.randi_range(1, 5)))


func _on_fired(_piece: Piece, _direction: Vector2, _power: float) -> void:
	_resolver.reset_chain()


func _on_merged(tier: int, position: Vector2, chain_depth: int) -> void:
	_merges.append({"tier": tier, "position": position, "chain": chain_depth})


func _on_annihilated(_position: Vector2, _chain_depth: int) -> void:
	_annihilations += 1


# --- automated pass ------------------------------------------------------------------------------

func _run_merge_tests() -> void:
	print("\n=== F5 merging ===")

	await _case_simple_pair()
	await _case_three_in_contact()
	await _case_different_tiers()
	await _case_tier_twelve()
	await _case_chain_from_one_shot()
	await _case_no_leaks()

	print("%d checks failed\n" % _failures if _failures > 0 else "all checks passed\n")


## Two of a tier touching become one of the next tier, at their midpoint, still moving.
func _case_simple_pair() -> void:
	await _reset()
	var left := _spawn(3, Vector2(500.0, 900.0))
	var right := _spawn(3, Vector2(700.0, 900.0))
	right.inherit_velocity(Vector2(-600.0, 0.0))

	await _settle()
	_check("a pair merges once", _merges.size() == 1, "%d merges" % _merges.size())
	_check("one piece is left", _live_pieces().size() == 1, "%d left" % _live_pieces().size())
	if _merges.size() == 1 and _live_pieces().size() == 1:
		var result: Piece = _live_pieces()[0]
		_check("it is the next tier up", result.tier == 4, "tier %d" % result.tier)
		_check("it merged near the midpoint",
			absf(_merges[0]["position"].x - 600.0) < 120.0,
			"x=%.0f" % _merges[0]["position"].x)
	_check("both originals are gone",
		not is_instance_valid(left) and not is_instance_valid(right), "an original survived")


## Three touching pieces of one tier: exactly one merge, and the odd one out is untouched.
func _case_three_in_contact() -> void:
	await _reset()
	# Overlapping on purpose: all three are in contact the moment physics runs.
	_spawn(2, Vector2(540.0, 900.0))
	_spawn(2, Vector2(590.0, 900.0))
	_spawn(2, Vector2(565.0, 945.0))

	await _settle()
	_check("three in contact merge exactly once", _merges.size() == 1,
		"%d merges" % _merges.size())
	var live := _live_pieces()
	_check("two pieces remain", live.size() == 2, "%d remain" % live.size())
	if live.size() == 2:
		var tiers := [live[0].tier, live[1].tier]
		tiers.sort()
		_check("one merged, one did not", tiers == [2, 3], "tiers %s" % str(tiers))


func _case_different_tiers() -> void:
	await _reset()
	var moving := _spawn(4, Vector2(700.0, 900.0))
	_spawn(6, Vector2(500.0, 900.0))
	moving.inherit_velocity(Vector2(-800.0, 0.0))

	await _settle()
	_check("different tiers never merge", _merges.is_empty(), "%d merges" % _merges.size())
	_check("both pieces survive", _live_pieces().size() == 2,
		"%d pieces" % _live_pieces().size())


## The top of the chain: both vanish, nothing is produced, the table loses mass.
func _case_tier_twelve() -> void:
	await _reset()
	var left := _spawn(12, Vector2(420.0, 900.0))
	var right := _spawn(12, Vector2(680.0, 900.0))
	right.inherit_velocity(Vector2(-700.0, 0.0))

	await _settle()
	_check("two tier-12s annihilate", _annihilations == 1, "%d annihilations" % _annihilations)
	_check("no tier 13 is produced", _merges.is_empty(), "%d merges" % _merges.size())
	_check("the table is empty", _live_pieces().is_empty(),
		"%d pieces" % _live_pieces().size())
	_check("neither survives",
		not is_instance_valid(left) and not is_instance_valid(right), "one survived")


## The point of carrying momentum through a merge: one shot setting off several.
func _case_chain_from_one_shot() -> void:
	await _reset()
	_spawn(1, Vector2(540.0, 1300.0))
	_spawn(2, Vector2(540.0, 1050.0))
	await get_tree().physics_frame

	var shot := _spawn(1, Vector2(540.0, Tuning.LAUNCHER_Y))
	_resolver.reset_chain()
	shot.launch(Vector2.UP * Tuning.SPEED_MAX * shot.mass)

	await _settle()
	_check("one shot chains two merges", _merges.size() == 2, "%d merges" % _merges.size())
	if _merges.size() == 2:
		_check("the chain produced a tier 3", _merges[1]["tier"] == 3,
			"tier %d" % _merges[1]["tier"])
		_check("chain depth counts up",
			_merges[0]["chain"] == 0 and _merges[1]["chain"] == 1,
			"depths %d, %d" % [_merges[0]["chain"], _merges[1]["chain"]])
	_check("one piece is left standing", _live_pieces().size() == 1,
		"%d pieces" % _live_pieces().size())


## Merge a long cascade and confirm the container is left holding exactly what is alive — no
## freed bodies lingering, no orphans.
func _case_no_leaks() -> void:
	await _reset()
	# Sixteen tier-1s packed slightly tighter than their own diameter, so every one of them is in
	# contact from the first frame and the cascade has to sort itself out.
	for i in 16:
		var x := 400.0 + float(i % 4) * 48.0
		var y := 800.0 + float(i / 4) * 48.0
		_spawn(1, Vector2(x, y))

	await _settle()
	var live := _live_pieces()

	var lingering := 0
	for child in _pieces.get_children():
		if child.is_queued_for_deletion():
			lingering += 1
	_check("no freed bodies linger", lingering == 0, "%d still queued for deletion" % lingering)

	var expected_children := live.size() + (1 if _launcher.loaded_piece() != null else 0)
	_check("the container holds only what is alive",
		_pieces.get_child_count() == expected_children,
		"%d children, expected %d" % [_pieces.get_child_count(), expected_children])
	_check("the cascade reduced the table", live.size() < 16, "%d pieces" % live.size())
	_check("every merge reported a real tier",
		_merges.all(func(m: Dictionary) -> bool: return m["tier"] >= 2 and m["tier"] <= 12),
		"a merge reported an impossible tier")
	print("  cascade: 16 tier-1s -> %d pieces after %d merges" % [live.size(), _merges.size()])


# --- helpers -------------------------------------------------------------------------------------

func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s (%s)" % [label, detail])


func _live_pieces() -> Array[Piece]:
	var live: Array[Piece] = []
	for child in _pieces.get_children():
		var piece := child as Piece
		if piece != null and is_instance_valid(piece) and not piece.is_queued_for_deletion():
			if piece != _launcher.loaded_piece():
				live.append(piece)
	return live


func _spawn(tier: int, position: Vector2) -> Piece:
	var piece := MergeResolver.PIECE_SCENE.instantiate() as Piece
	piece.position = position
	_pieces.add_child(piece)
	piece.setup(_tiers.get_tier(tier))
	return piece


## Clears the table and the recorded signals so each case starts from nothing.
func _reset() -> void:
	for child in _pieces.get_children():
		if child != _launcher.loaded_piece():
			child.queue_free()
	_merges.clear()
	_annihilations = 0
	_resolver.reset_chain()
	await get_tree().process_frame
	await get_tree().physics_frame


## Runs physics until nothing is moving and nothing is queued to merge.
func _settle() -> void:
	var waited := 0.0
	var still := 0
	while waited < MEASURE_TIMEOUT:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		var moving := false
		for piece in _live_pieces():
			if not piece.is_at_rest():
				moving = true
				break
		still = still + 1 if not moving else 0
		if still > 12:
			return
	await get_tree().process_frame


func _seed_playable_table() -> void:
	await _reset()
	for pair in [[1, 380.0, 700.0], [1, 700.0, 780.0], [2, 460.0, 1050.0], [2, 640.0, 1180.0],
			[3, 320.0, 1350.0], [4, 760.0, 1400.0]]:
		_spawn(int(pair[0]), Vector2(pair[1], pair[2]))
	await get_tree().physics_frame


func _capture_screenshot() -> void:
	var path := OS.get_environment("F5_SHOT")
	if path.is_empty():
		return
	for i in 30:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("capture wrote %s (error %d)" % [path, error])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
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
		KEY_R:
			for child in _pieces.get_children():
				if child != _launcher.loaded_piece():
					child.queue_free()


func _process(_delta: float) -> void:
	_readout.text = "F5 merging — fire to chain | %d-key tier, click to drop | R clear\npieces: %d  merges: %d  chain depth: %d  selected tier: %d" % [
		_selected, _live_pieces().size(), _merges.size(), _resolver.chain_depth, _selected
	]
