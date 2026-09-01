## The full twelve-rung merge chain, authored as `res://resources/tiers.tres` so it stays
## editable in the inspector.
##
## This is the gameplay chain and nothing else: radius, and the colour a tier falls back to. What
## a piece *looks like* is a PieceSet (§5.1), which is also where the eventual art swap lands —
## no piece set can reach anything in here, which is what keeps unlockable sets cosmetic.
##
## Tiers are addressed by their 1-based tier number, never by array index.
@tool
class_name TierSet
extends Resource

const DEFAULT_PATH := "res://resources/tiers.tres"

@export var tiers: Array[TierData] = []


static func load_default() -> TierSet:
	return load(DEFAULT_PATH) as TierSet


## The TierData for `tier`, or null if it is out of range.
func get_tier(tier: int) -> TierData:
	for data in tiers:
		if data != null and data.tier == tier:
			return data
	return null


## What `tier` merges into, or null at the top of the chain — tier 12 has no successor, because
## two of them annihilate instead of merging (§8).
func next_tier(tier: int) -> TierData:
	return get_tier(tier + 1)


## Checks the set is complete and internally consistent. Returns a list of problems, empty when
## the set is sound. Cheap enough to call from a harness or a test.
func validate() -> Array[String]:
	var problems: Array[String] = []

	if tiers.size() != Tuning.MAX_TIER:
		problems.append("expected %d tiers, found %d" % [Tuning.MAX_TIER, tiers.size()])

	var previous_radius := 0.0
	for tier in range(1, Tuning.MAX_TIER + 1):
		var data := get_tier(tier)
		if data == null:
			problems.append("tier %d is missing" % tier)
			continue
		if data.radius <= previous_radius:
			problems.append("tier %d radius %.1f is not larger than tier %d's %.1f"
				% [tier, data.radius, tier - 1, previous_radius])
		previous_radius = data.radius

	return problems
