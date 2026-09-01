## Every piece set the build ships with, authored as `res://resources/piece_sets.tres`.
##
## An explicit list rather than a scan of `res://resources/sets/`: DirAccess over `res://` is not
## dependable in an exported build, and an unlockable that silently fails to appear on device is
## a worse bug than one that fails to appear in the editor.
##
## Sets are addressed by their string id, which is also what the save file stores (§13).
@tool
class_name PieceSetRegistry
extends Resource

@export var sets: Array[PieceSet] = []


static func load_default() -> PieceSetRegistry:
	return load(Tuning.PIECE_SET_REGISTRY_PATH) as PieceSetRegistry


## The set with `id`, or null when nothing matches.
func get_set(id: StringName) -> PieceSet:
	for piece_set in sets:
		if piece_set != null and piece_set.id == id:
			return piece_set
	return null


## The classic set, which everything falls back to. Null only if the registry is broken, which
## validate() is there to catch.
func default_set() -> PieceSet:
	return get_set(Tuning.DEFAULT_PIECE_SET)


## The set with `id` if it exists, otherwise the default. Never returns null on a sound registry,
## so callers do not each have to re-implement the fallback.
func get_set_or_default(id: StringName) -> PieceSet:
	var piece_set := get_set(id)
	return piece_set if piece_set != null else default_set()


## The label to draw for `tier` in `piece_set`, falling back to the default set's label when this
## set does not author that tier. A set with a hole in it therefore shows a tier number there
## rather than a blank circle.
func label_for(piece_set: PieceSet, tier: int) -> PieceLabel:
	if piece_set != null:
		var label := piece_set.get_label(tier)
		if label != null:
			return label

	var fallback := default_set()
	return fallback.get_label(tier) if fallback != null else null


## Ids the player owns without paying: everything free. The save adds to this (§13).
func free_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for piece_set in sets:
		if piece_set != null and piece_set.is_free():
			out.append(piece_set.id)
	return out


## Checks the registry and every set in it. Returns a list of problems, empty when sound.
func validate() -> Array[String]:
	var problems: Array[String] = []

	if sets.is_empty():
		problems.append("registry is empty")

	var seen: Array[StringName] = []
	for piece_set in sets:
		if piece_set == null:
			problems.append("registry holds a null set")
			continue
		if piece_set.id in seen:
			problems.append("duplicate set id '%s'" % piece_set.id)
		seen.append(piece_set.id)
		problems.append_array(piece_set.validate())

	var fallback := default_set()
	if fallback == null:
		problems.append("no '%s' set — nothing to fall back to" % Tuning.DEFAULT_PIECE_SET)
	elif not fallback.is_free():
		problems.append("the '%s' fallback set is priced; it must be free" % Tuning.DEFAULT_PIECE_SET)

	return problems
