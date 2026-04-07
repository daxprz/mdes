class_name MusicComposition extends RefCounted

## The full musical piece — all movements, bridges, and turnarounds.
## Pure data.  No playback state, no UI.

## Composition identifier — "title_screen", "boss_fight", etc.
var id: String = ""

## All movements, keyed by id
var movements: Dictionary = {}  # String -> MusicMovement

## All bridges, keyed by id
var bridges: Dictionary = {}  # String -> MusicBridge

## All turnarounds, keyed by id
var turnarounds: Dictionary = {}  # String -> MusicTurnaround

## Which movement plays first
var default_movement_id: String = ""


func get_default_movement() -> MusicMovement:
	return movements.get(default_movement_id)


func get_bridge_between(from_id: String, to_id: String) -> MusicBridge:
	## Find a bridge that goes from `from_id` to `to_id`.
	## Returns null if no such bridge exists.
	for bridge in bridges.values():
		if bridge.from_movement_id == from_id and bridge.to_movement_id == to_id:
			return bridge
	return null


func get_transitions_from(from_id: String) -> Array:
	## Return all bridges originating from `from_id`.
	## Each entry: {target_id: String, bridge: MusicBridge}
	var result: Array = []
	for bridge in bridges.values():
		if bridge.from_movement_id == from_id:
			result.append({"target_id": bridge.to_movement_id, "bridge": bridge})
	return result
