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
	# Default melodic voice
	_voices["default"] = presets.call("get_voice_preset", "midi.piano1")
	_voices["piano"] = presets.call("get_voice_preset", "midi.piano1")
	_voices["bass"] = presets.call("get_voice_preset", "midi.bass7")
	_voices["lead"] = presets.call("get_voice_preset", "midi.lead2")
	_voices["pad"] = presets.call("get_voice_preset", "midi.pad2")
	_voices["organ"] = presets.call("get_voice_preset", "midi.organ3")
	_voices["strings"] = presets.call("get_voice_preset", "midi.strings1")
	_voices["sawtooth"] = presets.call("get_voice_preset", "midi.lead2")
	_voices["square"] = presets.call("get_voice_preset", "midi.lead1")


func trigger(hap: StrudelHap, deadline: float, duration: float, cps: float, target_time: float) -> void:
	## Called by the Cyclist for each hap with an onset.
	if not driver:
		return

	var note_num: int = _resolve_note(hap.value)
	if note_num < 0:
		return

	var voice: Variant = _resolve_voice(hap.value)
	var length: float = maxf(duration, 0.05)

	# SiONDriver.note_on(note, voice, length, delay, quantize, track_id, disposable)
	# Use only the required params and let SiON use defaults for the rest
	# voice can be null to use default
	if voice != null:
		driver.call("note_on", note_num, voice)
	else:
		driver.call("note_on", note_num)

	DebugOverlay.log("strudel/trigger", null, "STRUDEL_TRIGGER: note=%d dur=%.3f val=%s" % [
		note_num, length, str(hap.value)])


func _resolve_note(value: Variant) -> int:
	## Convert a hap value to a MIDI note number.
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String:
		return _note_name_to_midi(value)
	if value is Dictionary:
		# Check for 'note', 'n', 'freq' keys (Strudel control format)
		if value.has("note"):
			var n: Variant = value["note"]
			if n is String:
				return _note_name_to_midi(n)
			if n is int or n is float:
				return int(n)
		if value.has("n"):
			return int(value["n"])
		if value.has("freq"):
			return _freq_to_midi(float(value["freq"]))
	return -1  # Can't resolve — skip


func _resolve_voice(value: Variant) -> Variant:
	## Get the SiON voice for this hap value.
	if value is Dictionary:
		var s: String = str(value.get("s", value.get("sound", "")))
		if _voices.has(s):
			return _voices[s]
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
