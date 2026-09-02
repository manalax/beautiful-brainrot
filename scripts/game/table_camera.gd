## Keeps the play area put on any screen shape (GAME_DESIGN.md §4.2).
##
## The playfield is a fixed size and must stay one — every physics constant in §6 and every score
## in §10 assumes a 1000x1600 table, so a run on a tall phone has to be the same run as on a short
## one. Stretching the table to fill the screen would quietly make the game different per device.
##
## So the surplus is placed rather than filled. Horizontally the design box is centred. Vertically
## most of the surplus goes *above* it, because the launcher lives at the bottom and the thumb has
## to reach it — a gap under the launch lane is the one place the space must not go.
##
## Where the box lands is `DesignBox`'s call, not this camera's — the HUD has to land on the same
## answer, and it is not a Node2D so it cannot get there by being looked at.
class_name TableCamera
extends Camera2D


func _ready() -> void:
	make_current()
	get_viewport().size_changed.connect(_reposition)
	_reposition()


## Puts design-space (0, 0) at `DesignBox.origin()`. At the design aspect that origin is (0, 0),
## so the camera resolves to the centre of the design box, is a complete no-op, and screen
## coordinates still equal world coordinates.
func _reposition() -> void:
	var view := get_viewport_rect().size
	position = view * 0.5 - DesignBox.origin(view)
