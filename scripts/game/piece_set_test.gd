## Dev harness for piece sets (GAME_DESIGN.md §5.1): the checks that prove the registry is sound,
## that the fallbacks hold, that ownership and persistence behave — and, most importantly, a
## visual grid of every set so you can confirm emoji actually render.
##
## Not part of the game. Run `res://scenes/game/piece_set_test.tscn` directly, windowed.
##
##   TAB / click   cycle the set being drawn large
##   G             toggle the all-sets grid
##
## The font check is the one that matters on device. `has_char` walking the chain in the editor
## on macOS proves nothing about an Android build, so run this on a real phone before authoring
## content: if the platform emoji font and the bundled Noto both fail, every piece shows tofu.
extends Node2D

@onready var _readout: Label = $UI/Readout

var _tiers: TierSet = null
var _registry: PieceSetRegistry = null
var _shown := 0
var _grid := true


func _ready() -> void:
	_tiers = TierSet.load_default()
	_registry = PieceSetRegistry.load_default()

	_check_registry()
	_check_fallbacks()
	_check_colour_override()
	_check_font()
	_check_metrics()
	_check_ownership()
	_check_persistence()
	queue_redraw()


## Every set complete, ids unique, classic present and free.
func _check_registry() -> void:
	print("\n=== piece set registry ===")
	if _registry == null:
		printerr("INVALID: %s did not load" % Tuning.PIECE_SET_REGISTRY_PATH)
		return

	var problems := _registry.validate()
	if problems.is_empty():
		print("registry valid: %d sets" % _registry.sets.size())
	else:
		for problem in problems:
			printerr("INVALID: %s" % problem)

	print("id         name        price  scale  tinted  labels")
	for piece_set in _registry.sets:
		if piece_set == null:
			continue
		var texts := PackedStringArray()
		for tier in range(1, Tuning.MAX_TIER + 1):
			var label := piece_set.get_label(tier)
			texts.append(label.text if label != null else "?")
		print("%-10s %-11s %5d  %5.2f  %-6s  %s" % [
			piece_set.id,
			piece_set.display_name,
			piece_set.price,
			piece_set.label_scale,
			"yes" if piece_set.label_tinted else "no",
			" ".join(texts),
		])


## An unknown id must land on classic rather than leaving pieces blank, and a set with a hole in
## it must fall back to the tier number for that hole alone.
func _check_fallbacks() -> void:
	print("\n=== fallbacks ===")

	var unknown := _registry.get_set_or_default(&"no-such-set")
	_assert(unknown != null and unknown.id == Tuning.DEFAULT_PIECE_SET,
		"unknown id falls back to '%s'" % Tuning.DEFAULT_PIECE_SET)

	# A deliberately incomplete set: authored for tier 1 only.
	var holed := PieceSet.new()
	holed.id = &"holed"
	holed.display_name = "Holed"
	var only := PieceLabel.new()
	only.tier = 1
	only.text = "X"
	var holed_labels: Array[PieceLabel] = [only]
	holed.labels = holed_labels

	var authored := _registry.label_for(holed, 1)
	_assert(authored != null and authored.text == "X", "authored tier is used")
	var filled := _registry.label_for(holed, 7)
	_assert(filled != null and filled.text == "7", "missing tier falls back to the tier number")
	_assert(holed.validate().size() > 0, "an incomplete set fails validate()")


## A set's colour override has to reach the table, not just the HUD swatch. Pieces build their
## own fill for the danger pulse and the merge flash and hand it back as an override, so they must
## start from PieceRender.base_fill() — starting from `data.color` would drop the set's colour on
## the floor for every piece actually in play.
func _check_colour_override() -> void:
	print("\n=== colour overrides ===")

	var tier1 := _tiers.get_tier(1)
	if tier1 == null:
		printerr("INVALID: no tier 1")
		return

	var plain := PieceSet.new()
	plain.id = &"plain"
	var untouched := PieceLabel.new()
	untouched.tier = 1
	untouched.text = "1"
	var plain_labels: Array[PieceLabel] = [untouched]
	plain.labels = plain_labels
	_assert(PieceRender.base_fill(tier1, plain).is_equal_approx(tier1.color),
		"a label with no override keeps the tier's colour")

	var tinted := PieceSet.new()
	tinted.id = &"tinted"
	var override := PieceLabel.new()
	override.tier = 1
	override.text = "1"
	override.color = Color("#00AAFF")
	var tinted_labels: Array[PieceLabel] = [override]
	tinted.labels = tinted_labels
	_assert(PieceRender.base_fill(tier1, tinted).is_equal_approx(override.color),
		"an override replaces the tier's colour")
	_assert(not PieceRender.base_fill(tier1, tinted).is_equal_approx(tier1.color),
		"the override is what a piece's own fill is built from")


