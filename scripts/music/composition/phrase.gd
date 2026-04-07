class_name MusicPhrase extends RefCounted

## A rendered bar of a single Track — what actually gets played for one cycle
## of one voice.
##
## A MusicBar contains N Phrases (one per Track in the current Movement/Bridge).
## Each Phrase independently:
##   - References which Track it came from
##   - Knows its offset into the Movement (bar index)
##   - Holds the rendered pattern slice for that bar
##   - Carries the Track's gain/voice/controls for playback

## The Track this Phrase was rendered from
var track: MusicTrack = null

## Bar offset into the Movement (0 = first bar, 1 = second, etc.)
var offset: int = 0

## The pattern for this single bar.  For infinite movements this is
## the Track's full pattern (which repeats every cycle).  For finite
## movements, this could be a slice or the full pattern depending on
## structure.
var bar_pattern: StrudelPattern = null


static func from_track(p_track: MusicTrack, p_offset: int) -> MusicPhrase:
	## Create a Phrase from a Track at a given bar offset.
	## For now, the bar_pattern is the track's full pattern (one cycle = one bar).
	## Future: support multi-bar tracks where bar_pattern is a time-slice.
	var p := MusicPhrase.new()
	p.track = p_track
	p.offset = p_offset
	p.bar_pattern = p_track.pattern
	return p
