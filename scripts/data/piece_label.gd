## What one tier *looks like* in one piece set: the text drawn on it, and optional overrides for
## its colour and its art. See GAME_DESIGN.md §5.1.
##
## Purely cosmetic. Nothing here can touch radius or mass — those stay on TierData, so an
## unlockable set can never shift the balance of the game.
##
## `color` and `texture` are overrides, not values: left unset, the tier's own authored colour
## from `tiers.tres` is used. A set that only changes text therefore authors no colours at all.
@tool
class_name PieceLabel
extends Resource

## 1..12. Matched against TierData.tier, never used as an array index.
@export_range(1, 12, 1) var tier: int = 1
## Drawn centred on the piece. One or two glyphs — emoji included, see §5.2 on the font chain.
## Empty draws nothing, which is how a texture-only set opts out of text.
@export var text: String = ""
## Transparent means "use the tier's colour from tiers.tres".
@export var color: Color = Color.TRANSPARENT
## Null through the placeholder phase. The art swap fills these in (§3, decision 15).
@export var texture: Texture2D = null


## The fill this label wants, given the tier's authored default.
func resolve_color(default_color: Color) -> Color:
	return default_color if color.a <= 0.0 else color
