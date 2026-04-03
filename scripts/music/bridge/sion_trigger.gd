class_name StrudelSionTrigger extends RefCounted

## Bridges Strudel hap events to GDSiON note_on/note_off calls.
## Converts pattern values (note names, MIDI numbers, frequencies)
## to SiON driver calls.

var driver: Variant = null     ## SiONDriver (dynamic to avoid parse-time dep)
var presets: Variant = null     ## SiONVoicePresetUtil
var _voices: Dictionary = {}   ## name -> SiONVoice
var _active_notes: Dictionary = {} ## track_id -> scheduled_off_time


func _init(p_driver: Variant, p_presets: Variant) -> void:
	driver = p_driver
	presets = p_presets
	_setup_voices()


func _setup_voices() -> void:
	if not presets:
		return

	# Build the full voice map: friendly name -> SiON preset
	# Names are chosen to be short and intuitive for mini-notation s() usage.
	var map := {
		# -- Piano / Keys --
		"piano":       "midi.piano1",
		"epiano":      "midi.piano5",
		"honkytonk":   "midi.piano4",
		"harpsichord": "midi.piano7",
		"clavi":       "midi.piano8",
		"celesta":     "midi.chrom1",
		"glockenspiel":"midi.chrom2",
		"musicbox":    "midi.chrom3",
		"vibes":       "midi.chrom4",
		"marimba":     "midi.chrom5",
		"xylophone":   "midi.chrom6",
		"bells":       "midi.chrom7",
		"dulcimer":    "midi.chrom8",
		# -- Organ --
		"organ":       "midi.organ3",
		"church":      "midi.organ4",
		"accordion":   "midi.organ6",
		"harmonica":   "midi.organ7",
		# -- Guitar --
		"guitar":      "midi.guitar1",
		"acoustic":    "midi.guitar1",
		"steel":       "midi.guitar2",
		"jazz":        "midi.guitar3",
		"electric":    "midi.guitar4",
		"muted":       "midi.guitar5",
		"overdrive":   "midi.guitar6",
		"distortion":  "midi.guitar7",
		# -- Bass --
		"bass":        "midi.bass1",
		"fingerbass":  "midi.bass2",
		"pickbass":    "midi.bass3",
		"fretless":    "midi.bass4",
		"slap":        "midi.bass5",
		"synthbass":   "midi.bass7",
		# -- Strings --
		"violin":      "midi.strings1",
		"viola":       "midi.strings2",
		"cello":       "midi.strings3",
		"contrabass":  "midi.strings4",
		"strings":     "midi.ensemble1",
		"pizzicato":   "midi.strings6",
		"harp":        "midi.strings7",
		"timpani":     "midi.strings8",
		# -- Ensemble --
		"choir":       "midi.ensemble5",
		"voice":       "midi.ensemble6",
		"orchestra":   "midi.ensemble8",
		# -- Brass --
		"trumpet":     "midi.brass1",
		"trombone":    "midi.brass2",
		"tuba":        "midi.brass3",
		"horn":        "midi.brass5",
		"brass":       "midi.brass6",
		# -- Reed / Wind --
		"sax":         "midi.reed2",
		"sopranosax":  "midi.reed1",
		"tenorsax":    "midi.reed3",
		"oboe":        "midi.reed5",
		"bassoon":     "midi.reed7",
		"clarinet":    "midi.reed8",
		"flute":       "midi.pipe2",
		"piccolo":     "midi.pipe1",
		"recorder":    "midi.pipe3",
		"panflute":    "midi.pipe4",
		"whistle":     "midi.pipe7",
		"ocarina":     "midi.pipe8",
		# -- Synth Lead --
		"square":      "midi.lead1",
		"sawtooth":    "midi.lead2",
		"saw":         "midi.lead2",
		"lead":        "midi.lead2",
		"calliope":    "midi.lead3",
		"chiff":       "midi.lead4",
		"charang":     "midi.lead5",
		"fifths":      "midi.lead7",
		# -- Synth Pad --
		"pad":         "midi.pad2",
		"newage":      "midi.pad1",
		"warmpad":     "midi.pad2",
		"polysynth":   "midi.pad3",
		"choirpad":    "midi.pad4",
		"bowed":       "midi.pad5",
		"metallic":    "midi.pad6",
		# -- Short aliases --
		"pno":         "midi.piano1",
		"str":         "midi.ensemble1",
		"syn":         "midi.lead2",
		"brs":         "midi.brass6",
		"fl":          "midi.pipe2",
		"vln":         "midi.strings1",
		"vc":          "midi.strings3",
		"cb":          "midi.strings4",
		"tp":          "midi.brass1",
		"tb":          "midi.brass2",
		"ob":          "midi.reed5",
		"cl":          "midi.reed8",
	}

	for name in map:
		_voices[name] = presets.call("get_voice_preset", map[name])

	_voices["default"] = _voices["piano"]
	print("STRUDEL: %d voices mapped" % _voices.size())


