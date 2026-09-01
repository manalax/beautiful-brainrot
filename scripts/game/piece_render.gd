## Draws a piece's placeholder look. Shared so the HUD's next-piece swatch and the piece on the
## table are literally the same drawing code and cannot drift apart.
##
## A piece is drawn from two halves: the TierData fixes its size and default colour (gameplay),
## and the PieceSet supplies the face — the text on it, any colour override, and eventually the
## texture. See GAME_DESIGN.md §5.1.
##
## This stays a pure static helper and never reads GameState. Callers resolve the set they want,
## which is what lets the dev harness draw every set side by side without touching global state.
class_name PieceRender
extends RefCounted


## `piece_set` supplies the face; null falls back to the tier number, which is what the classic
## set authors anyway.
##
## `fill_override` replaces the tier's colour when it is not transparent. Callers work out their
## own fill — a piece stacks the danger pulse and the merge flash onto it — and the outline and
## the label both follow whatever comes out, so a piece stays readable however it is tinted.
static func draw_piece(
	canvas: CanvasItem,
	centre: Vector2,
	radius: float,
	data: TierData,
	piece_set: PieceSet = null,
	fill_override := Color.TRANSPARENT
) -> void:
	if data == null:
		return

	var label := _resolve_label(piece_set, data.tier)

	# Highest priority first: the caller's tint, then the set's override, then the tier's colour.
	var fill := base_fill(data, piece_set)
	if fill_override.a > 0.0:
		fill = fill_override

	canvas.draw_circle(centre, radius, fill)

	var outline := clampf(
		radius * Tuning.PIECE_OUTLINE_RATIO, Tuning.PIECE_OUTLINE_MIN, Tuning.PIECE_OUTLINE_MAX
	)
	# Arcs straddle the radius, so pull inward by half the width to keep the outline inside the
	# piece's actual collision circle.
	canvas.draw_arc(
		centre,
		radius - outline * 0.5,
		0.0,
		TAU,
		clampi(int(radius), 24, 96),
		fill.darkened(Tuning.PIECE_OUTLINE_DARKEN),
		outline,
		true
	)

	_draw_label(canvas, centre, radius, label, piece_set, fill)


## The colour a piece is drawn in before any caller tint: the set's override if it has one, the
## tier's authored colour otherwise.
##
## Callers that build their own fill must start from this rather than from `data.color`, or a set
## that overrides a colour would be honoured in the HUD swatch and silently ignored on the table.
static func base_fill(data: TierData, piece_set: PieceSet) -> Color:
	if data == null:
		return Color.WHITE
	var label := _resolve_label(piece_set, data.tier)
	return label.resolve_color(data.color) if label != null else data.color


## Plain tier numbers, built once. This is a per-frame path for every piece on the table, so the
## fallback cannot allocate — at the §15 target of 40 pieces that would be ~2400 throwaway
## resources a second.
static var _number_labels: Array[PieceLabel] = []


## The set's label for this tier, or the tier number when no set authors one. The fallback is
## built here rather than left to callers so that a set with a hole in it degrades to a readable
## piece instead of a blank circle.
static func _resolve_label(piece_set: PieceSet, tier: int) -> PieceLabel:
	if piece_set != null:
		var label := piece_set.get_label(tier)
		if label != null:
			return label

	if _number_labels.is_empty():
		for n in range(1, Tuning.MAX_TIER + 1):
			var fallback := PieceLabel.new()
			fallback.tier = n
			fallback.text = str(n)
			_number_labels.append(fallback)

	if tier < 1 or tier > _number_labels.size():
		return null
	return _number_labels[tier - 1]


static func _draw_label(
	canvas: CanvasItem,
	centre: Vector2,
	radius: float,
	label: PieceLabel,
	piece_set: PieceSet,
	fill: Color
) -> void:
	if label == null or label.text.is_empty():
		return

	var font := PieceFont.label_font()
	if font == null:
		return

	var label_scale := piece_set.label_scale if piece_set != null else 1.0
	var size := int(radius * Tuning.PIECE_LABEL_SIZE_RATIO * label_scale)
	if size <= 0:
		return

	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

	# Two-digit labels on tiers 10-12, and any label of more than one glyph, would otherwise
	# overflow the circle.
	var max_width := radius * Tuning.PIECE_LABEL_MAX_WIDTH_RATIO
	if width > max_width and width > 0.0:
		size = maxi(1, int(size * max_width / width))
		width = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

	# draw_string anchors to the baseline, so offset by half the visual height to centre it.
	var baseline := (font.get_ascent(size) - font.get_descent(size)) * 0.5
	canvas.draw_string(
		font,
		centre + Vector2(-width * 0.5, baseline),
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		_modulate_for(piece_set, fill)
	)


## Digit sets take the computed dark/light label colour. Emoji sets do not: `draw_string`
## multiplies its modulate into colour bitmap glyphs, so tinting would recolour the emoji instead
## of leaving it as authored. Hence PieceSet.label_tinted.
static func _modulate_for(piece_set: PieceSet, fill: Color) -> Color:
	if piece_set != null and not piece_set.label_tinted:
		return Color.WHITE
	return label_color(fill)


## Fills brighter than the threshold take the dark label. Computed from the fill actually being
## drawn, so it stays right both if a tier colour changes and while a piece is pulsing red.
static func label_color(fill: Color) -> Color:
	var bright := fill.get_luminance() > Tuning.PIECE_LABEL_DARK_ABOVE_LUMINANCE
	return Tuning.PIECE_LABEL_DARK if bright else Tuning.PIECE_LABEL_LIGHT
