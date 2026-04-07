class_name MusicTrack extends RefCounted

## One voice/instrument line within a Movement or Bridge.
##
## A Movement has N tracks (e.g., "sub", "pad", "mid", "sparkle", "shimmer", "pulse").
## Each Track owns its compiled pattern, voice routing, gain, and bus controls.
## Tracks are NEVER stacked into a single pattern — they remain individual
## through the entire playback pipeline.

## Track label — the "sub:", "pad:", etc. from the .strudel file
var label: String = ""

## Compiled Strudel pattern for this track (one full cycle)
var pattern: StrudelPattern = null

## SiON voice name — "sine", "sawtooth", "square", etc.
var voice: String = ""

## Track-level gain (0.0–1.0).  Applied per-note via _resolve_velocity().
var gain: float = 1.0

## Bus-level audio controls — {lpf, room, delay, etc.}
## These affect the audio bus, NOT individual haps.
var controls: Dictionary = {}

## Signal-modulated controls — Array[StrudelPattern] that produce {key: value} dicts.
## e.g., sine.range(200, 2000) wrapped as {lpf: value}
var signal_controls: Array = []

## ADSR envelope overrides — {attack, decay, sustain, release}
## Only the keys that were explicitly set.  Empty = use voice defaults.
var adsr: Dictionary = {}

## Original source text from the .strudel file (for drawer display)
var source_text: String = ""


static func from_compiled(compiled: Dictionary) -> MusicTrack:
	## Create a MusicTrack from the dictionary produced by
	## StrudelLineCompiler.compile_strudel_file().tracks[i].
	var t := MusicTrack.new()
	t.label = compiled.get("name", "")
	t.pattern = compiled.get("pattern")
	t.voice = compiled.get("voice", "")
	t.gain = compiled.get("gain", 1.0)
	t.source_text = compiled.get("source_text", "")
	var ctrls: Dictionary = compiled.get("controls", {})
	# Separate ADSR from bus controls
	for key in ["attack", "decay", "sustain", "release"]:
		if ctrls.has(key):
			t.adsr[key] = ctrls[key]
	for key in ctrls:
		if key not in ["attack", "decay", "sustain", "release", "gain", "velocity", "s"]:
			t.controls[key] = ctrls[key]
	t.signal_controls = compiled.get("signals", [])
	return t
