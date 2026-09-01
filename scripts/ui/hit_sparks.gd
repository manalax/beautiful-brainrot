## The mark a piece leaves when it hits a wall hard (GAME_DESIGN.md §12 F11).
##
## An arc struck against the wall at the contact point, spreading and fading over a quarter of a
## second, sized by how hard the hit was. Slow nudges leave nothing — only impacts worth noticing
## get marked, or the walls would twinkle constantly.
##
## Like ScorePopups, every spark is drawn by this one node rather than being its own scene, so a
## busy rally costs a handful of dictionaries instead of a burst of instantiation (§15).
class_name HitSparks
extends Node2D

## Watches this container and marks every piece that joins it, the same way MergeResolver does,
## so nothing that creates pieces has to know sparks exist.
@export var pieces_root_path: NodePath

var _active: Array[Dictionary] = []


func _ready() -> void:
	var root := _pieces_root()
	if root == null:
		return
	root.child_entered_tree.connect(_watch)
	for child in root.get_children():
		_watch(child)


func clear() -> void:
	_active.clear()
	queue_redraw()


func _pieces_root() -> Node:
	if not pieces_root_path.is_empty():
		return get_node_or_null(pieces_root_path)
	return get_parent()


func _watch(node: Node) -> void:
	var piece := node as Piece
	if piece != null:
		piece.hit_wall.connect(_on_hit_wall)


func _on_hit_wall(position: Vector2, normal: Vector2, speed: float) -> void:
	# The arc has to open back into the table. Contact normals can be reported facing either way
	# depending on which body is asked, so settle it against the playfield rather than trusting
	# the sign: whichever direction points at the table's middle is the one to use.
	var inward := Tuning.PLAYFIELD_RECT.get_center() - position
	var facing := normal if normal.dot(inward) >= 0.0 else -normal

	_active.append({
		"position": position + facing.normalized() * Tuning.SPARK_INSET,
		"angle": facing.angle(),
		"strength": clampf(
			(speed - Tuning.SPARK_MIN_SPEED) / (Tuning.PIECE_MAX_SPEED - Tuning.SPARK_MIN_SPEED),
			0.0,
			1.0
		),
		"age": 0.0,
	})


func _process(delta: float) -> void:
	if _active.is_empty():
		return

	var survivors: Array[Dictionary] = []
	for spark in _active:
		spark["age"] += delta
		if spark["age"] < Tuning.SPARK_LIFETIME:
			survivors.append(spark)
	_active = survivors
	queue_redraw()


func _draw() -> void:
	for spark in _active:
		var progress: float = spark["age"] / Tuning.SPARK_LIFETIME
		var strength: float = spark["strength"]

		# Springs out almost immediately and then eases, fading the whole way — an impact should
		# be at its brightest on the frame it happens, not a tenth of a second later.
		var radius: float = Tuning.SPARK_MAX_RADIUS * lerpf(0.45, 1.0, strength) \
			* (1.0 - pow(1.0 - progress, 4.0))
		var alpha := pow(1.0 - progress, 1.4) * lerpf(0.6, 1.0, strength)
		var angle: float = spark["angle"]

		draw_arc(
			spark["position"],
			maxf(radius, 1.0),
			angle - Tuning.SPARK_SPREAD,
			angle + Tuning.SPARK_SPREAD,
			20,
			Color(Tuning.COLOR_SPARK, alpha),
			Tuning.SPARK_WIDTH * (1.0 - progress * 0.6),
			true
		)
