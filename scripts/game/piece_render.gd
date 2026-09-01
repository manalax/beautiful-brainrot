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

	var metrics := label_metrics(font, label.text)
	var width := metrics.x * size

	# Two-digit labels on tiers 10-12, and any label of more than one glyph, would otherwise
	# overflow the circle.
	var max_width := radius * Tuning.PIECE_LABEL_MAX_WIDTH_RATIO
	if width > max_width and width > 0.0:
		size = maxi(1, int(size * max_width / width))

	# Place the pen so that the middle of the inked pixels lands on the middle of the circle.
	canvas.draw_string(
		font,
		centre - Vector2(metrics.y, metrics.z) * size,
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


## Measured at this size and then scaled. Font metrics are linear in size, so one measurement
## describes every size a label is ever drawn at.
const METRIC_REFERENCE_SIZE := 64

## text -> (ink width, ink centre x, ink centre y), all per point of font size and all relative
## to the pen origin. See label_metrics().
static var _metrics: Dictionary = {}


## How wide a label's inked pixels are, and where the middle of those pixels sits relative to the
## pen origin — per point of font size, so one measurement serves every size.
##
## Measured from the actual glyph bitmaps, not from font metrics. Font metrics describe a *box*
## the glyph is laid out in, and a glyph is not centred in its own box: an emoji's box is sized
## to align it with a line of text, and centring the box leaves the emoji itself visibly high.
## Ascent and descent cannot fix this, whichever font they are read from. Only the ink can.
##
## Falls back to the nominal box when the text server cannot report glyph bitmaps, which is the
## behaviour this replaced — right for digits, off for emoji.
##
## Measured once per distinct label text and cached: this is a per-frame path for every piece on
## the table, and shaping 40 lines a frame to draw 40 circles would be absurd.
static func label_metrics(font: Font, text: String) -> Vector3:
	if _metrics.has(text):
		return _metrics[text]

	var line := TextLine.new()
	line.add_string(text, font, METRIC_REFERENCE_SIZE)

	var box := _ink_bounds(line)
	if box.size == Vector2.ZERO:
		box = Rect2(
			0.0,
			-line.get_line_ascent(),
			line.get_line_width(),
			line.get_line_ascent() + line.get_line_descent()
		)

	var measured := Vector3(
		box.size.x, box.get_center().x, box.get_center().y
	) / float(METRIC_REFERENCE_SIZE)

	_metrics[text] = measured
	return measured


## The union of the glyph bitmaps in a shaped line, relative to the pen origin. A zero-sized rect
## means the text server could not report them and the caller should use the nominal box.
static func _ink_bounds(line: TextLine) -> Rect2:
	var server := TextServerManager.get_primary_interface()
	if server == null:
		return Rect2()
	for required in ["shaped_text_get_glyphs", "font_get_glyph_offset", "font_get_glyph_size"]:
		if not server.has_method(required):
			return Rect2()

	var bounds := Rect2()
	var found := false
	var pen := 0.0

	for glyph: Dictionary in server.shaped_text_get_glyphs(line.get_rid()):
		var advance := float(glyph.get("advance", 0.0))
		var font_rid: RID = glyph.get("font_rid", RID())
		if font_rid.is_valid():
			var at := Vector2i(int(glyph.get("font_size", METRIC_REFERENCE_SIZE)), 0)
			var index := int(glyph.get("index", 0))
			var ink: Vector2 = server.font_get_glyph_size(font_rid, at, index)
			# A space, or a glyph the server declines to raster, has no ink to contribute.
			if ink != Vector2.ZERO:
				var origin := Vector2(
					pen + float(glyph.get("x_off", 0.0)), float(glyph.get("y_off", 0.0))
				)
				var offset: Vector2 = server.font_get_glyph_offset(font_rid, at, index)
				var glyph_box := Rect2(origin + offset, ink)
				bounds = glyph_box if not found else bounds.merge(glyph_box)
				found = true
		pen += advance

	return bounds if found else Rect2()


## Drops both cached measurements and the cached font chain, so the next draw re-resolves. Only
## the dev harness needs this; the two must go together, because the metrics describe the font.
static func reset_caches() -> void:
	_metrics.clear()
	_number_labels.clear()
	PieceFont.reset()


## Fills brighter than the threshold take the dark label. Computed from the fill actually being
## drawn, so it stays right both if a tier colour changes and while a piece is pulsing red.
static func label_color(fill: Color) -> Color:
	var bright := fill.get_luminance() > Tuning.PIECE_LABEL_DARK_ABOVE_LUMINANCE
	return Tuning.PIECE_LABEL_DARK if bright else Tuning.PIECE_LABEL_LIGHT
