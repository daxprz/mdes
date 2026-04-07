class_name MusicBar extends RefCounted

## One cycle of playback — contains a list of Phrases, one per Track.
##
## A Bar knows which Movement/Bridge/Turnaround it belongs to,
## its index within that section, and its absolute cycle number.
## The Phrases are the actual renderable units — each independently
## carries its Track's pattern, gain, voice, and controls.

## Which movement this bar belongs to (always set)
var movement: MusicMovement = null

## Non-null only when this bar is part of a bridge transition
var bridge: MusicBridge = null

## Non-null only when this bar is part of a turnaround variation
var turnaround: MusicTurnaround = null

## Index within the section (0 = first bar of this movement/bridge/turnaround)
var index: int = 0

## Absolute cycle number since playback started
var cycle_number: int = 0

## The individual rendered track phrases for this bar.
## One Phrase per Track.  Never stacked.
var phrases: Array = []  # Array[MusicPhrase]


func get_cps() -> float:
	## Return the tempo for this bar.
	## Bridge > turnaround > movement priority.
	if bridge:
		return bridge.cps
	return movement.cps if movement else 0.5


func get_section_id() -> String:
	## Return the id of the active section (bridge > turnaround > movement).
	if bridge:
		return bridge.id
	if turnaround:
		return turnaround.id
	return movement.id if movement else ""


static func from_movement(p_movement: MusicMovement, p_bar_index: int, p_cycle: int) -> MusicBar:
	var b := MusicBar.new()
	b.movement = p_movement
	b.index = p_bar_index
	b.cycle_number = p_cycle
	b.phrases = p_movement.get_phrases_for_bar(p_bar_index)
	return b


static func from_bridge(p_bridge: MusicBridge, p_movement: MusicMovement, p_bar_index: int, p_cycle: int) -> MusicBar:
	var b := MusicBar.new()
	b.movement = p_movement
	b.bridge = p_bridge
	b.index = p_bar_index
	b.cycle_number = p_cycle
	b.phrases = p_bridge.get_phrases_for_bar(p_bar_index)
	return b


static func from_turnaround(p_turnaround: MusicTurnaround, p_movement: MusicMovement, p_bar_index: int, p_cycle: int) -> MusicBar:
	var b := MusicBar.new()
	b.movement = p_movement
	b.turnaround = p_turnaround
	b.index = p_bar_index
	b.cycle_number = p_cycle
	b.phrases = p_turnaround.get_phrases_for_bar(p_bar_index)
	return b
