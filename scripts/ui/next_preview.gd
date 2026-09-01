## The HUD's next-piece swatch (GAME_DESIGN.md §11): a caption and the piece that is coming after
## the one on the launcher, drawn at its true size so its tier reads from both colour and bulk.
##
## Draws through PieceRender, so the swatch and the piece on the table can never look different.
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
	var font := ThemeDB.fallback_font
	var caption_width := 0.0
	if font != null:
		caption_width = font.get_string_size(
			CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE
		).x
		draw_string(
			font,
			Vector2(0.0, size.y * 0.5 + font.get_ascent(CAPTION_SIZE) * 0.5
				- font.get_descent(CAPTION_SIZE) * 0.5),
			CAPTION,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			CAPTION_SIZE,
			Tuning.COLOR_HUD_CAPTION
		)

	if _data == null:
		return

	# Reserve a slot as wide as the largest tier that can be drawn, so the swatch does not shift
	# around as the queue changes.
	var slot := _widest_spawn_radius()
	var centre := Vector2(caption_width + 20.0 + slot, size.y * 0.5)
	PieceRender.draw_piece(self, centre, _data.radius, _data, GameState.active_set)


func _widest_spawn_radius() -> float:
	var tiers := TierSet.load_default()
	return tiers.get_tier(Tuning.SPAWN_TIER_WEIGHTS.size()).radius
