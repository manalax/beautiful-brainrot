## The end-of-run overlay (GAME_DESIGN.md §11), dimmed over the frozen board.
##
## Retry restarts in place rather than going back through the menu — a run should be one tap away
## from the next one.
class_name GameOver
extends Control

signal retry_pressed
signal menu_pressed

@onready var _headline: Label = $Panel/Headline
@onready var _score: Label = $Panel/Score
@onready var _stats: Label = $Panel/Stats
@onready var _retry: Button = $Panel/Retry
@onready var _menu: Button = $Panel/Menu


func _ready() -> void:
	_retry.pressed.connect(retry_pressed.emit)
	_menu.pressed.connect(menu_pressed.emit)
	hide()


func open(score: int, is_best: bool) -> void:
	_headline.text = "NEW BEST" if is_best else "GAME OVER"
	_headline.add_theme_color_override(
		"font_color", Tuning.COLOR_POWER_LOW if is_best else Tuning.COLOR_DANGER_WARNING
	)
	_score.text = Hud.format_number(score)
	_stats.text = "highest %s      longest chain %d\n%d merges      %d shots" % [
		Hud.format_tier(GameState.highest_tier),
		GameState.longest_chain,
		GameState.total_merges,
		GameState.shots_fired,
	]
	show()
	_animate_in()


func retry_button() -> Button:
	return _retry


func menu_button() -> Button:
	return _menu


## Fades the overlay up and lets the panel settle, rather than snapping into place.
##
## The tween is set to run while the tree is paused: the pause overlay is shown by pausing, so a
## tween that respected the pause would never move.
func _animate_in() -> void:
	var panel := $Panel as Control
	modulate.a = 0.0
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * Tuning.OVERLAY_PANEL_FROM

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, Tuning.OVERLAY_FADE_TIME)
	tween.tween_property(panel, "scale", Vector2.ONE, Tuning.OVERLAY_FADE_TIME)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