## Does the font chain actually have the glyphs the sets ask for? This is the whole risk of the
## emoji decision, so it reports per set rather than pass/fail overall.
func _check_font() -> void:
	print("\n=== font chain ===")

	var font := PieceFont.label_font()
	if font == null:
		printerr("INVALID: no label font at all")
		return

	var bundled: Resource = load(Tuning.EMOJI_FONT_PATH)
	_assert(bundled != null, "bundled %s imported" % Tuning.EMOJI_FONT_PATH.get_file())
	print("base: ThemeDB.fallback_font (digits, and the metrics labels are centred on)")
	print("fallback 1: platform emoji, tried in order — %s" % ", ".join(Tuning.EMOJI_FONT_NAMES))
	print("fallback 2: %s" % Tuning.EMOJI_FONT_PATH)

	for piece_set in _registry.sets:
		if piece_set == null:
			continue
		var missing := PackedStringArray()
		for tier in range(1, Tuning.MAX_TIER + 1):
			var label := piece_set.get_label(tier)
			if label == null or label.text.is_empty():
				continue
			for i in label.text.length():
				if not font.has_char(label.text.unicode_at(i)):
					missing.append(label.text)
					break
		if missing.is_empty():
			print("  %-10s all %d labels have glyphs" % [piece_set.id, Tuning.MAX_TIER])
		else:
			printerr("  %-10s NO GLYPH for: %s  <- these draw as tofu"
				% [piece_set.id, " ".join(missing)])


## Label metrics, per set. A zero width means the chain produced no glyph at all, which is the
## same failure as tofu but silent. The baseline column is what centring rides on: it should be
## roughly 0.3 per point for digits, and differ for emoji — an emoji column identical to the
## digit one means the shaped line is reporting the base font's metrics rather than the emoji
## font's, and labels will sit off centre again.
func _check_metrics() -> void:
	print("\n=== label metrics (per point of font size) ===")

	var font := PieceFont.label_font()
	if font == null:
		printerr("INVALID: no label font")
		return

	for piece_set in _registry.sets:
		if piece_set == null:
			continue
		var widths := PackedStringArray()
		var baselines := PackedStringArray()
		var degenerate := PackedStringArray()
		for tier in range(1, Tuning.MAX_TIER + 1):
			var label := piece_set.get_label(tier)
			if label == null or label.text.is_empty():
				continue
			var m := PieceRender.label_metrics(font, label.text)
			widths.append("%.2f" % m.x)
			baselines.append("%.2f" % m.y)
			if m.x <= 0.0:
				degenerate.append(label.text)
		print("  %-10s width    %s" % [piece_set.id, " ".join(widths)])
		print("  %-10s baseline %s" % ["", " ".join(baselines)])
		if not degenerate.is_empty():
			printerr("  %-10s ZERO WIDTH for: %s  <- no glyph was produced"
				% [piece_set.id, " ".join(degenerate)])


## Free sets are owned; a priced one is not until it is granted.
func _check_ownership() -> void:
	print("\n=== ownership ===")

	for piece_set in _registry.sets:
		if piece_set != null and piece_set.is_free():
			_assert(GameState.owns_set(piece_set.id), "free set '%s' is owned" % piece_set.id)

	_assert(not GameState.owns_set(&"no-such-set"), "an unknown set is never owned")
	_assert(not GameState.select_set(&"no-such-set"), "selecting an unknown set is refused")
	_assert(GameState.active_set != null, "there is always an active set")

	# The shop seam, exercised without a shop: priced, unowned, then granted.
	var priced := PieceSet.new()
	priced.id = &"priced"
	priced.price = 500
	_assert(not priced.is_free(), "a priced set is not free")
	_assert(not GameState.unlock_set(&"priced"),
		"unlocking a set outside the registry is refused")


