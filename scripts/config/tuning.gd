## Every tunable constant in the game, and nothing else.
##
## This is the single place a designer changes numbers. No magic numbers belong in scene
## scripts. Values here are sourced from GAME_DESIGN.md; when you tune one, update the doc.
## Registered as the `Tuning` autoload, so reach it from anywhere as `Tuning.PIECE_LINEAR_DAMP`.
##
## `@tool` so that @tool scenes (the table's editor preview) can read these constants in-editor.
## There is no runtime logic here — only constants — so running in the editor is inert.
@tool
extends Node

# --- Layout (design-resolution pixels, see GAME_DESIGN.md §4) ---------------------------------

## Design resolution. All layout constants below are in this space.
const DESIGN_SIZE := Vector2(1080.0, 1920.0)
## HUD band across the top; not aimable surface.
const HUD_BAND_HEIGHT := 220.0
## Inner face of the walls — the area pieces can actually occupy.
const PLAYFIELD_RECT := Rect2(40.0, 260.0, 1000.0, 1600.0)
## Visual thickness of the walls, drawn just outside PLAYFIELD_RECT.
const WALL_THICKNESS := 40.0
## How deep the wall *colliders* run, outward from the same inner face. Much thicker than the
## drawn wall and mostly off-screen: at 60Hz a full-power piece advances ~43px per step and sinks
## ~35px into a wall before the solver answers, so a 40px-deep collider is a tunnelling risk.
## Costs nothing — see GAME_DESIGN.md §6.
const WALL_COLLIDER_DEPTH := 240.0
## Below this line is the launch lane; an object resting there ends the run.
const DANGER_LINE_Y := 1660.0
## Height of the launch lane (DANGER_LINE_Y to the bottom wall).
const LAUNCH_LANE_HEIGHT := 200.0
## The launcher's fixed y. Only its x varies.
const LAUNCHER_Y := 1780.0

## On a screen taller than the 9:16 design box, this much of the surplus height is placed *above*
## the play area and the remainder below it. Biased hard toward the top on purpose: the launcher
## sits at the bottom edge and has to stay under the thumb. 0.5 would centre the table; 1.0 would
## pin it flush to the bottom. See GAME_DESIGN.md §4.2.
const CAMERA_TOP_BIAS := 0.86

# --- Placeholder palette (§4.1) ----------------------------------------------------------------

## Behind everything, including the HUD band. Also set as the project's default clear color.
const COLOR_SURROUND := Color("#141922")
## The table surface itself.
const COLOR_TABLE_BG := Color("#1E2430")
## Slightly lifted from the table so the launch lane reads as its own zone.
const COLOR_LAUNCH_LANE := Color("#2A3242")
const COLOR_WALL := Color("#3E4859")
## Idle danger line. Amber rather than red so it is not confused with a tier-1 piece.
const COLOR_DANGER_LINE := Color("#F5A623")
## Danger line and at-risk pieces pulse to this during the grace period (F8).
const COLOR_DANGER_WARNING := Color("#E74C3C")

## HUD captions ("NEXT", "SCORE", "BEST") — present but never competing with the board.
const COLOR_HUD_CAPTION := Color("#8A94A6")

## The tier progression guide (§11). Caption weight on purpose: it is furniture the player reads
## between shots, not a readout. Emoji sets ignore this and draw as authored.
const COLOR_TIER_GUIDE := Color("#8A94A6")
## How much of its cell the widest label fills, and the ceiling on label size as a fraction of the
## guide's height. The first almost always wins — twelve cells across ~580px is the tight axis.
const TIER_GUIDE_CELL_FILL := 0.8
const TIER_GUIDE_HEIGHT_FILL := 0.75

const DANGER_LINE_WIDTH := 4.0
## Length of each dash; draw_dashed_line uses an equal gap.
const DANGER_LINE_DASH := 26.0

# --- Piece rendering (§5) ----------------------------------------------------------------------

## Outline width, as a fraction of the piece's radius, clamped to the bounds below. A flat 3px
## outline reads as a hairline on the big tiers, so it scales.
const PIECE_OUTLINE_RATIO := 0.09
const PIECE_OUTLINE_MIN := 3.0
const PIECE_OUTLINE_MAX := 9.0
## How much darker than the fill the outline is drawn.
const PIECE_OUTLINE_DARKEN := 0.35

