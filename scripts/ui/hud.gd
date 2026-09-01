## The HUD band across the top (GAME_DESIGN.md §11): score, best, and the next-piece swatch.
##
## Reads nothing on its own — the play scene feeds it. That keeps the physics and the run state
## unaware that a HUD exists.
class_name Hud
extends Control

const PUNCH_SCALE := 1.18
const PUNCH_TIME := 0.18

## The player asked to pause. The play scene decides what that means.
signal pause_pressed

@onready var _score_value: Label = $ScoreValue
@onready var _best_value: Label = $BestValue
@onready var _next: NextPreview = $NextPreview
@onready var _tier_guide: TierGuide = $TierGuide
@onready var _pause_button: Button = $PauseButton

var _punch: Tween = null


func _ready() -> void:
	_pause_button.pressed.connect(pause_pressed.emit)


## Hidden while a run is over — there is nothing to pause, and the overlay owns the screen.
func set_pause_available(available: bool) -> void:
	_pause_button.visible = available


func set_score(value: int) -> void:
	_score_value.text = format_number(value)


func set_best(value: int) -> void:
	_best_value.text = format_number(value)


func show_next(data: TierData) -> void:
	_next.show_tier(data)


## The progression guide. It feeds itself from the active piece set, so nothing calls into it —
## this is here for the harness.
func tier_guide() -> TierGuide:
	return _tier_guide


## The tier the swatch is advertising, or 0. Used by the F7 harness.
func shown_next_tier() -> int:
	return _next.shown_tier()


## A brief squeeze on the score, for merges worth noticing. Chains only, so it stays meaningful.
func punch_score() -> void:
	if _punch != null and _punch.is_valid():
		_punch.kill()
	_score_value.pivot_offset = Vector2(0.0, _score_value.size.y * 0.5)
	_score_value.scale = Vector2.ONE * PUNCH_SCALE
	_punch = create_tween()
	_punch.tween_property(_score_value, "scale", Vector2.ONE, PUNCH_TIME)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 7 -> "tier 7"; anything outside 1..12 -> an em dash. There is no tier 0: a run that ended
## without a single merge never reached a tier, and printing "tier 0" names a rung that does not
## exist. Out-of-range rather than just zero, because a corrupt save can hand back anything.
static func format_tier(tier: int) -> String:
	if tier < 1 or tier > Tuning.MAX_TIER:
		return "—"
	return "tier %d" % tier


## 12480 -> "12,480". Long scores are read at a glance, so the separators earn their keep.
static func format_number(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out
