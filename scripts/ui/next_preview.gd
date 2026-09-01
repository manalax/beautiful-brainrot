## The HUD's next-piece swatch (GAME_DESIGN.md §11): a caption and the label of the piece coming
## after the one on the launcher.
##
## The label alone — no circle, no outline. Size still tracks the tier's radius, so a bigger tier
## still reads as bigger, and a digit set keeps the tier's colour: with the circle gone those are
## the only two signals of which tier is coming, and dropping both would leave "8" and "3" telling
## the player nothing apart. Emoji sets draw untinted, as everywhere else (§5.2).
##
## Sized and centred through PieceRender, so the glyph sits in the swatch exactly as it will on
## the table.
class_name NextPreview
extends Control

const CAPTION := "NEXT"
const CAPTION_SIZE := 30

var _data: TierData = null


func _ready() -> void:
	# The swatch is drawn from the active set like any piece, so it has to repaint when the set
	# changes rather than waiting for the next queue advance.
	GameState.piece_set_changed.connect(func(_set: PieceSet) -> void: queue_redraw())


func show_tier(data: TierData) -> void:
	_data = data
	queue_redraw()


## The tier currently on show, or 0 when empty. Used by the F6 harness.
func shown_tier() -> int:
	return _data.tier if _data != null else 0


func _draw() -> void:
	var caption_font := ThemeDB.fallback_font
	var caption_width := 0.0
	if caption_font != null:
		caption_width = caption_font.get_string_size(
			CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE
		).x
		draw_string(
			caption_font,
			Vector2(0.0, size.y * 0.5 + caption_font.get_ascent(CAPTION_SIZE) * 0.5
				- caption_font.get_descent(CAPTION_SIZE) * 0.5),
			CAPTION,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			CAPTION_SIZE,
			Tuning.COLOR_HUD_CAPTION
		)

	if _data == null:
		return

	var font := PieceFont.label_font()
	if font == null:
		return

	var piece_set := GameState.active_set
	var label := GameState.piece_sets.label_for(piece_set, _data.tier) \
		if GameState.piece_sets != null else null
	if label == null or label.text.is_empty():
		return

	# The size a piece of this tier would draw its label at, so the swatch and the table agree.
	var label_scale := piece_set.label_scale if piece_set != null else 1.0
	var font_size := int(_data.radius * Tuning.PIECE_LABEL_SIZE_RATIO * label_scale)
	if font_size <= 0:
		return

	# Reserve a slot as wide as the largest tier that can be drawn, so the swatch does not shift
	# around as the queue changes.
	var slot := _widest_spawn_radius()
	var centre := Vector2(caption_width + 20.0 + slot, size.y * 0.5)

	var metrics := PieceRender.label_metrics(font, label.text)
	draw_string(
		font,
		centre - Vector2(metrics.y, metrics.z) * font_size,
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		_tint(piece_set, label)
	)


## A digit set takes the tier's colour, which is the only colour signal left once the circle is
## gone. An emoji set draws as authored: `draw_string` multiplies its modulate into colour bitmap
## glyphs, so a tint would recolour the emoji rather than leave it alone.
func _tint(piece_set: PieceSet, label: PieceLabel) -> Color:
	if piece_set != null and not piece_set.label_tinted:
		return Color.WHITE
	return label.resolve_color(_data.color)


func _widest_spawn_radius() -> float:
	var tiers := TierSet.load_default()
	return tiers.get_tier(Tuning.SPAWN_TIER_WEIGHTS.size()).radius
