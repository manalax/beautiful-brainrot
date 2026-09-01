## Keeps the play area put on any screen shape (GAME_DESIGN.md §4.2).
##
## The playfield is a fixed size and must stay one — every physics constant in §6 and every score
## in §10 assumes a 1000x1600 table, so a run on a tall phone has to be the same run as on a short
## one. Stretching the table to fill the screen would quietly make the game different per device.
##
## So the surplus is placed rather than filled. Horizontally the design box is centred. Vertically
## most of the surplus goes *above* it, because the launcher lives at the bottom and the thumb has
## to reach it — a gap under the launch lane is the one place the space must not go.
class_name TableCamera
extends Camera2D


func _ready() -> void:
	make_current()
	get_viewport().size_changed.connect(_reposition)
	_reposition()


func _reposition() -> void:
	var view := get_viewport_rect().size
	position = Vector2(
		_centre(view.x, Tuning.DESIGN_SIZE.x, 0.5),
		_centre(view.y, Tuning.DESIGN_SIZE.y, Tuning.CAMERA_TOP_BIAS)
	)


## Where the camera must sit on one axis for `bias` of the surplus to fall before the design box
## and the rest after it. `bias` of 0.5 centres; 1.0 pins the design box to the far edge.
##
## With no surplus this returns exactly half the design size, so at the design aspect the camera
## is a no-op and screen coordinates still equal world coordinates.
func _centre(view: float, design: float, bias: float) -> float:
	return view * 0.5 - bias * maxf(0.0, view - design)