## Label height as a fraction of radius, and the widest it may get before being shrunk to fit
## (two-digit labels on tiers 10-12). A piece set scales the first of these by its own
## `label_scale`, because emoji are square and read small at a size that suits a digit.
const PIECE_LABEL_SIZE_RATIO := 1.05
const PIECE_LABEL_MAX_WIDTH_RATIO := 1.15
## Fills brighter than this get the dark label, everything else the light one. Computed rather
## than listed per tier so it stays correct if a colour changes.
const PIECE_LABEL_DARK_ABOVE_LUMINANCE := 0.6
const PIECE_LABEL_DARK := Color("#161B24")
const PIECE_LABEL_LIGHT := Color("#FFFFFF")

# --- Piece sets (§5.1) -------------------------------------------------------------------------

## The registry of shippable sets, and the id selected when the save has nothing to say.
const PIECE_SET_REGISTRY_PATH := "res://resources/piece_sets.tres"
const DEFAULT_PIECE_SET := &"classic"

## Platform emoji fonts, tried in this order before the bundled one. See PieceFont.
const EMOJI_FONT_NAMES := Array([
	"Apple Color Emoji",
	"Noto Color Emoji",
	"Segoe UI Emoji",
	"Twemoji Mozilla",
])
## Shipped so that a device resolving none of the names above still draws colour emoji rather
## than tofu. CBDT bitmap build — the one Godot's FreeType reads.
const EMOJI_FONT_PATH := "res://resources/fonts/NotoColorEmoji.ttf"

# --- Juice (§12 F11) ---------------------------------------------------------------------------

## A merged piece flares toward this, briefly, so the merge is felt rather than just noticed.
const COLOR_MERGE_FLASH := Color("#FFFFFF")
const PIECE_FLASH_TIME := 0.11

## A merged piece grows into place instead of appearing at full size. The drawn radius only —
## the collision shape is never scaled, so this cannot touch the physics.
const PIECE_POP_TIME := 0.19
const PIECE_POP_FROM := 0.62
## How far past full size the pop swells at its midpoint.
const PIECE_POP_OVERSHOOT := 1.08

## Wall impacts below this speed are not worth marking.
const SPARK_MIN_SPEED := 420.0
const SPARK_LIFETIME := 0.26
## Arc radius at the fastest impact the game allows; slower hits scale down from here.
const SPARK_MAX_RADIUS := 74.0
const SPARK_WIDTH := 7.0
## Nudges the arc off the wall face so it is not half-buried in the wall, or clipped at the edge
## of the viewport on a side wall.
const SPARK_INSET := 9.0
## Half-angle of the arc drawn against the wall.
const SPARK_SPREAD := 1.15
const COLOR_SPARK := Color("#FFFFFF")

## Overlays fade in and their panel settles, rather than snapping into place.
const OVERLAY_FADE_TIME := 0.22
const OVERLAY_PANEL_FROM := 0.94

# --- Physics (§6) ------------------------------------------------------------------------------

## Viscous drag term. Scales with speed, so it does most of its work early in a shot.
## Set `linear_damp_mode = REPLACE` on bodies so this value is authoritative and does not
## combine with the project's default damping.
const PIECE_LINEAR_DAMP := 0.78
## Coulomb (dry) friction term, in px/s². Constant deceleration regardless of speed — this is
## what a real object sliding on a table feels, and it brings pieces to a genuine dead stop
## rather than an asymptotic crawl, which the danger-zone rest check in §9 depends on.
## Total deceleration is PIECE_LINEAR_DAMP * v + PIECE_FRICTION_DECEL; see GAME_DESIGN.md §6.
const PIECE_FRICTION_DECEL := 258.0
const PIECE_ANGULAR_DAMP := 3.0
const PIECE_FRICTION := 0.2
const PIECE_BOUNCE := 0.35
## Required for merge detection; the first lever to pull if physics gets expensive.
const PIECE_MAX_CONTACTS_REPORTED := 6
## Hard ceiling applied in _integrate_forces. Merges can otherwise compound velocity.
const PIECE_MAX_SPEED := 3000.0

const WALL_FRICTION := 0.1
## Bouncier than the pieces, so bank shots stay lively.
const WALL_BOUNCE := 0.6
## The restitution the engine ACTUALLY applies to a piece-wall contact, which is not WALL_BOUNCE
## alone: Godot combines the two materials additively. Measured at 0.942 against a predicted
## 0.95, the rest lost to contact friction. The aim guide needs this to predict a rebound that
## matches the real one; the F4 harness re-measures it and fails if it drifts.
## Derived, so it tracks the two it depends on — but cap it by hand if they ever sum above 1.0.
const WALL_RESTITUTION := PIECE_BOUNCE + WALL_BOUNCE

