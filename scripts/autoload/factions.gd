extends Node

## Faction system — determines which entities are hostile, friendly, or neutral
## to each other. Used by AI targeting and damage systems.
##
## Factions:
##   "players"  — human-controlled characters and player-controlled monsters
##   "monsters" — AI quadruped monsters (hostile to players and animals)
##   "animals"  — bats (hostile to bugs, neutral to players)
##   "bugs"     — fireflies (passive, prey for animals)
##
## Hostility matrix (A is hostile to B):
##   players  → monsters
##   monsters → players, animals
##   animals  → bugs
##   bugs     → (nothing — passive)

# Hostility table: faction_name → array of factions it will attack
const HOSTILITY: Dictionary = {
	"players":  ["monsters"],
	"monsters": ["players", "animals"],
	"animals":  ["bugs"],
	"bugs":     [],
}

# All known factions
const ALL_FACTIONS: Array[String] = ["players", "monsters", "animals", "bugs"]


func is_hostile(attacker_faction: String, target_faction: String) -> bool:
	## Returns true if attacker_faction considers target_faction an enemy.
	if not HOSTILITY.has(attacker_faction):
		return false
	return target_faction in HOSTILITY[attacker_faction]


func are_allies(faction_a: String, faction_b: String) -> bool:
	## Returns true if neither faction is hostile to the other.
	return not is_hostile(faction_a, faction_b) and not is_hostile(faction_b, faction_a)


func get_faction(node: Node) -> String:
	## Determine an entity's faction from its group membership or metadata.
	# Explicit faction override (set by player controller, etc.)
	if node.has_meta("faction"):
		return node.get_meta("faction")
	# Infer from groups
	if node.is_in_group("players"):
		return "players"
	if node.is_in_group("animals"):
		return "animals"
	if node.is_in_group("bugs"):
		return "bugs"
	if node.is_in_group("enemies"):
		return "monsters"
	return ""


func get_hostile_targets(attacker: Node) -> Array[Node]:
	## Get all valid targets that the attacker's faction considers hostile.
	var faction: String = get_faction(attacker)
	if faction.is_empty():
		return []
	var hostile_factions: Array = HOSTILITY.get(faction, [])
	if hostile_factions.is_empty():
		return []

	var targets: Array[Node] = []
	for target_faction in hostile_factions:
		# Map faction to group name(s) to search
		var groups: Array[String] = _faction_to_groups(target_faction)
		for group_name in groups:
			for node in attacker.get_tree().get_nodes_in_group(group_name):
				if node == attacker:
					continue
				if not node is Node2D:
					continue
				# Skip dead entities
				if "_dead" in node and node._dead:
					continue
				if "health" in node and node.health <= 0:
					continue
				targets.append(node)
	return targets


func _faction_to_groups(faction: String) -> Array[String]:
	## Map a faction name to the Godot groups its members belong to.
	match faction:
		"players":
			return ["players"]
		"monsters":
			return ["enemies"]
		"animals":
			return ["animals"]
		"bugs":
			return ["bugs"]
	return []
