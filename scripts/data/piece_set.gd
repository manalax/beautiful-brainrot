## One unlockable set of piece faces: twelve labels, a price, and the name the shop will show.
## See GAME_DESIGN.md §5.1.
##
## A set is cosmetic in full. It owns text, colour overrides and eventually textures; it owns no
## radius, no mass, and no physics, so no set can ever be worth buying for an advantage. The
## twelve-rung chain itself stays authored once, in `tiers.tres`.
##
## The `classic` set authors the plain tier numbers, so the game's original look is data like any
## other set rather than a special case in the renderer.
@tool
class_name PieceSet
extends Resource

## Stable identity. This is what gets written to the save file, so renaming one orphans a
## player's selection — the loader falls back to the default set when an id is unknown (§13).
@export var id: StringName = &""
## Shown in the shop and the set picker, neither of which exists yet.
@export var display_name: String = ""
## What this costs in the currency that is not implemented yet (§16). Zero means free: a set
## priced at zero is owned by everyone, which is how every set behaves until currency lands.
@export var price: int = 0

## Multiplies Tuning.PIECE_LABEL_SIZE_RATIO for this set alone. Digits read well at 1.0; emoji
## are square and sit small at the same size, so an emoji set wants roughly 1.4.
@export_range(0.5, 3.0, 0.05) var label_scale: float = 1.0

## Godot's `draw_string` modulate multiplies into colour bitmap glyphs, so the luminance-derived
## dark/light label colour would tint an emoji rather than leave it alone. Digit sets want the
## tint; emoji sets want their glyphs drawn as authored.
@export var label_tinted: bool = true

## Twelve entries, one per tier. Addressed by PieceLabel.tier, not by index.
@export var labels: Array[PieceLabel] = []


## The label for `tier`, or null if this set does not author one. Callers fall back to the
## default set rather than drawing nothing — see PieceSetRegistry.label_for().
func get_label(tier: int) -> PieceLabel:
	for label in labels:
		if label != null and label.tier == tier:
			return label
	return null


## Free sets are owned by definition. Everything else waits on the currency in §16.
func is_free() -> bool:
	return price <= 0


## Checks the set is complete and internally consistent, mirroring TierSet.validate(). Returns a
## list of problems, empty when the set is sound.
func validate() -> Array[String]:
	var problems: Array[String] = []

	if String(id).is_empty():
		problems.append("set has no id")
	if display_name.is_empty():
		problems.append("set '%s' has no display_name" % id)
	if price < 0:
		problems.append("set '%s' has a negative price (%d)" % [id, price])
	if labels.size() != Tuning.MAX_TIER:
		problems.append("set '%s': expected %d labels, found %d"
			% [id, Tuning.MAX_TIER, labels.size()])

	for tier in range(1, Tuning.MAX_TIER + 1):
		if get_label(tier) == null:
			problems.append("set '%s': tier %d is missing" % [id, tier])

	return problems