## The two new keys survive a write/read cycle, and an old save without them still loads.
func _check_persistence() -> void:
	print("\n=== persistence ===")

	var real_path := SaveManager.save_path
	var tmp := "user://piece_set_test.json"
	SaveManager.use_path(tmp)

	SaveManager.selected_set = &"fruit"
	var owned: Array[StringName] = [&"fruit", &"someday"]
	SaveManager.owned_sets = owned
	SaveManager.save()
	SaveManager.use_path(tmp)
	_assert(SaveManager.selected_set == &"fruit", "selected_set round-trips")
	_assert(SaveManager.owned_sets.size() == 2, "owned_sets round-trips")

	_assert(SaveManager.grant_set(&"another"), "granting a new set reports a change")
	_assert(not SaveManager.grant_set(&"another"), "granting twice is a no-op")

	# A SAVE_VERSION 1 file written before piece sets existed: the keys are simply absent.
	var legacy := FileAccess.open(tmp, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({
		"version": Tuning.SAVE_VERSION, "best_score": 4321, "top_scores": [], "stats": {},
	}))
	legacy.close()
	SaveManager.use_path(tmp)
	_assert(SaveManager.best_score == 4321, "a pre-piece-set save still loads its scores")
	_assert(SaveManager.selected_set == Tuning.DEFAULT_PIECE_SET,
		"a save with no selected_set defaults to '%s'" % Tuning.DEFAULT_PIECE_SET)
	_assert(SaveManager.owned_sets.is_empty(), "a save with no owned_sets defaults to empty")

	# A hand-corrupted file must not leave the player with no face on their pieces.
	var corrupt := FileAccess.open(tmp, FileAccess.WRITE)
	corrupt.store_string(JSON.stringify({
		"version": Tuning.SAVE_VERSION, "selected_set": 17, "owned_sets": "not-an-array",
	}))
	corrupt.close()
	SaveManager.use_path(tmp)
	_assert(SaveManager.selected_set == Tuning.DEFAULT_PIECE_SET,
		"a non-string selected_set defaults")
	_assert(SaveManager.owned_sets.is_empty(), "a non-array owned_sets defaults")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	SaveManager.use_path(real_path)
	print("restored the real save at %s" % real_path)


func _assert(condition: bool, what: String) -> void:
	if condition:
		print("  ok    %s" % what)
	else:
		printerr("  FAIL  %s" % what)


# --- the visual half ------------------------------------------------------------------------------

func _draw() -> void:
	if _registry == null or _registry.sets.is_empty():
		return

	if _grid:
		_draw_grid()
	else:
		_draw_large(_registry.sets[_shown % _registry.sets.size()])


## Every set, one row each, all twelve tiers at true size. The point of the harness: if emoji are
## broken on this device you see tofu here.
func _draw_grid() -> void:
	var y := 360.0
	for piece_set in _registry.sets:
		if piece_set == null:
			continue
		var x := 90.0
		for tier in range(1, Tuning.MAX_TIER + 1):
			var data := _tiers.get_tier(tier)
			if data == null:
				continue
			# True size would run off a 1080px row at the top tiers, so the grid draws to a
			# shared cell instead. The large view below is the one drawn at true scale.
			var radius := 26.0 + tier * 2.2
			PieceRender.draw_piece(self, Vector2(x, y), radius, data, piece_set)
			x += 80.0
		y += 190.0


## One set at the sizes the game actually uses.
func _draw_large(piece_set: PieceSet) -> void:
	var centre := Vector2(Tuning.DESIGN_SIZE.x * 0.5, 700.0)
	var angle := 0.0
	for tier in range(1, Tuning.MAX_TIER + 1):
		var data := _tiers.get_tier(tier)
		if data == null:
			continue
		var at := centre + Vector2(cos(angle), sin(angle)) * 380.0
		PieceRender.draw_piece(self, at, data.radius, data, piece_set)
		angle += TAU / Tuning.MAX_TIER


func _unhandled_input(event: InputEvent) -> void:
	var advance := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_TAB:
				advance = true
			KEY_G:
				_grid = not _grid
				queue_redraw()

	if advance:
		_shown += 1
		_grid = false
		queue_redraw()


func _process(_delta: float) -> void:
	if _registry == null or _registry.sets.is_empty():
		return
	var shown := _registry.sets[_shown % _registry.sets.size()]
	_readout.text = "piece set harness — TAB/click cycle set | G grid\n%s | active: %s | %s" % [
		"grid: all sets" if _grid else "showing: %s (scale %.2f)" % [shown.id, shown.label_scale],
		GameState.active_set.id if GameState.active_set != null else "none",
		"see Output for the font check",
	]
