## The tier progression guide in the HUD band (GAME_DESIGN.md §11): all twelve tiers in merge
## order, so a new player can see what they are building toward.
##
## Text alone — no circles, no tier colours. The board already carries the colour, and repeating
## it in the HUD would compete with the thing it is meant to explain. This is a reference the
## player consults between shots, not something read at a glance mid-run, so it stays quiet:
## always the full chain, never highlighted, never animated.
##
## Reads the active piece set directly instead of being fed by the Hud, because it depends on
## nothing else — no score, no queue, no run state. It repaints when the set changes or when it
## is resized, and at no other time.
class_name TierGuide
extends Control


func _ready() -> void:
	GameState.piece_set_changed.connect(func(_set: PieceSet) -> void: queue_redraw())
	resized.connect(queue_redraw)


func _draw() -> void:
	var font := PieceFont.label_font()
	if font == null:
		return

	var piece_set := GameState.active_set
	var font_size := label_size()
	if font_size <= 0:
		return

	# Emoji carry their own colour and `draw_string` multiplies its modulate into colour bitmap
	# glyphs, so tinting an emoji set would recolour it. Same rule as a piece (§5.2).
	var tint := Tuning.COLOR_TIER_GUIDE
	if piece_set != null and not piece_set.label_tinted:
		tint = Color.WHITE

	for tier in range(1, Tuning.MAX_TIER + 1):
		var label := _label_for(tier)
		if label == null or label.text.is_empty():
			continue
		# Centred on the ink, through the same measurement a piece uses, so a glyph sits the same
		# way here as it does on the table.
		var metrics := PieceRender.label_metrics(font, label.text)
		draw_string(
			font,
			cell_centre(tier) - Vector2(metrics.y, metrics.z) * font_size,
			label.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			tint
		)


## The middle of the cell tier `tier` occupies. Twelve equal cells across the full width.
func cell_centre(tier: int) -> Vector2:
	return Vector2((tier - 0.5) * cell_width(), size.y * 0.5)


func cell_width() -> float:
	return size.x / float(Tuning.MAX_TIER)


## One size for the whole row, chosen so the *widest* label fits its cell. Sizing each tier to its
## own glyph would leave the row visibly ragged; sizing to the widest keeps them uniform and
## guarantees none of them overflows.
func label_size() -> int:
	var font := PieceFont.label_font()
	if font == null or size.x <= 0.0 or size.y <= 0.0:
		return 0

	var widest := 0.0
	for tier in range(1, Tuning.MAX_TIER + 1):
		var label := _label_for(tier)
		if label == null or label.text.is_empty():
			continue
		widest = maxf(widest, PieceRender.label_metrics(font, label.text).x)

	if widest <= 0.0:
		return 0

	# Bounded on both axes: by the cell it has to fit across, and by the band it has to fit down.
	var by_width := cell_width() * Tuning.TIER_GUIDE_CELL_FILL / widest
	return int(minf(by_width, size.y * Tuning.TIER_GUIDE_HEIGHT_FILL))


## The twelve texts in tier order, as they will be drawn. Used by the dev harness.
func labels() -> PackedStringArray:
	var out := PackedStringArray()
	for tier in range(1, Tuning.MAX_TIER + 1):
		var label := _label_for(tier)
		out.append(label.text if label != null else "")
	return out


## Goes through the registry rather than the set directly, so a set with a hole in it shows that
## tier's number here exactly as it would on the table.
func _label_for(tier: int) -> PieceLabel:
	var registry := GameState.piece_sets
	if registry == null:
		return null
	return registry.label_for(GameState.active_set, tier)
