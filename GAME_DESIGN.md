# Game Design Document — *suika-brainrot-like*

**Working title:** Slide Merge (placeholder)
**Engine:** Godot 4.6, Mobile renderer, **2D**
**Platform:** Mobile (Android + iOS), portrait
**Status:** Design locked. Built through F11 — only the F12 balance pass remains. See §12.

> **Purpose of this document.** This is the build spec. Future Claude sessions should read this
> file first, pick the next unbuilt feature from [§12 Build Roadmap](#12-build-roadmap), implement
> it against its acceptance criteria, and update the roadmap checkboxes. Every number in here is a
> starting value, not a law — but numbers live in **one** place in code
> (`res://scripts/config/tuning.gd`), so tuning never means hunting through scenes.

---

## 1. One-paragraph pitch

A physics merge game in the Suika family, but the table is horizontal and you *shoot*. You look
straight down at a walled table. At the bottom edge sits your next object; you place it along that
edge with your thumb, then drag back to slingshot it across the table. Objects slide, ricochet off
the walls, and slow to a stop under table friction. When two objects of the same tier touch, they
fuse into the next tier up — carrying their momentum, so a good shot can chain three or four merges
in one go. Twelve tiers. Two tier-12s annihilate for a huge bonus. Let the table clog up into your
own launch lane and the run is over.

## 2. Design pillars

1. **Skill lives in the shot.** Angle, power, and launch position are all yours. There is no drop
   chute, no gravity funnel, no luck about where the piece lands. Bank shots off walls are the
   skill ceiling.
2. **It reads as a table, not a jar.** Top-down, zero gravity, friction-driven. Objects slide and
   coast. Nothing stacks, nothing falls.
3. **Momentum is the reward.** Merges keep moving, so the good shot is the one that sets off a
   chain. Combo multipliers pay that off explicitly.
4. **Legible at a glance on a phone.** Flat colored circles, high contrast, each tier a distinct
   hue and ~14% larger than the last. Board state readable in half a second at arm's length. The
   face on a piece is set by the active piece set (§5.1) and is *not* load-bearing for that: the
   classic set numbers them, others carry emoji, and tier identity has to survive either.
5. **Offline and self-contained.** No network, no accounts, no analytics. Scores live on device.

## 3. Locked design decisions

These were decided with the project owner. Do not silently revisit them.

| # | Decision | Chosen |
|---|---|---|
| 1 | Rendering & physics | **Pure 2D top-down.** Godot 2D physics, `RigidBody2D`, zero gravity, `linear_damp` as table friction |
| 2 | Table boundaries | **Four bouncy walls.** Nothing ever leaves the table |
| 3 | Loss condition | **An object comes to rest in the launch lane** (the bottom strip below the danger line) and stays there past a grace period |
| 4 | Aim input | **Slingshot.** Touch to place, drag backwards, release to fire. Drag length = power, drag angle = direction (fires opposite the drag) |
| 5 | Launch position | **Slides along the bottom edge.** Player positions the piece horizontally before aiming |
| 6 | Aim assist | **Dotted trajectory with one predicted wall bounce**, plus a power indicator |
| 7 | Merge behaviour | **Spawns at the midpoint, keeps combined momentum.** Chains are possible and encouraged |
| 8 | Tier count | **12 tiers**, each ~14% larger in radius than the last |
| 9 | Spawn pool | **Random from tiers 1–5**, weighted toward the low tiers |
| 10 | Tier 12 + tier 12 | **Both vanish, large score bonus**, table pressure relieved |
| 11 | Shot pacing | **~0.4s cooldown** between shots. No waiting for the table to settle |
| 12 | Hold / swap | **None.** You see current + next and must play them in order |
| 13 | Scoring | **Per-merge, scaling with tier, with a per-shot chain multiplier** |
| 14 | v1 scope | **Main menu → game → game over → local high scores.** Audio, settings, haptics deferred |
| 15 | Art | **Placeholder colored primitives** now. The *look* of a piece is authored separately from its physics (§5.1), so a texture swap stays a one-field change — the field moved from `TierData` to `PieceLabel` when piece sets landed, and there can now be more than one set of them |

## 4. Screen layout and coordinate space

Design resolution: **1080 × 1920** (portrait). Stretch mode `canvas_items`, aspect `expand`, so
taller/shorter phones gain or lose vertical space; all layout is anchored, never hardcoded to
1920 except the constants below.

```
 y=0    ┌──────────────────────────────┐
        │  SCORE 12,480      BEST 31k  │   HUD band (y 0–220)
        │  NEXT ●                      │
 y=260  ├══════════════════════════════┤  ← top wall
        │                              │
        │      ●        ⬤              │
        │   ●      ●         ●         │   PLAYFIELD
        │        ⬤       ●             │   x 40–1040 (1000 wide)
        │   ●        ●        ●        │   y 260–1860 (1600 tall)
        │                              │
 y=1660 ├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤  ← DANGER LINE
        │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │   LAUNCH LANE (200 tall)
        │ ←──────────  ●  ──────────→  │   launcher y = 1780
 y=1860 └══════════════════════════════┘  ← bottom wall
```

| Constant | Value | Notes |
|---|---|---|
| `PLAYFIELD_RECT` | x 40 → 1040, y 260 → 1860 | Inner face of the walls |
| `WALL_THICKNESS` | 40 px | How thick the walls are *drawn*, just outside the playfield |
| `WALL_COLLIDER_DEPTH` | 240 px | How deep the wall *colliders* run outward, mostly off-screen — see §6 |
| `DANGER_LINE_Y` | 1660 | Visual dashed line + `Area2D` top edge |
| `LAUNCH_LANE` | y 1660 → 1860 | The danger zone **and** the launcher's track |
| `LAUNCHER_Y` | 1780 | Fixed; only x varies |
| `LAUNCHER_X_RANGE` | 40 + r → 1040 − r | Clamped per-piece by its radius |

The playfield is ~2.4 tier-12 diameters wide. That is deliberate: at the top of the chain the
table feels genuinely crowded.

### 4.1 Placeholder palette

The table is deliberately dark and low-saturation so the twelve saturated tier colours in §5 are
the only things on screen competing for attention.

| Constant | Colour | Used for |
|---|---|---|
| `COLOR_SURROUND` | `#141922` | Behind everything, HUD band included. Also the project's default clear colour |
| `COLOR_TABLE_BG` | `#1E2430` | The table surface |
| `COLOR_LAUNCH_LANE` | `#2A3242` | The strip below the danger line, lifted just enough to read as its own zone |
| `COLOR_WALL` | `#3E4859` | The four walls |
| `COLOR_DANGER_LINE` | `#F5A623` amber | Idle danger line. Amber, not red, so it is never mistaken for a tier-1 piece |
| `COLOR_DANGER_WARNING` | `#E74C3C` red | What the line and at-risk pieces pulse to during the grace period (F8) |

The danger line is dashed, 4 px wide, 26 px dashes.

### 4.2 Fitting real screens

The design box is 9:16. Almost no phone is: 19.5:9 and 20:9 are the norm, and a tablet is wider.
`expand` keeps the design box anchored at the origin and adds the surplus after it, which put a
dead band under the launch lane on every modern phone — a fifth of the screen on a 20:9 device,
with the launcher pushed up out of thumb reach.

**The playfield is never stretched to fit.** Every constant in §6 and every score in §10 assumes a
1000x1600 table, so growing it on a taller phone would quietly make a run on one device a
different game from a run on another. The surplus is *placed* instead, by `TableCamera`:

- **Horizontally**, the design box is centred — a tablet gets even margins either side.
- **Vertically**, `CAMERA_TOP_BIAS` (0.86) of the surplus goes *above* the play area and the rest
  below it. Biased hard toward the top on purpose: the launcher sits at the bottom edge and has to
  stay under the thumb, so the one place the space must not go is beneath the launch lane.

At the design aspect the camera resolves to the exact centre of the design box and is a complete
no-op, which is why every harness that assumes screen coordinates equal world coordinates still
holds. It repositions on `size_changed`, so a rotation or a resize is handled.

The camera is also the hook screen shake would need, if F11's unbuilt items are ever revisited.

## 5. Tier table

Authored as a `TierSet` Resource (`res://resources/tiers.tres`) so it is editable in the inspector
and swappable for themed art later. Each entry:

```gdscript
# res://scripts/data/tier_data.gd
class_name TierData extends Resource
@export var tier: int          # 1..12
@export var radius: float      # px at design resolution
@export var color: Color
@export var texture: Texture2D # null during placeholder phase — art swap fills this in

var mass: float:               # derived from radius, never authored
	get: return pow(radius / Tuning.MASS_BASE_RADIUS, Tuning.MASS_EXPONENT)
```

The twelve live in a `TierSet` (`res://scripts/data/tier_set.gd`), which owns lookup by tier
number, `next_tier()`, and a `validate()` that the F2 harness runs on start.

| Tier | Radius | Ratio | Mass *(derived)* | Color | Label |
|---:|---:|---:|---:|---|---|
| 1 | 26 | — | 1.00 | `#E74C3C` red | light |
| 2 | 30 | 1.154 | 1.24 | `#E67E22` orange | light |
| 3 | 34 | 1.133 | 1.50 | `#F1C40F` yellow | dark |
| 4 | 39 | 1.147 | 1.84 | `#7ED321` lime | dark |
| 5 | 44 | 1.128 | 2.20 | `#2ECC71` green | dark |
| 6 | 50 | 1.136 | 2.67 | `#1ABC9C` teal | light |
| 7 | 57 | 1.140 | 3.25 | `#3498DB` blue | light |
| 8 | 65 | 1.140 | 3.95 | `#5B6ABF` indigo | light |
| 9 | 74 | 1.138 | 4.80 | `#9B59B6` purple | light |
| 10 | 84 | 1.135 | 5.81 | `#E84393` magenta | light |
| 11 | 96 | 1.143 | 7.09 | `#8D6E63` brown | light |
| 12 | 110 | 1.146 | 8.70 | `#ECF0F1` white | dark |

- Radius growth ≈ ×1.14 per tier — visibly larger, never a jump.
- **Mass is derived, never authored:** `(radius / 26) ^ 1.5`, computed as a property on
  `TierData`. Changing a radius can therefore never leave a stale mass behind. The mass column
  above is the computed result, shown for reference only. Deliberately **sub-quadratic**: large
  pieces are heavy and hard to shove, but a well-aimed tier-1 can still move a tier-10. Quadratic
  mass made big pieces feel like immovable scenery in similar games; do not "fix" this to be
  physically correct. (How *much* a tier-1 actually moves a tier-8 is measured in §6, and it is a
  lot — see the open question in §16.)
- Every placeholder piece draws: filled circle, darker outline (`darkened(0.35)`, width scaling
  with radius from 3px to 9px so it is not a hairline on the big tiers), and a centred label. The
  label is **not** hardcoded to the tier number any more — it comes from the active piece set
  (§5.1). The classic set authors "1" through "12", so the original look is data like any other
  set rather than a special case in the renderer.
- **Label colour is computed, not listed:** fills with luminance above 0.6 take the dark label,
  everything else the light one, so it stays correct if a colour ever changes. That currently
  makes tiers 3, 4, 5 and 12 dark-labelled. A set may opt out (`label_tinted = false`), which
  emoji sets must — see §5.2.

### 5.1 Piece sets

A **piece set** is what a tier's twelve circles *look like*: the text on them, optional colour
overrides, and eventually their textures. Sets are the unlockable the shop will sell once there is
a currency to sell them for (§16 q10).

The split is the whole point:

| | Lives on | Authored | Overridable by a set |
|---|---|---|---|
| tier number, radius, mass | `TierData` in `tiers.tres` | once | **never** |
| text, colour, texture | `PieceLabel` in a set's `.tres` | per set | yes |

**No set can change radius or mass.** That is not an oversight to be tidied up later — it is the
reason a paid set can never be worth buying for an advantage. Anything that would alter how the
game plays belongs in `tiers.tres`, which sets cannot reach.

```gdscript
# res://scripts/data/piece_label.gd — one tier's face
@export var tier: int
@export var text: String        # "7", or "🍉". Empty draws nothing.
@export var color: Color        # transparent = use the tier's colour from tiers.tres
@export var texture: Texture2D  # null through the placeholder phase

# res://scripts/data/piece_set.gd — twelve of them, plus what the shop needs
@export var id: StringName      # written to the save; renaming one orphans a player's choice
@export var display_name: String
@export var price: int          # 0 = free, and free means owned by everyone
@export var label_scale: float  # multiplies PIECE_LABEL_SIZE_RATIO for this set alone
@export var label_tinted: bool  # see §5.2
@export var labels: Array[PieceLabel]
```

`color` is an *override*, not a value. Left transparent it defers to the tier's own colour, so a
set that only changes text authors no colours at all — and the tier hues that carry identity under
pillar 4 survive by default rather than by every set author remembering to preserve them.

Sets ship in `res://resources/piece_sets.tres`, a `PieceSetRegistry` holding an explicit list.
Explicit rather than a `DirAccess` scan of the sets folder: directory listing over `res://` is not
dependable in an exported build, and an unlockable that silently fails to appear on a device is a
far worse bug than one that fails to appear in the editor.

**Two fallbacks, so a piece is never faceless.** An id the build does not have resolves to
`classic` (a set renamed, or a save from a later version). A set missing one tier falls back to
that tier's number for that tier alone. `PieceSetRegistry.validate()` catches both at harness time.

`label_scale` exists because a digit and an emoji want different sizes in the same circle: emoji
are square and read small at the ratio that suits a digit. Classic sits at 1.0, the fruit set at
1.45. It multiplies the global ratio rather than replacing it, so retuning `PIECE_LABEL_SIZE_RATIO`
still moves every set together.

Shipping now: **classic** (the tier numbers) and **fruit** (a worked emoji example, no colour
overrides). Both are free, because the currency does not exist yet.

### 5.2 The label font chain

`ThemeDB.fallback_font` is Godot's bundled monochrome Noto Sans and has **no emoji glyphs at all**,
so an emoji label drawn with it is tofu. `PieceFont.label_font()` builds a chain once:

```
base        ThemeDB.fallback_font    digits and latin — and the metrics labels are centred on
fallback 1  SystemFont(              the platform's own emoji font, by name:
              "Apple Color Emoji",     iOS / macOS
              "Noto Color Emoji",      Android / Linux
              "Segoe UI Emoji",        Windows
              "Twemoji Mozilla")
fallback 2  res://resources/fonts/NotoColorEmoji.ttf   bundled, ~10MB, CBDT bitmap build
```

Godot resolves missing glyphs down the chain one glyph at a time, so a mixed label works.

Three things about this ordering are deliberate:

- **Platform emoji before the bundled font.** It costs nothing to ship and matches what the player
  already sees in every other app on their phone. The bundle is the safety net, not the default.
- **The text font is the base, not an emoji font.** `Font.get_ascent()` and `get_descent()` report
  the *base* font's metrics, and `PieceRender` centres labels on those. An emoji font's ascent is
  nothing like Noto Sans's, so putting one first would silently shift every digit off centre.
- **A `FontVariation` wraps the base rather than mutating it.** `ThemeDB.fallback_font` is shared
  with every `Label` in the game; setting fallbacks on it directly would reach far beyond pieces.

MSDF stays off throughout: a colour bitmap glyph cannot be expressed as a distance field, and
turning it on strips the colour out of every emoji.

`label_tinted` is the other emoji consequence. `draw_string` multiplies its modulate into colour
bitmap glyphs, so the computed dark/light label colour would *recolour* an emoji rather than leave
it as authored. Digit sets keep the tint; emoji sets turn it off and draw white.

**The risk to keep testing:** `has_char()` passing in the editor on one desktop proves nothing
about an Android or iOS build. Run `piece_set_test.tscn` on a real device before authoring a set.

## 6. Physics model

The whole feel of the game is in this section. Get it right before building anything on top.

```
Project settings:
  physics/2d/default_gravity        = 0
  physics/common/physics_ticks_per_second = 60
```

**Pieces** — `RigidBody2D`, `CircleShape2D`:

| Property | Value | Why |
|---|---|---|
| `gravity_scale` | 0 | Top-down table |
| `linear_damp` | 0.78, mode `REPLACE` | Viscous drag term — see **Table friction** below. `REPLACE` so Tuning is authoritative and this does not combine with the project default |
| Coulomb friction | 258 px/s², applied in `_integrate_forces` | Constant-deceleration term — see below |
| `angular_damp` | 3.0, mode `REPLACE` | Spin bleeds off fast; rotation is cosmetic |
| `physics_material.friction` | 0.2 | Light piece-on-piece grab |
| `physics_material.bounce` | 0.35 | Pieces knock each other around without ping-ponging |
| `WALL_RESTITUTION` | 0.95 | **Not a body property.** The bounce the engine actually applies to a piece-wall contact: Godot combines the two materials *additively*, so it is `PIECE_BOUNCE + WALL_BOUNCE`, not `WALL_BOUNCE`. Measured at 0.942, the rest lost to contact friction. The aim guide depends on it; the F4 harness re-measures it every run and fails if it drifts |
| `continuous_cd` | `CCD_MODE_CAST_SHAPE` **while in flight**, `DISABLED` once resting | Prevents a fast shot tunnelling through a wall or a small piece |
| `contact_monitor` | `true`, `max_contacts_reported = 6` | Required for merge detection |
| `can_sleep` | `true` | Sleeping is the definition of "at rest" — see §9 |
| Speed clamp | 3000 px/s, applied in `_integrate_forces` | Hard ceiling; merges can otherwise compound velocity |

### Table friction — two terms, not one

Friction is the sum of a **viscous** term (scales with speed, Godot's `linear_damp`) and a
**Coulomb** term (constant deceleration, applied manually):

```
deceleration = PIECE_LINEAR_DAMP * speed + PIECE_FRICTION_DECEL
             = 0.78 * speed + 258 px/s²
```

Every moving piece applies the Coulomb term in `_integrate_forces`, along with the speed clamp:

```gdscript
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var velocity := state.linear_velocity
	var speed := velocity.length()

	if speed > 0.0:
		var drop := Tuning.PIECE_FRICTION_DECEL * state.step
		if drop >= speed:
			velocity = Vector2.ZERO
		else:
			velocity -= velocity / speed * drop

	if velocity.length() > Tuning.PIECE_MAX_SPEED:
		velocity = velocity.normalized() * Tuning.PIECE_MAX_SPEED

	state.linear_velocity = velocity
```

Why both, when the original spec used `linear_damp` alone? Under pure viscous damping, coast
distance is exactly proportional to launch speed, so the 5.2× speed range gives a 5.2× distance
range — but the targets below ask for about 9×. No single damping value satisfies both ends; F1
measured `linear_damp = 1.6` alone landing a max-power shot at y≈351, pinned against the top
wall instead of returning to mid-table. Adding the Coulomb term decouples the two, and it is also
the physically right model for an object sliding on a table — which is the game's whole conceit.
It has a second benefit the loss condition depends on: constant deceleration reaches zero in
finite time, so pieces come to a genuine dead stop rather than an asymptotic crawl.

**Walls** — four separate `StaticBody2D`s (so a future feature can make one special),
`friction 0.1`, `bounce 0.6`. Bouncier than the pieces so bank shots stay lively.

Colliders are **240 px deep** (`WALL_COLLIDER_DEPTH`) even though the walls are only drawn 40 px
thick, with the extra depth running off-screen. At 60 Hz a full-power piece advances ~43 px per
step and was measured sinking 35 px into a wall before the solver answers — inside a 40 px
collider that is a tunnelling risk. The depth costs nothing.

**Collision layers** (name them in project settings):

| Bit | Layer | Collides with |
|---|---|---|
| 1 | `pieces` | pieces, walls |
| 2 | `walls` | pieces |
| 3 | `danger_zone` | *(Area2D, monitors pieces only)* |
| 4 | `ui_touch` | *(no physics)* |

**Tuning targets, and what F1 measured.** `scenes/game/table_test.tscn` fires a tier-1 puck
straight up the table at five power levels and prints these numbers; re-run it after touching any
friction constant.

| Power | Speed | Path | Time to rest | Bounces | Rest y |
|---:|---:|---:|---:|---:|---:|
| 0.00 | 500 | 248 px | 1.08 s | 0 | 1532 |
| 0.25 | 926 | 616 px | 1.62 s | 0 | 1164 |
| 0.50 | 1446 | 1129 px | 2.05 s | 0 | 650 |
| 0.75 | 2008 | 1719 px | 2.38 s | 1 | 497 |
| 1.00 | 2600 | 2348 px | 2.65 s | 1 | 1111 |

- ✅ Minimum-power shot travels ~250 px before stopping — **248 px**.
- ✅ Maximum-power shot crosses the full table height and returns roughly to mid-table — reaches
  the top wall, bounces once, rests at **y 1111** against a mid-table of 1060.
- ✅ Everything settles within ~3s — worst case **2.65 s**.
- ❌ A tier-1 at full power moves a resting tier-8 by ~30–60 px — **measured at F2 as 412 px
  across the table and 581 px point blank.** The impact kicks the tier-8 up to ~700–870 px/s, and
  it then coasts under the same friction as everything else. The 30–60 px figure was written
  before there was anything to simulate and is not reachable with this mass model — even
  quadratic mass only brings it to roughly 160 px. Decide at F12 whether the target or the model
  is what should change; see §16.

## 7. Input and firing

### The gesture

One continuous gesture handles **both** placement and aiming. This is the fiddliest part of the
design; implement it exactly.

```
 1. TOUCH DOWN anywhere on screen
      → launcher x snaps to touch.x (clamped to LAUNCHER_X_RANGE)
      → state = PLACING

 2. DRAG while total displacement < AIM_DEADZONE (24 px)
      → launcher x keeps following touch.x   (fine positioning)
      → state stays PLACING

 3. DRAG past AIM_DEADZONE
      → launcher x LOCKS at its current value
      → state = AIMING
      → drag     = touch_start - touch_pos               # opposite the drag
      → shot_dir = drag.normalized()
      → power    = clamp(|drag| - AIM_DEADZONE, 0, DRAG_MAX) / DRAG_MAX

 4. RELEASE while AIMING
      → fire, state = COOLDOWN (0.4 s), then reload next piece
    RELEASE while PLACING (never crossed deadzone)
      → nothing fires; the tap just repositioned the launcher
    Drag back inside the deadzone before releasing
      → cancels the shot, returns to PLACING
```

Both direction and power are measured from **`touch_start`** — where the finger first landed —
with the deadzone subtracted from the distance. An earlier draft measured them from the point
where the drag crossed the deadzone, so that power would start at zero rather than jumping. It
does achieve that, but it makes direction violently unstable: right after crossing, the vector
from the crossing point to the finger is near zero, so the aim spins. Subtracting the deadzone
from a `touch_start`-based distance gets the same zero start with a direction vector that is
never shorter than 24 px. Full power therefore needs a drag of `AIM_DEADZONE + DRAG_MAX` = 344 px.

**Holstering.** The loaded piece is a real `Piece` living in the world from the moment it is
loaded, not a preview — the launcher just keeps its position synced and holsters it: frozen, and
on no collision layer, so sliding the launcher along the lane cannot bulldoze whatever is already
resting there. Freeze with `FREEZE_MODE_STATIC`, never `KINEMATIC`: a kinematic-frozen body
derives a velocity from being moved, and that leaks the last slide into the shot as sideways
drift. `Piece.launch()` also zeroes velocity before applying the impulse, so a shot always starts
from rest.

| Constant | Value |
|---|---|
| `AIM_DEADZONE` | 24 px |
| `DRAG_MAX` | 320 px (full power) |
| `SPEED_MIN` / `SPEED_MAX` | 500 / 2600 px/s |
| `SHOT_COOLDOWN` | 0.4 s |
| Power curve | `speed = lerp(SPEED_MIN, SPEED_MAX, pow(power, 1.15))` — slightly eased so low power is controllable |

Fire with `apply_central_impulse(shot_dir * speed * mass)`.

Because the finger anchors below and behind the piece, it never covers the target. Aim gestures
that start on top of the HUD are ignored; everything else on screen is aimable surface.

**Desktop testing:** set `input_devices/pointing/emulate_touch_from_mouse = true` so the whole
gesture works with a mouse in the editor.

### Aim guide

Rendered while `state == AIMING`, as a `Node2D` with `_draw()`:

- Dotted polyline from the piece centre along `shot_dir`. Dots are spaced along the *whole*
  polyline rather than per segment, so the rhythm carries through the bounce instead of
  restarting at the corner. The post-bounce segment draws dimmer — it is a prediction of a
  prediction.
- Total length = `lerp(200, 900, power)` — the line itself communicates power. It is deliberately
  **not** the full trajectory: a full-power shot travels ~2350 px, far past the end of the guide.
- **Sweep the piece's own circle** (`cast_motion` + `get_rest_info`), not a ray. A ray from the
  centre clips corners and puts the bounce on the wall face instead of a radius short of it.
  `cast_motion`'s safe fraction backs off a couple of px so the shapes never overlap; that is the
  tolerance to expect when comparing predictions to wall planes.
- On hitting a **wall**, reflect once and continue with the remaining length. On hitting a
  **piece**, stop the line there and draw a faint ring on the piece that would be struck.
- **Exactly one bounce.** Do not extend to two; it makes the game solvable rather than skilful.
- **Model restitution, not a mirror.** Reflect only the normal component of the direction and
  scale it by `WALL_RESTITUTION`, leaving the tangential component alone — which is what the
  engine does. See the note on `WALL_RESTITUTION` in §6: it is *not* `WALL_BOUNCE`.
- Also draw a small power arc near the launcher — a ring around the held piece that closes to a
  full turn at power 1.0, ramping teal → coral.

## 8. Merge system

The core rule: **two touching bodies of the same tier fuse into one body of the next tier.**

### Detection and resolution

Physics callbacks cannot free bodies safely, so merges are queued and resolved between steps.

The resolver **watches the pieces container** — connecting to `child_entered_tree` and wiring
each new piece's `body_entered` — rather than being handed pieces by whoever made them. The
launcher and the spawn queue therefore never need to know it exists.

```gdscript
# merge_resolver.gd — inside the contact callback: claim, never act
if second != null and second.tier == piece.tier and piece.can_merge() and second.can_merge():
    piece.merging = true                    # claimed here, inside the callback, so that
    second.merging = true                   # the mirrored report finds them spoken for
    _queue.append([piece, second])

# merge_resolver.gd — _physics_process, outside any physics callback
var pending := _queue
_queue = []
for pair in pending:
    if is_instance_valid(pair[0]) and is_instance_valid(pair[1]):
        _resolve(pair[0], pair[1])
```

Claiming both pieces *inside* the callback is what makes the guarantees below hold. Every contact
is reported twice, once by each body, and the second report must find the pair already taken; a
third piece touching either of them in the same frame must find the same.

`resolve(a, b)`:

1. `mid = (a.position + b.position) * 0.5`
2. `v = (a.linear_velocity + b.linear_velocity) * 0.5 * MERGE_MOMENTUM_SCALE` — `MERGE_MOMENTUM_SCALE = 0.85`.
   Note this is *not* conservation of momentum: the merged mass is less than the sum of parts
   (§5), so true conservation would make merged pieces *accelerate* and the board would go
   berserk. This averaged form is the intended, tuned behaviour.
3. `despawn()` both — which clears their collision layers *before* `queue_free`, not merely
   queueing them — then spawn tier `n+1` at `mid` with velocity `v`. Clearing collision matters:
   `queue_free` does not take effect until the end of the frame, so a body on its way out would
   otherwise still be solid and would shove the piece that just replaced it.
4. New piece gets `merge_cooldown = 1` physics frame — it cannot merge again until the next tick.
   This prevents same-frame cascades while still allowing chains on subsequent ticks.
5. Emit `merged(tier, position, chain_depth)` — or `annihilated(position, chain_depth)` at the
   top of the chain — then increment chain depth. The resolver does not score; F7 listens.

### Guarantees the implementation must hold

- **Never double-resolve a pair.** Claiming both bodies with `merging` inside the contact
  callback is sufficient on its own; no separate de-duplication is needed. Three same-tier pieces
  touching in one frame must produce exactly one merge, with the third left untouched (it will
  merge next frame if still in contact).
- **No orphaned flags.** If a queued piece is freed for any other reason, drop the pair.
- **Spawn overlap is acceptable.** The larger piece may briefly overlap a neighbour; physics
  resolves it within a frame or two. Do not add push-out logic unless testing shows jitter.

### Tier 12

Two tier-12s merging **both despawn**, award `TIER12_BONUS = 2000` (× chain multiplier), and play
the biggest available effect. Nothing spawns in their place. This is the only way to remove mass
from the table, so it is the real pressure valve — treat it as a designed reward, not an edge case.

### Chains and combo

`chain_depth` is per **shot**. It resets to 0 when a new piece is fired, not on a timer — a shot
that ricochets and merges four seconds later still counts toward that shot's chain.

## 9. Spawn queue and loss condition

### Spawn queue

Two-slot queue: **current** (sitting on the launcher) and **next** (shown in the HUD). On fire, next
becomes current and a new next is drawn.

Weighted random over tiers 1–5:

| Tier | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Weight | 30 | 25 | 20 | 15 | 10 |

Use a seeded `RandomNumberGenerator` stored on the run (makes bugs reproducible and leaves the door
open for a daily-seed mode). `SpawnQueue.run_seed` records the seed actually used, rolled or given.

**The contract:** `peek_next()` returns exactly what the following `take()` will hand over. The
HUD shows `peek_next()`, so the player is promised the piece they can see coming — that equality
is the whole point of the class, and the F6 harness fires ten real shots to confirm it holds.

Only the **next** slot is filled at `start()`, not both. Nothing is "current" until the launcher
asks for a piece, which it does on the first frame. Prefilling both puts the queue a slot ahead
of itself, and the HUD then advertises the piece *after* the one that actually loads next — which
is exactly the bug F6 hit before this was pinned down.

```
start()   next=A                      HUD: —
take()    current=A  next=B  -> A     HUD: B     launcher holds A
take()    current=B  next=C  -> B     HUD: C     launcher holds B, as advertised
```

### Loss condition

An `Area2D` spans the launch lane (y 1660 → 1860, full playfield width), monitoring the `pieces`
layer.

```
For each piece overlapping the danger zone:
    if piece.is_sleeping() or piece.linear_velocity.length() < REST_SPEED (30 px/s):
        piece.danger_timer += delta
        if piece.danger_timer > DANGER_GRACE (2.0 s):  → GAME OVER
    else:
        piece.danger_timer = 0
```

- Pieces merely passing through the lane at speed are fine. Only *settling* there kills you.
- From 1.0s onward the piece and the danger line pulse red — the player gets a full second of
  warning and can still shoot it out of the lane. A piece rescued in time forgets it was ever in
  trouble: its clock resets and its tint clears.
- The pulse is an oscillation, not a steady tint. A steady red reads as a colour change; the
  throb is what says *act now*.
- **Frozen pieces are skipped**, which is what exempts the piece on the launcher without anyone
  having to be told about it: a holstered piece is frozen and on no collision layer. The same
  rule keeps the zone quiet once a run has ended.
- On game over: freeze physics, show the overlay (§11), commit the score (§13).

**Pausing and ending a run are different things.** Pausing genuinely pauses the tree, and the
pause overlay runs `WHEN_PAUSED` so its buttons still work. Ending a run does not:
`Game.end_run()` calls `freeze_in_place()` on each piece The board goes still while the HUD, the score popups and
F9's game-over overlay all stay alive over it — and nothing has to fight process modes.

## 10. Scoring

```
merge into tier N   →  base = N * N * 10
tier 12 annihilate  →  base = 2000

multiplier by chain depth within the current shot:
    depth 0 → ×1.0    depth 1 → ×1.5    depth 2 → ×2.0
    depth 3 → ×2.5    depth 4+ → ×3.0 (cap)

points = int(base * multiplier)
```

Reference values: tier 2 = 40, tier 5 = 250, tier 8 = 640, tier 12 = 1440, tier-12 pop = 2000.
A clean 4-merge chain is worth roughly as much as seven isolated merges — the multiplier is the
main lever on how aggressive the game feels, so expect to tune it.

HUD shows the running score. Each merge floats its point value at the merge position; a chain of 2+
also shows the multiplier ("×2.0") and briefly punches the score readout.

Also tracked per run, for the game-over screen: highest tier reached, total merges, longest chain,
shots fired.

## 11. Screens and flow

```
        ┌──────────┐   Play   ┌──────────┐  loss  ┌───────────┐
        │  MAIN    │ ───────► │   GAME   │ ─────► │ GAME OVER │
        │  MENU    │ ◄─────── │          │ ◄───── │  overlay  │
        └──────────┘  Menu    └──────────┘ Retry  └───────────┘
```

**Main menu** — title, big Play button, best score, a top-10 list, a one-screen "How to play"
(three lines: place, drag back, release). No settings in v1.

**Game** — HUD band at the top: score (left), best (right), next-piece swatch showing the tier
colour and number. Everything below is playfield. A small pause button top-right (pause → resume /
quit to menu) is in scope; it is the only way out mid-run. *Built at F7 except the pause button,
which lands with the rest of the menus at F9.*

Restarting a run is not just clearing the table: the launcher has to let go of its held piece
before that piece is freed, and the merge resolver's chain depth has to reset, or the new run
opens scoring at the old run's multiplier. `Game.start_run()` does all three in order.

**Game over** — dimmed overlay over the frozen board: final score, "New best!" when applicable,
highest tier reached, longest chain, then Retry and Menu. **There is no tier 0:** a run that ended
without a single merge never reached a tier, so both here and in the menu's top-10 list it reads
as an em dash rather than a rung that does not exist. `Hud.format_tier()` owns that rule for both
screens. Retry restarts in place without touching
the menu scene.

## 12. Build roadmap

Build in order. Each feature is one session's worth of work and ends in something runnable. Tick
the box and note anything you changed when you finish one.

- [x] **F0 — Project configuration & scaffolding** *(done)*
  Portrait 1080×1920, `canvas_items` / `expand`, `default_gravity = 0`, orientation portrait,
  mouse→touch emulation on, collision layer names, directory skeleton (§14), `tuning.gd` with every
  constant from this doc, empty `main.tscn` scene switcher.
  *Done when:* the project runs and shows an empty portrait viewport at the right aspect on desktop.
  *Notes:* Verified in a windowed run — viewport reports exactly 1080×1920, Forward Mobile renderer,
  gravity 0, layer names and all `Tuning` constants resolving. Removed the leftover
  `3d/physics_engine="Jolt Physics"` setting (dead config for a 2D game). Only the `Tuning` autoload
  is registered so far; `GameState` and `SaveManager` get registered by F7 and F10 respectively.
  Nothing was tuned — every value still matches this document.

- [x] **F1 — Table** *(done)*
  `table.tscn`: background, four wall `StaticBody2D`s, dashed danger line, launch-lane tint.
  *Done when:* a manually placed `RigidBody2D` shot in with a script impulse bounces off all four
  walls and coasts to a stop in roughly the times given in §6.
  *Notes:* Verified with `scenes/game/table_test.tscn` — full-power shots at each of the four walls
  all register contact, rebound, and come to rest inside the playfield. Coast measurements are in
  §6 and hit every target. **Two constants changed from the original spec, both documented in §6:**
  friction is now a two-term model (`linear_damp` 1.6 → 0.78 plus a 258 px/s² Coulomb term),
  because no single damping value could satisfy both the min- and max-power distance targets; and
  `WALL_COLLIDER_DEPTH` (240 px) was added after measuring a full-power piece sinking 35 px into
  a 40 px wall. To revert the friction change, set `PIECE_FRICTION_DECEL = 0.0` and
  `PIECE_LINEAR_DAMP = 1.6`. Also added the §4.1 palette, which the doc had not specified.

- [x] **F2 — Tier data & piece scene** *(done)*
  `TierData` resource + `tiers.tres` populated from §5. `piece.tscn` with `_draw()` placeholder
  rendering (fill, outline, number) and a `setup(tier)` that applies radius, mass, colour, damping.
  *Done when:* a debug key spawns any tier at the cursor with correct size, colour, and mass.
  *Notes:* Verified with `scenes/game/piece_test.tscn` — click spawns the selected tier at the
  cursor, `A` lays out all twelve for comparison. `TierSet.validate()` passes: twelve tiers, radii
  strictly increasing. **Mass is now derived from radius rather than authored**, which corrected
  small drifts in the §5 table (tier 12 was listed at 8.81, is actually 8.70). **Label colour is
  now computed from luminance** rather than a hardcoded list, which also makes tiers 4 and 5 dark.
  The outline scales with radius (3–9px) instead of a flat 3px, which was a hairline on tier 12.
  Closed §6's open tier-1-into-tier-8 check — the result badly misses the target, see §16 q6.

- [x] **F3 — Launcher & firing** *(done)*
  `launcher.gd` implementing the full §7 state machine. No merging, no aim guide yet.
  *Done when:* the place → drag → release → cooldown loop works end to end with a mouse, the
  deadzone lock feels right, and cancel-by-dragging-back works.
  *Notes:* `scenes/game/launcher_test.tscn` drives the whole gesture with synthetic touch events
  and checks all 23 transitions — placement, deadzone lock, aim direction and power, cancel,
  fire, cooldown lockout, reload, tap-does-not-fire, and lane clamping. **Run it windowed, not
  headless:** synthetic touches are in screen coordinates, and headless gives a square viewport
  whose stretch transform skews them; the harness detects this and skips rather than reporting
  false failures. **One real bug found and fixed:** holstered pieces were frozen `KINEMATIC`, so
  a piece inherited a velocity from the launcher sliding underneath it and every shot picked up
  sideways drift — see the holstering note in §7. Power is now measured from `touch_start` with
  the deadzone subtracted rather than from the deadzone crossing point, also explained in §7.
  The launcher does not own the piece supply: it emits `needs_piece` and F6 will answer.

- [x] **F4 — Aim guide** *(done)*
  Dotted trajectory, one wall reflection, first-contact ring, power indicator.
  *Done when:* the predicted line matches where the piece actually goes on a bank shot.
  *Notes:* `aim_guide.gd`, living inside `launcher.tscn` and driven by the launcher. Verified in
  `launcher_test.tscn`, which now covers F3 and F4: on a full-power bank shot the predicted
  bounce lands **3.7 px** from the real one and the predicted rebound direction matches to
  **dot 0.9965**. **The important find: `WALL_BOUNCE` is not the bounce the engine applies.**
  Godot combines the piece's and the wall's materials additively, so the real restitution is 0.95,
  not 0.6 — predicting with 0.6 gave a rebound 15° off. The harness measures it live (0.942) and
  fails if `WALL_RESTITUTION` drifts from it. Space queries run on the physics step, one frame
  behind the input that moved the aim, which also throttles them as §15 suggests.
  Harness flake worth knowing about: synthetic input is buffered and delivered on the *next*
  iteration, so checks must wait two process frames, and the aim poll waits for a prediction
  rather than a fixed frame count.

- [x] **F5 — Merge system** *(done)*
  `MergeResolver`, contact detection, the §8 guarantees, tier-12 annihilation.
  *Done when:* three same-tier pieces in contact produce exactly one merge per frame with no
  crashes, no double-scores, and no leaked bodies; chains visibly occur from a single shot.
  *Notes:* `scenes/game/merge_test.tscn` covers all of it in 22 checks: a pair merging once at
  the midpoint, three touching pieces producing exactly one merge with the odd one out untouched,
  different tiers never merging, two tier-12s annihilating with nothing produced, one shot
  chaining two merges with chain depth counting 0 then 1, and a 16-piece cascade leaving no body
  queued for deletion and no orphans in the container. The resolver watches the pieces container
  instead of being handed pieces, so the launcher needed no changes. `Piece.despawn()` clears
  collision layers before `queue_free` — see step 3 of §8; without that the dying pieces shove
  their own replacement. Scoring is not here: F5 emits `merged` / `annihilated` and F7 listens.

- [x] **F6 — Spawn queue & next preview** *(done)*
  Weighted draw, two-slot queue, HUD next swatch.
  *Done when:* the preview always matches what actually loads after the shot.
  *Notes:* `scenes/game/spawn_test.tscn` wires the queue to the launcher the way the play scene
  will, and checks: the pool never leaves tiers 1–5 over 5000 draws; the observed distribution
  over 20000 draws sits within 0.6% of the configured weights; a seed replays a run exactly and a
  different seed does not; and across ten real fired shots the swatch always advertised the piece
  that then loaded. **The off-by-one this caught is worth remembering** — prefilling both slots
  made the HUD show the piece *after* the one that loads next; see the corrected contract in §9.
  Also extracted `PieceRender`, so the HUD swatch and the piece on the table are the same drawing
  code and cannot drift apart — that is also the single place the art swap will touch.

- [x] **F7 — Scoring, combos & HUD** *(done)*
  Score model, chain multiplier, floating point popups, score/best readouts.
  *Done when:* a hand-verified chain produces exactly the arithmetic in §10.
  *Notes:* **`scenes/game/game.tscn` was built here** — the HUD needed somewhere to live, so the
  play scene now assembles table, pieces, resolver, queue, launcher, popups and HUD. `game.gd` is
  wiring only; every rule stays in the part that owns it. `GameState` is registered as the second
  autoload and owns the score model as static functions. `scenes/game/score_test.tscn` embeds the
  real play scene and checks §10's reference values, the multiplier table and its cap, the worked
  example (90 + 240 + 500 = 830) and then a chain played through the real scene for 40 + 135 =
  175. Popups are drawn by one node rather than instantiated per merge, as §15 asks.
  **Three restart bugs found and fixed, all of which F9's Retry would have hit:** the launcher
  went on holding a piece the restart had freed, so the lane came up empty; the resolver's chain
  depth survived a restart, so the first merge of a new run scored at the last run's multiplier;
  and popups were drawn on top of the piece that produced them. `Launcher.reset()` exists now and
  `Game.start_run()` is order-sensitive — see the comment there. Best score is in `GameState` but
  reads 0 until F10 loads it.

- [x] **F8 — Danger zone & game over** *(done)*
  Area2D, rest detection, grace timer, warning pulse, freeze + end-of-run state.
  *Done when:* a piece rolling through the lane is safe, a piece parked there ends the run after
  2s with a full second of visible warning.
  *Notes:* `scenes/game/danger_test.tscn`, 18 checks. Measured: **warning at 1.03s, run over at
  2.03s** — a piece crossing the lane at speed never starts the clock, a piece resting above the
  line never warns, a piece knocked clear in time has its clock and its tint reset, and the
  holstered piece never counts. The zone polls `get_overlapping_bodies()` each physics step rather
  than tracking enter/exit, which at 40 bodies is cheap and has no bookkeeping to get wrong.
  Pieces are frozen individually at the end of a run rather than pausing the tree — see §9.
  The game-over overlay and committing the score are F9 and F10; `Game.run_ended` is the hook.

- [x] **F9 — Menus** *(done)*
  Main menu, pause, game-over overlay, scene flow from §11.
  *Done when:* menu → game → loss → retry → loss → menu runs cleanly with no leaks between runs.
  *Notes:* `main.tscn` now boots into the menu, so Run Project works. `scenes/game/flow_test.tscn`
  walks the whole loop three times pressing the real buttons — play, lose, retry, pause, resume,
  lose, menu — and measures **0 orphan nodes and 0 node growth** across the last two round trips.
  Retry restarts in place without rebuilding the scene, which the harness asserts. The pause
  overlay really does pause the tree (`process_mode = WHEN_PAUSED` on it), unlike the end of a
  run; `Main.show_menu()` unpauses defensively, since quitting from the pause overlay would
  otherwise hand the menu a paused tree. The top-scores list renders whatever `GameState.top_scores`
  holds and says "No scores yet" while F10 has not filled it.

- [x] **F10 — Local persistence** *(done)*
  `SaveManager`, best score + top 10 + lifetime stats, corrupt/missing-file handling.
  *Done when:* scores survive a full app restart, and a hand-corrupted save file loads as defaults
  instead of crashing.
  *Notes:* `scenes/game/save_test.tscn`, 16 in-process checks plus a **genuine two-process restart
  proof** — `F10_PHASE=write` writes in one launch of the engine and `F10_PHASE=read` verifies it
  in a fresh one, so the criterion is met literally rather than by calling `load()` again.
  Corruption cases covered: missing file, garbage, a truncated file (exactly what an interrupted
  write used to look like), a version from the future, and a well-formed file whose every field is
  the wrong type. All load as defaults, none crash. `flow_test` now also confirms a played run
  reaches the save and appears on the menu, and both harnesses retarget `SaveManager` at a scratch
  file so testing cannot wipe real scores. `GameState`'s best and table became read-only views on
  `SaveManager` rather than copies, and `Game` now takes `is_best` from `GameState.run_ended`
  instead of recomputing it — two answers to one question is a bug waiting to happen.

- [x] **F11 — Juice pass** *(done, partial by choice)*
  Cosmetic only — must not touch physics or scoring.

  Built, on the project owner's selection:
  - **Merge flash** — a merged piece flares white for ~0.11s.
  - **Spawn pop** — a merged piece grows in from 0.62 with a slight swell past full size. The
    *drawn* radius only; the collision circle is never scaled, so it is invisible to the physics.
  - **Wall-hit spark** — an arc struck against the wall at the contact point, sized and lit by
    impact speed, ignored below `SPARK_MIN_SPEED` so the walls do not twinkle constantly.
    `Piece.hit_wall` reports the first frame of each contact and carries the *previous* frame's
    speed, because by the time a contact is visible the bounce has already spent it.
  - **Overlay entrances** — game-over and pause fade up with their panel settling. The pause
    tween is set `TWEEN_PAUSE_PROCESS`: the overlay is shown *by* pausing, so a tween that
    respected the pause would never move.

  Deliberately not built, and still available: merge scale-punch on the HUD *(already existed
  from F7)*, screen shake on a tier-12 pop, launcher recoil, aim-guide fade, next-swatch
  transition, reload pop, and the tier-12 annihilation effect — see §16 q9.

  *Verified:* every harness still passes, and the F1 coast measurements come back byte-identical
  to the table in §6 (248 / 616 / 1129 / 1719 / 2348 px). That equality is the proof the pass
  stayed cosmetic; re-run `table_test` after any further juice work and check it again.

- [ ] **F12 — Balance pass**
  Play a lot. Tune damping, power range, mass exponent, spawn weights, multiplier cap, lane height.
  Record before/after values in this doc.

- [x] **F13 — Piece sets** *(done; built ahead of F12 at the project owner's request)*
  Groundwork for unlockable, purchasable piece faces. Cosmetic in full — see §5.1.

  Built:
  - **`PieceLabel` / `PieceSet` / `PieceSetRegistry`**, and `texture` moved off `TierData`. A set
    owns text, colour overrides and art; it can never touch radius or mass, so no set can be worth
    buying for an advantage.
  - **`classic.tres`** authors "1"–"12", so the renderer no longer hardcodes `str(data.tier)`
    anywhere and the original look is data. **`fruit.tres`** is a worked emoji example.
  - **The label font chain** (§5.2): platform emoji first, bundled `NotoColorEmoji.ttf` behind it,
    both hanging off the text font so digit metrics are unchanged.
  - **Persistence**: `selected_set` and `owned_sets` in `save.json` with no version bump (§13),
    reachable through `GameState.active_set` / `owns_set()` / `select_set()` / `unlock_set()`.
  - **`piece_set_test.tscn`**, which validates the registry, both fallbacks, ownership, the save
    round-trip *and* reports per-set whether the font chain actually has each glyph.

  Deliberately not built: the currency itself, a shop, and a set-picker UI. `PieceSet.price` and
  `GameState.unlock_set()` are the seams those plug into — nothing spends anything yet, and every
  shipped set is free, so every set is currently owned.

  *Amended §2 pillar 4 and §3 decision 15*, both of which assumed a single numbered look. Tier
  identity now rests on hue and size rather than the number; the number is one set's content.

  *Not yet verified on a device.* The emoji font chain is the risk — see the last note in §5.2.

**Deferred past v1** (do not build without being asked): audio + haptics, settings screen, themed
art swap replacing the primitives, extra modes, daily seed, achievements, anything online. The
currency, shop and set-picker that F13 leaves seams for are on this list too.

## 13. Save data

Single file, `user://save.json`, written on game over and on clean exit.

```json
{
  "version": 1,
  "best_score": 31480,
  "top_scores": [
    { "score": 31480, "highest_tier": 11, "longest_chain": 5, "timestamp": 1756598400 }
  ],
  "stats": { "games_played": 42, "total_merges": 1893, "tier12_pops": 3 },
  "selected_set": "fruit",
  "owned_sets": ["fruit"]
}
```

Rules: top 10 entries, sorted descending. Write to `user://save.json.tmp` then rename, so an
interrupted write cannot destroy an existing save. Any parse failure, missing key, or unknown
`version` → log a warning and fall back to defaults; never crash and never block play on save I/O.
`SaveManager` is an autoload and is the only thing that touches the filesystem.

Nothing loaded from the file is trusted for its type. JSON hands every number back as a float, and
a corrupt file can hand back anything at all — `top_scores` as a string, `stats` as a number, a
score entry that is not a dictionary. Every field is coerced and clamped on the way in, and
entries that cannot be made sense of are dropped rather than propagated.

Two smaller rules the schema does not show:

- **The best is reconciled against the table.** A file whose `best_score` is behind its own top
  entry is corrected upward on load, so the two can never disagree on screen.
- **If a platform refuses to rename over an existing file**, remove the destination and retry.
  That leaves a hairline window with no save at all, which is still better than never saving.

`GameState.best_score` and `GameState.top_scores` are read-only views onto `SaveManager` rather
than copies — one source, so they cannot drift. `SaveManager.use_path()` retargets the file, which
is how the harnesses avoid destroying a real player's scores.

**Piece sets in the save (§5.1).** `selected_set` is the id the player chose; `owned_sets` lists
only what they *paid* for, since a free set is owned by definition and listing it would just bloat
the file. Both were added after version 1 shipped and **the version was deliberately not bumped**:
`load_game()` discards the entire file on a version mismatch, so bumping would throw away every
existing player's high scores in order to add a cosmetic preference. A file without these keys
simply defaults, which is exactly the behaviour wanted.

`SaveManager` validates the *shape* of these fields and nothing more — a non-string id defaults, a
non-array `owned_sets` empties, duplicates are dropped. Whether an id still exists in this build is
not knowable at this layer; `GameState` resolves that against the registry and falls back to
`classic`. That split is why `SaveManager` still has no idea what a piece set *is*.

## 14. Code layout

```
res://
├── project.godot
├── GAME_DESIGN.md                  ← this file
├── resources/
│   ├── tiers.tres                  ← TierSet, 12 entries — the physics chain
│   ├── piece_sets.tres             ← PieceSetRegistry: every set the build ships
│   ├── sets/
│   │   ├── classic.tres            ← the tier numbers, authored as data
│   │   └── fruit.tres              ← worked emoji example
│   └── fonts/
│       └── NotoColorEmoji.ttf      ← bundled emoji safety net (§5.2)
├── scenes/
│   ├── main.tscn                   ← root; scene switcher
│   ├── game/
│   │   ├── game.tscn               ← play scene root: everything wired together
│   │   ├── score_test.tscn         ← dev harness: the score model, end to end
│   │   ├── danger_test.tscn        ← dev harness: the loss rule
│   │   ├── table.tscn              ← walls, danger line, background
│   │   ├── table_test.tscn         ← dev harness: friction measurements
│   │   ├── piece_test.tscn         ← dev harness: tier sandbox
│   │   ├── piece_set_test.tscn     ← dev harness: piece sets, and the emoji font check
│   │   ├── launcher_test.tscn      ← dev harness: gesture state machine
│   │   ├── merge_test.tscn         ← dev harness: merge rules and chains
│   │   ├── spawn_test.tscn         ← dev harness: queue, weighting, preview
│   │   ├── piece.tscn              ← RigidBody2D
│   │   └── launcher.tscn           ← launcher + aim guide
│   │   ├── flow_test.tscn          ← dev harness: the whole menu/run loop
│   │   └── save_test.tscn          ← dev harness: persistence and corrupt files
│   └── ui/
│       ├── main_menu.tscn
│       ├── hud.tscn                ← score, best, next swatch
│       ├── pause_menu.tscn
│       └── game_over.tscn
└── scripts/
    ├── main.gd                     ← scene switcher; owns the live screen
    ├── config/tuning.gd            ← every constant in this document, and nothing else
    ├── autoload/game_state.gd      ← run lifecycle, score model, run stats, signals,
    │                                  and the active piece set
    ├── autoload/save_manager.gd    ← the only filesystem access
    ├── game/save_test.gd           ← dev harness: schema, corruption, restart
    ├── data/tier_data.gd           ← one tier: radius, colour, derived mass. Gameplay only
    ├── data/tier_set.gd            ← the twelve, with lookup and validation
    ├── data/piece_label.gd         ← one tier's face: text, colour override, texture
    ├── data/piece_set.gd           ← twelve faces + what the shop needs (§5.1)
    ├── data/piece_set_registry.gd  ← every shipped set; lookup, fallbacks, validation
    ├── game/game.gd                ← owns the run, drives MergeResolver
    ├── game/table.gd               ← builds walls and draws the surface from Tuning
    ├── game/table_camera.gd        ← places the play area on any screen shape
    ├── game/table_test.gd          ← dev harness: friction + wall measurements
    ├── game/piece_test.gd          ← dev harness: interactive tier sandbox
    ├── game/piece.gd
    ├── game/launcher.gd            ← input state machine
    ├── game/launcher_test.gd       ← dev harness: synthetic-touch gesture checks
    ├── game/aim_guide.gd
    ├── game/spawn_queue.gd         ← the two-slot supply and its weighted draw
    ├── game/piece_render.gd        ← shared placeholder drawing; the art swap lands here
    ├── game/piece_font.gd          ← the label font chain, emoji included (§5.2)
    ├── game/piece_set_test.gd      ← dev harness: registry, fallbacks, font, ownership
    ├── game/merge_resolver.gd      ← queues same-tier contacts, resolves them off-callback
    ├── game/spawn_test.gd          ← dev harness: queue contract and distribution
    ├── game/merge_test.gd          ← dev harness: §8 guarantees
    ├── game/danger_zone.gd         ← the launch lane's clock and warning
    ├── game/danger_test.gd         ← dev harness: passing through vs settling
    ├── ui/next_preview.gd          ← the HUD's next-piece swatch
    ├── ui/score_popups.gd          ← every floating number, drawn by one node
    ├── ui/hit_sparks.gd            ← wall impact marks, drawn by one node
    ├── ui/main_menu.gd             ← title, play, best, top scores
    ├── ui/pause_menu.gd            ← pauses the tree; the only way out mid-run
    ├── ui/game_over.gd             ← the end-of-run overlay
    ├── game/flow_test.gd           ← dev harness: scene flow and leak counting
    ├── game/score_test.gd          ← dev harness: §10 arithmetic, hand-checked
    └── ui/*.gd
```

**Autoloads:** `Tuning` (constants), `GameState`, `SaveManager`. Nothing else.

**Conventions:** GDScript with static types everywhere (`var x: float`). `snake_case` files and
members, `PascalCase` classes. Communicate upward with signals, downward with direct calls — UI
must never reach into physics nodes. Anything a designer would want to change is a constant in
`tuning.gd` or a field on a resource; no magic numbers in scene scripts.

## 15. Performance & constraints

- Target 60 fps on mid-range hardware with **40 simultaneous pieces**. If it drops, the first levers
  are `max_contacts_reported` and the aim-guide cast frequency (throttle to every other frame),
  not the physics tick rate.
- Merges destroy two bodies and create one, so body count trends down under good play. If a build
  ever exceeds ~60 bodies, that is a signal the balance is wrong, not that the engine is slow.
- Pool merge VFX and score popups; do not instantiate label scenes per merge in the hot path.
- **Fully offline.** No HTTP, no plugins that phone home, no analytics SDKs. Permissions requested:
  none beyond default.

## 16. Open questions for later

Not blockers — decide these during F12 or when the art swap comes up.

1. Does the danger lane need to be *taller* than the launcher's own footprint to be readable? Test
   200 px against 260 px.
2. Should very low-power shots be disallowed (a minimum power floor) to stop players from dribbling
   pieces safely into corners forever?
3. Do walls need slightly different bounce values (e.g. deader side walls) to make bank shots more
   controllable?
4. Should the spawn weights shift toward higher tiers as the score climbs, to accelerate late runs?
5. Placeholder → themed art: keep the tier numbers on the pieces, or rely on silhouette and colour?
   **Partly settled by F13**, in that the number is now one set's content rather than a fixed
   feature — but that makes the question sharper, not softer: a non-numbered set has to carry tier
   identity on hue and size alone. Play a full run on the fruit set before authoring more.
6. **How much should a small piece be able to shove a big one?** F2 measured a full-power tier-1
   sliding a resting tier-8 by 412 px across the table, 581 px point blank — roughly a third of
   the table, against a §6 target of 30–60 px. Options: accept it and rewrite the target (a very
   mobile board suits a sliding-table game, and it keeps big pieces repositionable); raise
   `MASS_EXPONENT` toward 2.0 (gets to ~160 px, still not 60); or cut `PIECE_BOUNCE` so impacts
   transfer less. Needs play, not arithmetic.
7. Tiers 4/5 (lime/green) and 5/6 (green/teal) are close in hue at a glance. The numbers carry the
   distinction today; check whether that holds in motion on a phone. **Raised in priority by
   F13**: on a set with no numbers, hue and radius are the *only* things distinguishing those
   pairs, and the radius gap between adjacent tiers is only ~14%. If the fruit set proves hard to
   read at 4/5/6, the fix is the tier colours in `tiers.tres`, not the sets — every set inherits
   them by default, so widening those hues fixes all of them at once.
8. **A tier-12 annihilation has no effect on the board.** The two pieces simply vanish; only the
   score popup marks it. It is the rarest and most valuable event in the game and currently reads
   as a glitch. Raised at F11 and not selected — worth revisiting.
9. ~~**The table does not centre on a wider viewport.**~~ **Resolved** — `TableCamera`, §4.2.
   It was worse than written here: the common case is a phone *taller* than 9:16, which put the
   dead space below the launch lane and pushed the launcher out of thumb reach. Verified at 9:20,
   9:19.5, 1:2 and 3:4.
10. **What does a piece set cost, and what earns the currency?** F13 built the seams — `price` on
    `PieceSet`, `GameState.unlock_set()`, `owned_sets` in the save — and deliberately nothing
    behind them. Open: whether currency comes from score, from merges, from tier-12 pops, or from
    runs completed; whether prices are flat or escalate; and whether a set can be previewed before
    it is bought. Every shipped set is free until this is answered, so every set is owned.
11. **Emoji rendering is unverified on device.** The §5.2 chain is sound in principle and the
    harness checks it, but `has_char()` passing on a desktop editor says nothing about an Android
    or iOS build. If the platform emoji font fails to resolve *and* the bundled CBDT font is not
    rendered by Godot's FreeType, every piece in an emoji set shows tofu. Must be run on a real
    phone before any set is authored.

## 17. Shipping to devices

`export_presets.cfg` holds an **Android** preset, ready to use. Everything it needs beyond the
repo is machine setup, which has to be done once by hand.

### One-time setup

1. **Godot 4.6, standard build — not .NET.** The project is pure GDScript; the .NET build only
   adds an SDK dependency and APK size. Export templates must match the editor version *exactly*:
   Editor → Manage Export Templates → Download and Install.
2. **JDK 17** — `brew install --cask temurin@17`, or any JDK 17 distribution.
3. **Android SDK** — simplest through Android Studio; command-line tools work too. Needs
   platform-tools, build-tools and a platform (34 or later).
4. **Editor Settings → Export → Android** — point *Java SDK Path* and *Android SDK Path* at the
   two above, and let it generate a debug keystore if you have not got one.

Then Project → Export → Android → Export Project writes `build/android/slide-merge.apk`.

### What the preset does

| Setting | Value | Why |
|---|---|---|
| `package/unique_name` | `com.example.slidemerge` | **Placeholder.** Fine for sideloading; Google Play rejects `com.example.*`, which is deliberate — it forces the decision before a store submission rather than after |
| `package/name` | Slide Merge | Matches the title screen |
| `version/code` / `version/name` | 1 / 0.1 | Bump the code on every build handed out, or devices refuse to update |
| architectures | arm64-v8a + armeabi-v7a | Covers old test devices; drop the 32-bit one to roughly halve the APK |
| `screen/immersive_mode` | true | Full screen |
| permissions | none | Matches the offline pillar in §2 — see the caveat below |
| `exclude_filter` | `*_test.tscn,*_test.gd` | The dev harnesses are not shipped |
| `gradle_build/use_gradle_build` | false | Uses the prebuilt template; no Android build template to install |

### Two things to know before handing out a build

- **A debug export requests INTERNET anyway.** Godot adds that permission to debug builds for the
  remote debugger, regardless of the preset. A tester who checks the permission list will see it.
  For a build that genuinely asks for nothing, export **release** with a self-signed keystore
  (`keytool -genkeypair -alias slidemerge -keyalg RSA -validity 9999 -keystore release.keystore`)
  and set it in the preset. **If you do that, keep `export_presets.cfg` out of the repo** — it
  will then hold the keystore password.
- **The launcher icon is still Godot's default.** `icon.svg` is the stock one the project was
  created with. Testers will see a Godot robot on their home screen.

---

*Last updated: 2026-08-31. Amend this document whenever a locked decision changes, and say so in
the roadmap notes.*
