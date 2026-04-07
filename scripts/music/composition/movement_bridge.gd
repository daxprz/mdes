class_name MusicBridge extends RefCounted

## A fixed-length transition between two Movements.
##
## Always finite (1-2 bars).  Has its own tracks, tempo, and
## from/to movement references.

## Bridge identifier — "bridge_to_dark", "bridge_to_light"
var id: String = ""

## Number of bars — always finite (usually 1)
var bars: int = 1

## Tempo in cycles per second
var cps: float = 0.5

## Which movements this bridges between
var from_movement_id: String = ""
var to_movement_id: String = ""

## Individual voice tracks for the bridge
var tracks: Array = []  # Array[MusicTrack]

## Path to the source .strudel file
var strudel_file: String = ""


func get_track_count() -> int:
	return tracks.size()


func get_phrases_for_bar(bar_index: int) -> Array:
	## Generate Phrases for all tracks at the given bar offset.
	## Returns Array[MusicPhrase].
	var phrases: Array = []
	for track in tracks:
		phrases.append(MusicPhrase.from_track(track, bar_index))
	return phrases