func trigger(hap: StrudelHap, deadline: float, duration: float, cps: float, target_time: float) -> void:
	## Called by the Cyclist for each hap with an onset.
	if not driver:
		return

	var note_num: int = _resolve_note(hap.value)
	if note_num < 0:
		return

	var voice: Variant = _resolve_voice(hap.value)
	var length_sec: float = maxf(duration, 0.02)

	# SiON note_on length is in 16th-note ticks at the driver's current BPM.
	# The driver BPM is set to match the cyclist's CPS (see MusicManager).
	# Conversion: ticks = duration_seconds * BPM * 4 / 60
	#   where 4 = 16th notes per beat, 60 = seconds per minute
	# If CPS = 0.5, one cycle = 2 seconds. SiON BPM = cps * 120 = 60.
	# A quarter-cycle note (0.5s) = 0.5 * 60 * 4 / 60 = 2 ticks.
	var bpm: float = maxf(cps * 120.0, 30.0)  # CPS->BPM (cps=0.5 -> 60 BPM)
	var length_ticks: float = maxf(1.0, length_sec * bpm * 4.0 / 60.0)
	driver.call("note_on", note_num, voice, length_ticks)

	DebugOverlay.log("strudel/trigger", null, "STRUDEL_TRIGGER: note=%d dur=%.3f ticks=%.1f val=%s" % [
		note_num, length_sec, length_ticks, str(hap.value)])


func _resolve_note(value: Variant) -> int:
	## Convert a hap value to a MIDI note number.
	## Handles: int, float, string ("c4"), dict with "note"/"value"/"n"/"freq" keys.
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String:
		return _note_name_to_midi(value)
	if value is Dictionary:
		# Check all possible keys where a note value might be
		for key in ["note", "value", "n"]:
			if value.has(key):
				var n: Variant = value[key]
				if n is String:
					var midi: int = _note_name_to_midi(n)
					if midi >= 0:
						return midi
				if n is int or n is float:
					return int(n)
		if value.has("freq"):
			return _freq_to_midi(float(value["freq"]))
	return -1  # Can't resolve — skip


func _resolve_voice(value: Variant) -> Variant:
	## Get the SiON voice for this hap value.
	## Checks: dict.s, dict.sound, dict.voice, or the value itself as a voice name.
	if value is Dictionary:
		for key in ["s", "sound", "voice"]:
			if value.has(key):
				var s: String = str(value[key]).to_lower()
				if _voices.has(s):
					return _voices[s]
	if value is String:
		var lower: String = value.to_lower()
		if _voices.has(lower):
			return _voices[lower]
	return _voices.get("default")


func _resolve_velocity(value: Variant) -> float:
	if value is Dictionary:
		return float(value.get("velocity", value.get("gain", 1.0)))
	return 1.0


# -- Note Name Conversion ------------------------------------------------------

const NOTE_NAMES := {
	"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11,
}

func _note_name_to_midi(name: String) -> int:
	## Convert "c4", "eb3", "f#5" etc. to MIDI number.
	## Also handles plain numbers like "60".
	name = name.strip_edges().to_lower()

	# Plain number?
	if name.is_valid_int():
		return int(name)
	if name.is_valid_float():
		return int(float(name))

	if name.is_empty():
		return -1

	# Parse note letter
	var letter: String = name[0]
	if not NOTE_NAMES.has(letter):
		return -1

	var base: int = NOTE_NAMES[letter]
	var pos: int = 1

	# Parse accidentals
	while pos < name.length():
		if name[pos] == "#" or name[pos] == "s":  # sharp
			base += 1
			pos += 1
		elif name[pos] == "b" or name[pos] == "-":  # flat
			# Careful: 'b' alone after a note letter means flat, not the note B
			if letter != "b" or pos > 1:  # only treat as flat if not the first char
				base -= 1
			else:
				break  # It's the octave number
			pos += 1
		else:
			break

	# Parse octave (default 4 if not specified)
	var octave: int = 4
	if pos < name.length():
		var oct_str: String = name.substr(pos)
		if oct_str.is_valid_int():
			octave = int(oct_str)

	return (octave + 1) * 12 + base


func _freq_to_midi(freq: float) -> int:
	## Convert frequency (Hz) to nearest MIDI note.
	if freq <= 0.0:
		return -1
	return int(roundf(12.0 * log(freq / 440.0) / log(2.0) + 69.0))
