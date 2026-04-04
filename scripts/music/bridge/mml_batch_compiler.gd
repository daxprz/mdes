class_name MmlBatchCompiler extends RefCounted

## Compiles an array of StrudelHaps (one cycle's worth) into per-voice MML
## strings for sample-accurate playback via SiON's internal sequencer.
##
## Instead of frame-dispatched note_on() calls (±8ms jitter), the compiled MML
## is fed to SiON via play(), letting the audio thread handle inter-note
## timing at 44.1kHz sample precision (~23μs).
##
## BPM mapping: 1 cycle = 1 whole note. MML_BPM = 240 * CPS.
## At CPS=0.5: BPM=120. At CPS=1: BPM=240.

## Voices resolved by the trigger — passed at construction for voice lookup.
var _trigger: Variant = null  ## StrudelSionTrigger (for _resolve_voice/_resolve_note)


func _init(trigger: Variant = null) -> void:
	_trigger = trigger


# ==============================================================================
# Public API
# ==============================================================================

func compile_cycle(haps: Array, cps: float) -> Dictionary:
	## Compile a cycle's worth of haps into per-voice MML strings.
	##
	## Returns: { voice_key: { "mml": String, "voice": Variant, "notes": int } }
	## Each entry is a separate track for sequence_on().
	if haps.is_empty() or cps <= 0.0:
		return {}

	var bpm: int = maxi(30, int(240.0 * cps))
	var groups: Dictionary = _group_by_voice(haps)
	var result: Dictionary = {}

	for voice_key in groups:
		var group: Dictionary = groups[voice_key]
		var voice_haps: Array = group["haps"]
		var voice: Variant = group["voice"]

		# Sort by onset time
		voice_haps.sort_custom(_sort_by_onset)

		# Handle polyphony within same voice: split overlapping notes into sub-tracks
		var lanes: Array = _split_into_lanes(voice_haps)

		for lane_idx in range(lanes.size()):
			var lane: Array = lanes[lane_idx]
			var mml: String = _haps_to_mml(lane, bpm)
			if mml.is_empty():
				continue
			var track_key: String = voice_key if lanes.size() == 1 else "%s_%d" % [voice_key, lane_idx]
			result[track_key] = {
				"mml": mml,
				"voice": voice,
				"notes": lane.size(),
			}

	return result


# ==============================================================================
# Voice Grouping
# ==============================================================================

func _group_by_voice(haps: Array) -> Dictionary:
	## Group haps by their resolved voice name.
	## Returns: { voice_key: { "haps": Array, "voice": Variant } }
	var groups: Dictionary = {}

	for hap in haps:
		var voice_key: String = "default"
		var voice: Variant = null

		# Extract grouping key from hap value dict.
		# Prefer _line (per-drawer-line identity) over s/sound/voice (instrument).
		# This ensures each drawer line becomes its own MML track.
		if hap.value is Dictionary:
			if hap.value.has("_line"):
				voice_key = str(hap.value["_line"])
			else:
				for k in ["s", "sound", "voice"]:
					if hap.value.has(k):
						voice_key = str(hap.value[k]).to_lower()
						break

		# Resolve the actual SiONVoice object if trigger is available
		if _trigger:
			voice = _trigger._resolve_voice(hap.value)

		if not groups.has(voice_key):
			groups[voice_key] = {"haps": [], "voice": voice}
		groups[voice_key]["haps"].append(hap)

	return groups


func _split_into_lanes(sorted_haps: Array) -> Array:
	## Split overlapping notes into separate monophonic lanes.
	## Each lane contains non-overlapping haps sorted by onset.
	var lanes: Array = []

	for hap in sorted_haps:
		var onset: float = _hap_onset(hap)
		var placed: bool = false

		# Try to place in an existing lane
		for lane in lanes:
			if lane.is_empty():
				lane.append(hap)
				placed = true
				break
			var last_end: float = _hap_end(lane[-1])
			if onset >= last_end - 0.0001:  # Small epsilon for fraction rounding
				lane.append(hap)
				placed = true
				break

		if not placed:
			lanes.append([hap])

	return lanes


