## The numbers that float off a merge (GAME_DESIGN.md §10).
##
## Every popup is drawn by this one node rather than being its own scene, so a busy chain costs a
## few dictionaries instead of a burst of node instantiation in the hot path (§15).
class_name ScorePopups
extends Node2D

const LIFETIME := 0.9
const RISE := 90.0
## Popups start clear of the piece that produced them — the merged piece is drawn at the same
## point and can be up to 110px across.
const CLEARANCE := 78.0
const POINTS_SIZE := 44
const MULTIPLIER_SIZE := 30

var _active: Array[Dictionary] = []


## Floats `points` at a merge. A chain of two or more also shows the multiplier that earned it.
func show_points(world_position: Vector2, points: int, chain_depth: int) -> void:
	_active.append({
		"position": world_position,
		"points": "+%d" % points,
		"multiplier": (
			"x%.1f" % GameState.chain_multiplier(chain_depth) if chain_depth > 0 else ""
		),
		"age": 0.0,
	})


func clear() -> void:
	_active.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _active.is_empty():
		return

	var survivors: Array[Dictionary] = []
	for popup in _active:
		popup["age"] += delta
		if popup["age"] < LIFETIME:
			survivors.append(popup)
	_active = survivors
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return

	for popup in _active:
		var progress: float = popup["age"] / LIFETIME
		# Rises quickly then eases off, fading only over the back half so the number is readable.
		var offset := Vector2(0.0, -RISE * sqrt(progress))
		var alpha := 1.0 - maxf(0.0, (progress - 0.5) * 2.0)
		var origin: Vector2 = popup["position"] + offset - Vector2(0.0, CLEARANCE)

		_draw_centred(font, origin, popup["points"], POINTS_SIZE, Color(1.0, 1.0, 1.0, alpha))
		# Above the points, not below: below is where the merged piece is.
		var multiplier: String = popup["multiplier"]
		if not multiplier.is_empty():
			_draw_centred(
				font,
				origin - Vector2(0.0, POINTS_SIZE * 0.9),
				multiplier,
				MULTIPLIER_SIZE,
				Color(Tuning.COLOR_POWER_HIGH, alpha)
			)


func _draw_centred(font: Font, centre: Vector2, text: String, size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(
		font, centre - Vector2(width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color
	)
