class_name MusicPlayHead extends RefCounted

## High-precision position within the current bar.

## Position within the current bar [0.0, 1.0)
var cycle_position: float = 0.0

## Total cycles elapsed since playback started
var absolute_cycle: float = 0.0

## Index into MusicRecord.played_bars
var bar_index: int = 0


func update_from_cyclist(cyclist_now: float) -> void:
	## Update position from the cyclist's current time.
	absolute_cycle = cyclist_now
	cycle_position = cyclist_now - floorf(cyclist_now)
