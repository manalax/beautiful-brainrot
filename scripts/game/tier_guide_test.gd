## Dev harness for the tier progression guide (GAME_DESIGN.md §11): the checks that prove it lays
## twelve cells out evenly, sizes its labels to fit, and follows the active piece set.
##
## Not part of the game. Run `res://scenes/game/tier_guide_test.tscn` directly, windowed — the
## real HUD is instantiated at design width, so the numbers below are the shipping ones.
##
##   TAB / click   cycle the active piece set
extends Node2D

@onready var _hud: Hud = $UI/Hud
@onready var _readout: Label = $UI/Readout

var _guide: TierGuide = null
var _ids: Array[StringName] = []
var _shown := 0


## The checks switch the active set, and selecting one is persisted. Point the save elsewhere
## first, exactly as the F10 harness does, so running this cannot change a real player's choice.
var _real_save_path := ""


func _ready() -> void:
	_guide = _hud.tier_guide()
	_real_save_path = SaveManager.save_path
	SaveManager.use_path("user://tier_guide_test.json")

	_ids = GameState.available_set_ids()

	_check_layout()
	_check_fit()
	_check_follows_set()

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tier_guide_test.json"))
	SaveManager.use_path(_real_save_path)
	print("\nrestored the real save at %s" % _real_save_path)


## Twelve cells, evenly spaced, all inside the control.
func _check_layout() -> void:
	print("\n=== tier guide layout ===")
	print("guide rect: %.0f x %.0f at %s" % [_guide.size.x, _guide.size.y, _guide.position])

	_assert(_guide.size.x > 0.0 and _guide.size.y > 0.0, "the guide has been given a size")
	_assert(_guide.labels().size() == Tuning.MAX_TIER,
		"it lays out %d cells" % Tuning.MAX_TIER)

	var cell := _guide.cell_width()
	var previous := -INF
	var problems := 0
	for tier in range(1, Tuning.MAX_TIER + 1):
		var centre := _guide.cell_centre(tier)
		if centre.x <= previous:
			problems += 1
		if centre.x - cell * 0.5 < -0.01 or centre.x + cell * 0.5 > _guide.size.x + 0.01:
			problems += 1
		previous = centre.x
	_assert(problems == 0, "cells run left to right and all fit inside the guide")
	_assert(is_equal_approx(_guide.cell_centre(1).x, cell * 0.5),
		"the first cell is centred in its own width")


## The widest label has to fit its cell, and nothing may spill into its neighbour.
func _check_fit() -> void:
	print("\n=== label fit ===")

	var font := PieceFont.label_font()
	if font == null:
		printerr("INVALID: no label font")
		return

	var cell := _guide.cell_width()
	for id in _ids:
		GameState.select_set(id)
		var size := _guide.label_size()
		var widest := 0.0
		var widest_text := ""
		for text in _guide.labels():
			if text.is_empty():
				continue
			var ink := PieceRender.label_metrics(font, text).x * size
			if ink > widest:
				widest = ink
				widest_text = text
		print("  %-10s font size %d, widest label \"%s\" at %.1fpx in a %.1fpx cell"
			% [id, size, widest_text, widest, cell])
		_assert(size > 0, "'%s' resolves a usable font size" % id)
		_assert(widest <= cell, "'%s' keeps its widest label inside a cell" % id)


## The guide is a view onto the active set and must move with it.
func _check_follows_set() -> void:
	print("\n=== follows the active set ===")

	if _ids.size() < 2:
		print("  only one set is owned; nothing to switch between")
		return

	var seen := []
	for id in _ids:
		GameState.select_set(id)
		var texts := _guide.labels()
		print("  %-10s %s" % [id, " ".join(texts)])
		_assert(not texts.has(""), "'%s' authors every tier" % id)
		seen.append(texts)

	_assert(seen[0] != seen[1], "switching sets changes what the guide draws")
	GameState.select_set(_ids[0])


func _assert(condition: bool, what: String) -> void:
	if condition:
		print("  ok    %s" % what)
	else:
		printerr("  FAIL  %s" % what)


func _unhandled_input(event: InputEvent) -> void:
	var advance := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		advance = (event as InputEventKey).keycode == KEY_TAB

	if advance and not _ids.is_empty():
		_shown = (_shown + 1) % _ids.size()
		GameState.select_set(_ids[_shown])


func _process(_delta: float) -> void:
	if _guide == null:
		return
	var active := GameState.active_set
	_readout.text = "tier guide harness — TAB/click cycle set\nactive: %s | cell %.0f | font %d" % [
		active.id if active != null else "none", _guide.cell_width(), _guide.label_size(),
	]
