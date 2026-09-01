## Turns same-tier contacts into merges (GAME_DESIGN.md §8).
##
## Contacts arrive as physics callbacks, where freeing and spawning bodies is not safe, so pairs
## are queued as they are reported and resolved on the physics step. Claiming both pieces the
## instant a pair is queued is what makes the §8 guarantees hold: the same pair is reported twice
## (once by each body) and must merge once, and three touching pieces of a tier must produce
## exactly one merge, never one-and-a-half.
##
## The resolver watches the pieces container rather than being handed each piece, so the launcher
## and the spawn queue can go on creating pieces without knowing it exists.
class_name MergeResolver
extends Node

const PIECE_SCENE := preload("res://scenes/game/piece.tscn")

## Two pieces became one. `tier` is the tier produced. F7 turns this into score.
signal merged(tier: int, position: Vector2, chain_depth: int)
## Two tier-12s annihilated. Nothing is produced; the table loses mass.
signal annihilated(position: Vector2, chain_depth: int)

@export var pieces_root_path: NodePath

## How many merges deep the current shot is. Reset by the owner when a new piece is fired, not on
## a timer: a shot that ricochets and merges seconds later still belongs to that shot.
var chain_depth := 0

var _tiers: TierSet = null
var _queue: Array[Array] = []


func _ready() -> void:
	_tiers = TierSet.load_default()
	var root := _pieces_root()
	root.child_entered_tree.connect(_watch)
	for child in root.get_children():
		_watch(child)


## Called at the start of every shot.
func reset_chain() -> void:
	chain_depth = 0


func _pieces_root() -> Node:
	if not pieces_root_path.is_empty():
		var node := get_node_or_null(pieces_root_path)
		if node != null:
			return node
	return get_parent()


func _watch(node: Node) -> void:
	var piece := node as Piece
	if piece != null:
		piece.body_entered.connect(_on_contact.bind(piece))


func _on_contact(other: Node, piece: Piece) -> void:
	var second := other as Piece
	if second == null or second.tier != piece.tier:
		return
	if not piece.can_merge() or not second.can_merge():
		return

	# Claimed here, inside the callback, so the mirrored report of this same contact — and any
	# third piece touching either of them this frame — finds them already spoken for.
	piece.merging = true
	second.merging = true
	_queue.append([piece, second])


func _physics_process(_delta: float) -> void:
	if _queue.is_empty():
		return

	var pending := _queue
	_queue = []
	for pair in pending:
		var first := pair[0] as Piece
		var second := pair[1] as Piece
		# Either piece may have been freed for another reason between queueing and now.
		if is_instance_valid(first) and is_instance_valid(second):
			_resolve(first, second)


func _resolve(first: Piece, second: Piece) -> void:
	var tier := first.tier
	var midpoint := (first.global_position + second.global_position) * 0.5
	# Averaged, not conserved: the merged mass is less than the sum of its parts, so true
	# conservation would make merges accelerate. See §8.
	var velocity := (
		(first.linear_velocity + second.linear_velocity) * 0.5 * Tuning.MERGE_MOMENTUM_SCALE
	)

	first.despawn()
	second.despawn()

	if tier >= Tuning.MAX_TIER:
		annihilated.emit(midpoint, chain_depth)
		chain_depth += 1
		return

	var piece := PIECE_SCENE.instantiate() as Piece
	piece.position = midpoint
	_pieces_root().add_child(piece)
	piece.setup(_tiers.next_tier(tier))
	piece.inherit_velocity(velocity)
	piece.merge_cooldown = Tuning.MERGE_COOLDOWN_FRAMES
	piece.play_merge_effect()

	merged.emit(tier + 1, midpoint, chain_depth)
	chain_depth += 1