# ==============================================================================
# MML Generation
# ==============================================================================

## MIDI note → MML note name lookup (within an octave, 0-11)
const MML_NOTE_NAMES := ["c", "c+", "d", "d+", "e", "f", "f+", "g", "g+", "a", "a+", "b"]

## Voice name → MML voice command. SiON module types:
##   %0 = PSG (square/noise), %1 = APU, %2 = Analog (saw/square/tri),
##   %4 = OPM (4-op FM), %5 = OPL (2-op FM), %6 = OPN (FM preset), %7 = PCM
const VOICE_TO_MML := {
	# -- Oscillator types (analog module %2) --
	"sawtooth": "%2@1", "saw": "%2@1", "square": "%2@0",
	"sine": "%6@0", "triangle": "%2@2", "supersaw": "%2@1", "noise": "%0@15",
	# -- FM presets (module %6, GM program numbers 0-indexed) --
	"piano": "%6@0", "epiano": "%6@4", "organ": "%6@16", "church": "%6@19",
	"guitar": "%6@24", "acoustic": "%6@24", "electric": "%6@27",
	"overdrive": "%6@29", "distortion": "%6@30",
	"bass": "%6@32", "fingerbass": "%6@33", "synthbass": "%6@38",
	"violin": "%6@40", "strings": "%6@48", "choir": "%6@52",
	"trumpet": "%6@56", "brass": "%6@61", "sax": "%6@65", "oboe": "%6@68",
	"flute": "%6@73", "recorder": "%6@74", "whistle": "%6@78",
	"lead": "%6@81", "calliope": "%6@82",
	"pad": "%6@89", "warmpad": "%6@89", "newage": "%6@88",
	"marimba": "%6@12", "vibes": "%6@11", "xylophone": "%6@13",
	"bells": "%6@14", "glockenspiel": "%6@9", "celesta": "%6@8",
	"harp": "%6@46", "timpani": "%6@47",
	"bd": "%6@1", "sd": "%6@1", "hh": "%6@1",
	"pno": "%6@0", "str": "%6@48", "syn": "%6@81", "fl": "%6@73",
	"default": "%6@0",
}


func _haps_to_mml(sorted_haps: Array, bpm: int) -> String:
	## Convert a sorted array of haps into a looping MML string.
	## One cycle = one whole note at the given BPM.
	##
	## Simple approach: N notes per cycle → set l<N> as the default note length.
	## Each note uses the default length. This produces correct, evenly-spaced MML
	## regardless of hap whole span timing (which can be fractured by pattern algebra).
	if sorted_haps.is_empty():
		return ""

	var n: int = sorted_haps.size()
	var repeat_count: int = 9999

	# MML note length: N notes per whole note → l<N>
	# q8 = full gate time (sustain the entire note duration, no early cutoff)
	var parts: Array[String] = ["t%d q8 l%d [" % [bpm, n]]

	for hap in sorted_haps:
		var note_num: int = -1
		if _trigger:
			note_num = _trigger._resolve_note(hap.value)
		else:
			note_num = _resolve_note_simple(hap.value)

		if note_num >= 0:
			var octave: int = (note_num / 12) - 1
			var note_idx: int = note_num % 12
			parts.append("o%d %s " % [octave, MML_NOTE_NAMES[note_idx]])
		else:
			parts.append("r ")

	parts.append("]%d" % repeat_count)
	return "".join(PackedStringArray(parts))


func _emit_note(midi: int, duration: StrudelFraction) -> String:
	## Generate MML for a single note with explicit length.
	var length_str: String = _duration_to_mml(duration)
	var octave: int = (midi / 12) - 1
	var note_idx: int = midi % 12
	return "o%d %s%s " % [octave, MML_NOTE_NAMES[note_idx], length_str]


func _emit_rest(duration: StrudelFraction) -> String:
	## Generate MML rest: r<length>
	var length_str: String = _duration_to_mml(duration)
	return "r%s " % length_str


