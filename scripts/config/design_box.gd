## Where the 1080x1920 design box sits on a real screen (GAME_DESIGN.md §4.2).
##
## The design box is never stretched — the surplus on a taller or wider viewport is *placed*
## around it. Two things have to agree about where it landed: `TableCamera`, which puts the world
## there, and the `Hud`, which is laid out in design coordinates but lives on a `CanvasLayer` and
## so would otherwise be pinned to the screen instead. Both ask here.
##
## Static only; nothing to instance, and no autoload.
@tool
class_name DesignBox
extends RefCounted


## Screen position of design-space (0, 0) for a viewport of `view` pixels. At the design aspect
## this is exactly (0, 0), which is why every harness that assumes screen == world still holds.
static func origin(view: Vector2) -> Vector2:
	return Vector2(
		_place(view.x, Tuning.DESIGN_SIZE.x, Tuning.CAMERA_SIDE_BIAS),
		_place(view.y, Tuning.DESIGN_SIZE.y, Tuning.CAMERA_TOP_BIAS)
	)


## How much of one axis falls *before* the design box, for `bias` of the surplus placed ahead of
## it. `bias` of 0.5 centres; 1.0 pins the box to the far edge. Never negative: a viewport
## smaller than the design box on an axis loses the overhang rather than pulling the box back.
static func _place(view: float, design: float, bias: float) -> float:
	return bias * maxf(0.0, view - design)
