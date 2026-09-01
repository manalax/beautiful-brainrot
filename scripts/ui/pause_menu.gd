## The pause overlay (GAME_DESIGN.md §11): the only way out of a run.
##
## Runs `WHEN_PAUSED`, because pausing a run really does pause the tree — unlike the end of a run,
## which freezes the pieces instead so the game-over overlay can animate over a still board.
class_name PauseMenu
extends Control

signal resumed
signal quit_pressed

@onready var _resume: Button = $Panel/Resume
@onready var _quit: Button = $Panel/Quit


func _ready() -> void:
	_resume.pressed.connect(_on_resume)
	_quit.pressed.connect(_on_quit)
	hide()


func open() -> void:
	show()
	get_tree().paused = true
	_animate_in()


func close() -> void:
	get_tree().paused = false
	hide()


func _on_resume() -> void:
	close()
	resumed.emit()


func _on_quit() -> void:
	close()
	quit_pressed.emit()


func resume_button() -> Button:
	return _resume


func quit_button() -> Button:
	return _quit


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