## mass = (radius / MASS_BASE_RADIUS) ^ MASS_EXPONENT.
## Deliberately sub-quadratic: big pieces are heavy but never immovable scenery. Do not
## "correct" this to be physically accurate — see GAME_DESIGN.md §5.
const MASS_BASE_RADIUS := 26.0
const MASS_EXPONENT := 1.5

# --- Collision layers (§6) ---------------------------------------------------------------------

const LAYER_PIECES := 1 << 0
const LAYER_WALLS := 1 << 1
const LAYER_DANGER_ZONE := 1 << 2
const LAYER_UI_TOUCH := 1 << 3

# --- Input and firing (§7) ---------------------------------------------------------------------

## Drag distance at which the launcher locks its x and aiming begins.
const AIM_DEADZONE := 24.0
## Drag distance corresponding to full power.
const DRAG_MAX := 320.0
const SPEED_MIN := 500.0
const SPEED_MAX := 2600.0
## Eased slightly so low power stays controllable:
## speed = lerp(SPEED_MIN, SPEED_MAX, pow(power, POWER_CURVE_EXPONENT))
const POWER_CURVE_EXPONENT := 1.15
## Reload beat between shots. Not a wait for the table to settle.
const SHOT_COOLDOWN := 0.4

# --- Aim guide (§7) ----------------------------------------------------------------------------

const AIM_LINE_MIN_LENGTH := 200.0
const AIM_LINE_MAX_LENGTH := 900.0
## Exactly one. Two makes the game solvable rather than skilful.
const AIM_MAX_BOUNCES := 1

## Spacing and size of the dots making up the guide line.
const AIM_DOT_SPACING := 32.0
const AIM_DOT_RADIUS := 5.0
const COLOR_AIM_DOT := Color(1.0, 1.0, 1.0, 0.72)
## The segment past the bounce is dimmer — it is a prediction of a prediction.
const COLOR_AIM_DOT_BOUNCED := Color(1.0, 1.0, 1.0, 0.34)

## Ring drawn on the piece the shot is currently pointed at.
const AIM_TARGET_RING_GAP := 7.0
const AIM_TARGET_RING_WIDTH := 4.0
const COLOR_AIM_TARGET := Color(1.0, 1.0, 1.0, 0.85)

## Power arc, drawn around the held piece: a full turn at power 1.0.
const POWER_ARC_GAP := 11.0
const POWER_ARC_WIDTH := 7.0
const COLOR_POWER_LOW := Color("#6FE3D2")
const COLOR_POWER_HIGH := Color("#FF7A5A")

# --- Merging (§8) ------------------------------------------------------------------------------

const MAX_TIER := 12
## Merged velocity = average of the two, scaled. Not momentum conservation — the merged mass is
## less than the sum of parts, so true conservation would make merges accelerate.
const MERGE_MOMENTUM_SCALE := 0.85
## A freshly merged piece cannot merge again for this many physics frames. Prevents same-frame
## cascades while still allowing chains on subsequent ticks.
const MERGE_COOLDOWN_FRAMES := 1

# --- Spawn queue (§9) --------------------------------------------------------------------------

## Weights for tiers 1..5, in order. Index 0 is tier 1.
const SPAWN_TIER_WEIGHTS: Array[int] = [30, 25, 20, 15, 10]

# --- Loss condition (§9) -----------------------------------------------------------------------

## At or below this speed a piece counts as at rest for danger purposes.
const REST_SPEED := 30.0
## How long a piece may rest in the launch lane before the run ends.
const DANGER_GRACE := 2.0
## Warning pulse begins at this point in the grace period, leaving a full second to react.
const DANGER_WARNING_AT := 1.0
## How fast the warning throbs. A steady tint reads as a colour change; a pulse says "act now".
const DANGER_PULSE_HZ := 2.5

# --- Scoring (§10) -----------------------------------------------------------------------------

## Merging into tier N scores N * N * SCORE_TIER_FACTOR.
const SCORE_TIER_FACTOR := 10
## Awarded when two tier-12s annihilate.
const TIER12_BONUS := 2000
## Indexed by chain depth within the current shot; the last entry is the cap.
const CHAIN_MULTIPLIERS: Array[float] = [1.0, 1.5, 2.0, 2.5, 3.0]

# --- Save data (§13) ---------------------------------------------------------------------------

const SAVE_PATH := "user://save.json"
## Written first, then renamed, so an interrupted write cannot destroy an existing save.
const SAVE_TMP_PATH := "user://save.json.tmp"
const SAVE_VERSION := 1
const TOP_SCORES_COUNT := 10

# --- Performance (§15) -------------------------------------------------------------------------

## Target simultaneous pieces at 60fps. Exceeding ~60 signals a balance problem, not a slow engine.
const TARGET_PIECE_COUNT := 40
