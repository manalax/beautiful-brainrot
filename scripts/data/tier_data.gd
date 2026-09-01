## One rung of the merge chain: how big it is, and what colour it draws by default. See
## GAME_DESIGN.md §5 for the authored table of all twelve.
##
## This is the *gameplay* half of a piece. It is authored once, in `tiers.tres`, and no piece set
## can override any of it — that is what stops an unlockable set from changing the balance of the
## game. The cosmetic half (text, colour overrides, art) lives on PieceLabel; see §5.1.
##
## Mass is derived, not authored — it is always `(radius / MASS_BASE_RADIUS) ^ MASS_EXPONENT`, so
## changing a radius can never leave a stale mass behind. If per-tier hand-tuning is ever needed,
## add an optional override field rather than making mass a plain export.
@tool
class_name TierData
extends Resource

## 1..12. Tier 12 is terminal: two of them annihilate rather than merging (§8).
@export_range(1, 12, 1) var tier: int = 1
## Collision radius and draw radius, in design-resolution pixels.
@export var radius: float = 26.0
## Default fill colour of the placeholder circle; the outline and the label colour are derived
## from whatever fill is actually drawn. A piece set may override this per tier (PieceLabel).
@export var color: Color = Color.WHITE


## Sub-quadratic in radius on purpose: big pieces are heavy but never immovable scenery.
## Do not "correct" this to be physically accurate — see GAME_DESIGN.md §5.
var mass: float:
	get:
		return pow(radius / Tuning.MASS_BASE_RADIUS, Tuning.MASS_EXPONENT)
