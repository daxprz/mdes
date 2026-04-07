class_name MusicRecord extends RefCounted

## What was actually played / is playing.
## History of completed bars, the current bar, and cued upcoming bars.

signal bar_completed(bar: MusicBar)
signal bar_started(bar: MusicBar)
signal cue_changed(cued: Array)

## The composition being played
var composition: MusicComposition = null

## Bars that have already played (most recent last)
var played_bars: Array = []  # Array[MusicBar]

## Current playback position
var play_head: MusicPlayHead = MusicPlayHead.new()

## Upcoming bars — modifiable by game events (transitions, turnarounds).
## The front of this array is the NEXT bar to play.
var cued_bars: Array = []  # Array[MusicBar]

## Whether playback is active
var is_playing: bool = false

## The bar currently being played (null before first bar starts)
var current_bar: MusicBar = null


func advance_bar() -> void:
	## Move to the next bar: current -> played, cued.front -> current.
	## Emits bar_completed for the old bar and bar_started for the new one.
	if current_bar:
		played_bars.append(current_bar)
		bar_completed.emit(current_bar)

	if cued_bars.is_empty():
		current_bar = null
		return

	current_bar = cued_bars.pop_front()
	play_head.bar_index = played_bars.size()
	bar_started.emit(current_bar)


func replace_cued(new_cued: Array) -> void:
	## Replace the cue queue (e.g., when a transition is requested).
	## Emits cue_changed so UI can update.
	cued_bars = new_cued
	cue_changed.emit(cued_bars)


func get_current_phrases() -> Array:
	## Return the Phrases for the currently playing bar.
	## Returns empty array if nothing is playing.
	if current_bar:
		return current_bar.phrases
	return []


func get_current_tracks() -> Array:
	## Return the MusicTracks for the currently playing bar.
	## Convenience — extracts track refs from phrases.
	var tracks: Array = []
	for phrase in get_current_phrases():
		if phrase.track:
			tracks.append(phrase.track)
	return tracks
