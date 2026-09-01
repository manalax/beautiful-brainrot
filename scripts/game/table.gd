## The play surface: background, four bouncy walls, danger line, launch lane.
##
## Every dimension comes from Tuning (GAME_DESIGN.md §4), so the geometry is built in code rather
## than authored into the .tscn — that keeps a single source of truth for the layout. `@tool` so
## the table draws in the editor, which makes placing the launcher and HUD against it possible.
##
## Walls are four separate bodies so a later feature can give one of them special behaviour.
@tool
extends Node2D

## Inner faces of the walls — the region pieces can occupy.
var playfield: Rect2:
	get:
		return Tuning.PLAYFIELD_RECT

## The strip below the danger line. An object resting here ends the run (F8).
var launch_lane: Rect2:
	get:
		var r := Tuning.PLAYFIELD_RECT
		return Rect2(r.position.x, Tuning.DANGER_LINE_Y, r.size.x, Tuning.LAUNCH_LANE_HEIGHT)

const WALL_NAMES := ["WallTop", "WallBottom", "WallLeft", "WallRight"]

var _wall_rects: Array[Rect2] = []
## Matches the worst danger level on the table, so the line and the piece pulse together.
var _danger := 0.0


func _ready() -> void:
	_wall_rects = _compute_wall_rects(Tuning.WALL_THICKNESS)
	if not Engine.is_editor_hint():
		_build_walls()
	set_process(false)
	queue_redraw()


## Rectangles for the four walls, `thickness` deep, growing outward from the playfield's edges.
## Top and bottom span the full width; the side walls fill the gap between them, so no two wall
## bodies overlap. Called twice: once at the visual thickness, once at the collider depth.
func _compute_wall_rects(thickness: float) -> Array[Rect2]:
	var r := Tuning.PLAYFIELD_RECT
	var t := thickness
	return [
		Rect2(r.position.x - t, r.position.y - t, r.size.x + t * 2.0, t),        # top
		Rect2(r.position.x - t, r.end.y, r.size.x + t * 2.0, t),                 # bottom
		Rect2(r.position.x - t, r.position.y, t, r.size.y),                      # left
		Rect2(r.end.x, r.position.y, t, r.size.y),                               # right
	]


## Colliders share the walls' inner faces but run much deeper, so a full-power piece cannot
## tunnel out during the frame it makes contact. The extra depth is off-screen.
func _build_walls() -> void:
	var collider_rects := _compute_wall_rects(Tuning.WALL_COLLIDER_DEPTH)
	var material := PhysicsMaterial.new()
	material.friction = Tuning.WALL_FRICTION
	material.bounce = Tuning.WALL_BOUNCE

	for i in collider_rects.size():
		var rect: Rect2 = collider_rects[i]

		var body := StaticBody2D.new()
		body.name = WALL_NAMES[i]
		body.collision_layer = Tuning.LAYER_WALLS
		body.collision_mask = Tuning.LAYER_PIECES
		body.physics_material_override = material

		var shape := RectangleShape2D.new()
		shape.size = rect.size

		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = rect.get_center()

		body.add_child(collider)
		add_child(body)


func _draw() -> void:
	if _wall_rects.is_empty():
		_wall_rects = _compute_wall_rects(Tuning.WALL_THICKNESS)

	draw_rect(Tuning.PLAYFIELD_RECT, Tuning.COLOR_TABLE_BG, true)
	draw_rect(launch_lane, Tuning.COLOR_LAUNCH_LANE, true)

	for rect in _wall_rects:
		draw_rect(rect, Tuning.COLOR_WALL, true)

	var r := Tuning.PLAYFIELD_RECT
	draw_dashed_line(
		Vector2(r.position.x, Tuning.DANGER_LINE_Y),
		Vector2(r.end.x, Tuning.DANGER_LINE_Y),
		_line_color(),
		Tuning.DANGER_LINE_WIDTH,
		Tuning.DANGER_LINE_DASH
	)


func _line_color() -> Color:
	if _danger <= 0.0:
		return Tuning.COLOR_DANGER_LINE
	var phase := Time.get_ticks_msec() / 1000.0 * TAU * Tuning.DANGER_PULSE_HZ
	var pulse := _danger * (0.5 + 0.5 * sin(phase))
	return Tuning.COLOR_DANGER_LINE.lerp(Tuning.COLOR_DANGER_WARNING, pulse)


## How close the table is to ending the run, 0..1. The danger zone drives this.
func set_danger_intensity(value: float) -> void:
	if is_equal_approx(_danger, value):
		return
	_danger = value
	set_process(_danger > 0.0)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()
