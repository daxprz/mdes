class_name MusicMovement extends RefCounted

## A section of a Composition with a distinct feel/tone.
##
## Contains N Tracks (individual voice lines), a tempo, and a bar count.
## Tracks are never stacked — they remain individual through playback.

## Movement identifier — "light", "dark", etc.
var id: String = ""

## Number of bars.  -1 = infinite loop (most common for game music).
var bars: int = -1

## Tempo in cycles per second
var cps: float = 0.5

## Individual voice tracks — one per line in the .strudel file.
## Order matches the source file order (sub, pad, mid, sparkle, etc.)
var tracks: Array = []  # Array[MusicTrack]

## Path to the source .strudel file (for reference/reload)
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
