class_name MusicTurnaround extends RefCounted

## A toggleable variation that leads a Movement into a Bridge.
##
## When activated, replaces the current movement's tracks for N bars,
## then hands off to the target bridge.

## Turnaround identifier
var id: String = ""

## Fixed duration in bars before the bridge
var bars: int = 1

## Override tracks (replace the movement's tracks during the turnaround)
var tracks: Array = []  # Array[MusicTrack]

## Which bridge to enter after the turnaround completes
var target_bridge_id: String = ""


func get_phrases_for_bar(bar_index: int) -> Array:
	## Generate Phrases for all tracks at the given bar offset.
	var phrases: Array = []
	for track in tracks:
		phrases.append(MusicPhrase.from_track(track, bar_index))
	return phrases