# ==============================================================================
# Duration Decomposition: StrudelFraction → MML Length Notation
# ==============================================================================

func _duration_to_mml(frac: StrudelFraction) -> String:
	## Convert a rational duration (fraction of a whole note) to MML length notation.
	if frac.n <= 0:
		return "64"  # Minimum length

	var remaining: StrudelFraction = StrudelFraction.new(frac.n, frac.d)
	var parts: Array[String] = []
	var max_iter: int = 8

	while remaining.n > 0 and max_iter > 0:
		max_iter -= 1
		var best_denom: int = -1
		var best_dots: int = 0
		var best_value: StrudelFraction = null

		for denom in [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]:
			var val: StrudelFraction = StrudelFraction.new(1, denom)
			if val.lte(remaining):
				if best_value == null or val.gt(best_value):
					best_denom = denom
					best_dots = 0
					best_value = val

			var dotted: StrudelFraction = val.mul(StrudelFraction.new(3, 2))
			if dotted.lte(remaining):
				if best_value == null or dotted.gt(best_value):
					best_denom = denom
					best_dots = 1
					best_value = dotted

			var ddotted: StrudelFraction = val.mul(StrudelFraction.new(7, 4))
			if ddotted.lte(remaining):
				if best_value == null or ddotted.gt(best_value):
					best_denom = denom
					best_dots = 2
					best_value = ddotted

		if best_denom < 0 or best_value == null:
			if not parts.is_empty():
				break
			return "64"

		var notation: String = str(best_denom)
		for _i in range(best_dots):
			notation += "."
		parts.append(notation)

		remaining = remaining.sub(best_value)
		if remaining.n == 0 or (remaining.to_float() < 1.0 / 128.0):
			break

	return "^".join(PackedStringArray(parts))


# ==============================================================================
# Helpers
# ==============================================================================

static func _sort_by_onset(a: StrudelHap, b: StrudelHap) -> bool:
	var a_onset: float = a.w().begin.to_float() if a.whole != null else 0.0
	var b_onset: float = b.w().begin.to_float() if b.whole != null else 0.0
	return a_onset < b_onset


static func _hap_onset(hap: StrudelHap) -> float:
	return hap.w().begin.to_float() if hap.whole != null else 0.0


static func _hap_end(hap: StrudelHap) -> float:
	if hap.whole == null:
		return hap.part.end.to_float()
	return hap.w().begin.add(hap.get_duration()).to_float()


static func _hap_onset_frac(hap: StrudelHap) -> StrudelFraction:
	if hap.whole != null:
		return hap.w().begin
	return hap.part.begin


func _resolve_note_simple(value: Variant) -> int:
	## Fallback note resolution when no trigger is available (for testing).
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String:
		return _note_name_to_midi(value)
	if value is Dictionary:
		for key in ["note", "value", "n"]:
			if value.has(key):
				var n: Variant = value[key]
				if n is String:
					return _note_name_to_midi(n)
				if n is int or n is float:
					return int(n)
	return -1


static func _note_name_to_midi(note_name: String) -> int:
	## Minimal note name → MIDI converter for testing.
	const NOTES := {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
	note_name = note_name.strip_edges().to_lower()
	if note_name.is_valid_int():
		return int(note_name)
	if note_name.is_empty() or not NOTES.has(note_name[0]):
		return -1
	var letter: String = note_name[0]
	var base: int = NOTES[letter]
	var pos: int = 1
	while pos < note_name.length():
		if note_name[pos] == "#" or note_name[pos] == "s":
			base += 1
			pos += 1
		elif note_name[pos] == "b" or note_name[pos] == "-":
			if note_name[pos] == "b" and letter == "b" and pos == 1:
				break
			base -= 1
			pos += 1
		else:
			break
	var octave: int = 4
	if pos < note_name.length() and note_name.substr(pos).is_valid_int():
		octave = int(note_name.substr(pos))
	return (octave + 1) * 12 + base
