## The title screen (GAME_DESIGN.md §11): play, your best, how it works, and the table of scores.
class_name MainMenu
extends Control

signal play_pressed

@onready var _best: Label = $Panel/Best
@onready var _scores: VBoxContainer = $Panel/Scores
@onready var _play: Button = $Panel/Play
@onready var _aim_mode: Button = $Panel/AimMode


func _ready() -> void:
	_play.pressed.connect(play_pressed.emit)
	_aim_mode.pressed.connect(GameState.toggle_invert_aim)
	GameState.invert_aim_changed.connect(_show_aim_mode)
	SaveManager.loaded.connect(refresh)
	refresh()


## Re-reads the score table. Called on entry, so returning from a run shows the new numbers.
func refresh() -> void:
	_best.text = "BEST  %s" % Hud.format_number(GameState.best_score)
	# The pause menu can have changed the aim mode since this screen was last seen (§7).
	_show_aim_mode(GameState.invert_aim)

	for child in _scores.get_children():
		child.queue_free()

	if GameState.top_scores.is_empty():
		_scores.add_child(_row("No scores yet", ""))
		return

	var place := 0
	for entry in GameState.top_scores:
		place += 1
		_scores.add_child(_row(
			"%d.  %s" % [place, Hud.format_number(entry.get("score", 0))],
			Hud.format_tier(int(entry.get("highest_tier", 0)))
		))


func _row(left_text: String, right_text: String) -> Control:
	var row := HBoxContainer.new()

	var left := Label.new()
	left.text = left_text
	left.add_theme_font_size_override("font_size", 34)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var right := Label.new()
	right.text = right_text
	right.add_theme_font_size_override("font_size", 30)
	right.add_theme_color_override("font_color", Tuning.COLOR_HUD_CAPTION)
	row.add_child(right)

	return row


func _show_aim_mode(inverted: bool) -> void:
	_aim_mode.text = GameState.aim_mode_label(inverted)


## For the F9 harness.
func play_button() -> Button:
	return _play


func aim_mode_button() -> Button:
	return _aim_mode
