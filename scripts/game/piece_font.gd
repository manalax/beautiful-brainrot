## The font chain piece labels are drawn with, built once and cached.
##
## Emoji are the reason this exists. `ThemeDB.fallback_font` is Godot's bundled monochrome Noto
## Sans and has no emoji glyphs at all, so a label of "🍉" drawn with it comes out as tofu.
##
## The chain is a FontVariation over the *text* font, with the emoji fonts hanging off it as
## fallbacks (GAME_DESIGN.md §5.2):
##
##   base       ThemeDB.fallback_font — draws digits and latin, and supplies the line metrics
##   fallback 1 the platform's own emoji font, by name (Apple Color Emoji on iOS, Noto Color
##              Emoji on Android, Segoe UI Emoji on Windows). Free to ship, and it matches what
##              the player sees everywhere else on their phone, so it is tried first.
##   fallback 2 the bundled NotoColorEmoji.ttf, so a device that resolves none of those names
##              still draws colour emoji rather than tofu.
##
## The base font is the text one rather than an emoji one on purpose. `Font.get_ascent()` and
## `get_descent()` report the *base* font's metrics, and PieceRender centres a label on those, so
## putting an emoji font first would silently shift every digit off centre — an emoji font's
## ascent is nothing like Noto Sans's. Wrapping in a FontVariation rather than setting fallbacks
## on ThemeDB.fallback_font directly matters too: that resource is shared with every Label in the
## game, and mutating it here would reach well beyond the pieces.
class_name PieceFont
extends RefCounted

static var _label_font: Font = null


## The chain described above. Built on first use. Comes back null only if there is no fallback
## font at all, which callers still guard for — a missing label beats a crash.
static func label_font() -> Font:
	if _label_font != null:
		return _label_font

	var base := ThemeDB.fallback_font
	if base == null:
		push_warning("piece font: no ThemeDB.fallback_font; labels will not draw")
		return null

	var chain: Array[Font] = []

	# Platform emoji first, as the player's own phone would draw it.
	var system := SystemFont.new()
	system.font_names = Tuning.EMOJI_FONT_NAMES
	chain.append(system)

	# Then the shipped one. This has no .import until the editor has opened the project once, so
	# a null here is normal on a fresh checkout and only means the safety net is missing.
	var bundled := load(Tuning.EMOJI_FONT_PATH) as FontFile
	if bundled != null:
		chain.append(bundled)
	else:
		push_warning("piece font: %s did not load; relying on the platform emoji font alone"
			% Tuning.EMOJI_FONT_PATH)

	# MSDF is left at its default of off throughout: a colour bitmap glyph cannot be represented
	# as a distance field, so turning it on would strip the colour out of every emoji.
	var font := FontVariation.new()
	font.base_font = base
	font.fallbacks = chain

	_label_font = font
	return _label_font


## Drops the cached chain, so the next call rebuilds it. Only the dev harness needs this.
static func reset() -> void:
	_label_font = null
