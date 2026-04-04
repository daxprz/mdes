class_name StrudelOscillator extends RefCounted

## Pure waveform oscillator — generates audio the same way Strudel/Web Audio does.
## Replaces SiON for basic oscillator types (sine, sawtooth, square, triangle).
##
## Strudel uses Web Audio OscillatorNode which produces mathematically perfect
## waveforms. SiON uses FM synthesis which produces harmonically different output.
## This class generates the same waveforms as Web Audio for exact compatibility.

const RATE := 44100
const OSCILLATOR_TYPES := ["sine", "sawtooth", "square", "triangle"]


static func is_oscillator(voice_name: String) -> bool:
	## Returns true if this voice should use the oscillator instead of SiON.
	return voice_name.to_lower() in OSCILLATOR_TYPES


static func render_note(midi: int, duration_sec: float, waveform: String, gain: float = 0.7) -> AudioStreamWAV:
	## Render a single note as an AudioStreamWAV.
	## midi: MIDI note number (60=C4)
	## duration_sec: note length in seconds
	## waveform: sine, sawtooth, square, triangle
	## gain: amplitude 0.0-1.0
	var freq: float = 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var n_samples: int = int(RATE * duration_sec)
	var data := PackedByteArray()
	data.resize(n_samples * 2)  # 16-bit = 2 bytes per sample

	var attack_samples: int = int(RATE * 0.005)   # 5ms attack
	var release_samples: int = int(RATE * 0.010)   # 10ms release

	for i in range(n_samples):
		var t: float = float(i) / RATE
		var phase: float = fmod(freq * t, 1.0)

		# Oscillator
		var val: float = 0.0
		match waveform:
			"sine":
				val = sin(TAU * freq * t)
			"sawtooth":
				val = 2.0 * phase - 1.0
			"square":
				val = 1.0 if phase < 0.5 else -1.0
			"triangle":
				val = 4.0 * absf(phase - 0.5) - 1.0

		# Envelope (quick attack/release to avoid clicks)
		var env: float = 1.0
		if i < attack_samples:
			env = float(i) / attack_samples
		elif i > n_samples - release_samples:
			env = float(n_samples - i) / release_samples

		var sample: int = clampi(int(val * gain * env * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


static func render_cycle(haps: Array, cps: float, waveform: String = "sine", default_gain: float = 0.7, signal_controls: Array = []) -> AudioStreamWAV:
	## Render a full cycle of haps as a single looping AudioStreamWAV.
	## Each hap produces a note at the correct pitch, duration, and timing.
	## signal_controls: Array of StrudelPattern producing {lpf: value} dicts,
	## evaluated per-note to bake filtering directly into the waveform.
	var cycle_dur: float = 1.0 / cps
	var n_samples: int = int(RATE * cycle_dur)
	var buffer := PackedFloat32Array()
	buffer.resize(n_samples)
	buffer.fill(0.0)

	for hap in haps:
		if not hap.has_onset():
			continue

		var midi: int = _resolve_midi(hap.value)
		if midi < 0:
			continue
		var onset: float = hap.w().begin.to_float() if hap.whole != null else 0.0
		onset = fmod(onset, 1.0)
		if onset < 0:
			onset += 1.0
		var dur_frac: float = hap.get_duration().to_float()

		var note_start: int = int(onset * cycle_dur * RATE)
		var note_dur: float = dur_frac * cycle_dur
		var note_samples: int = int(note_dur * RATE)
		var freq: float = 440.0 * pow(2.0, (midi - 69.0) / 12.0)

		var gain: float = default_gain
		if hap.value is Dictionary:
			gain = float(hap.value.get("gain", hap.value.get("velocity", default_gain)))

		# Evaluate signal controls at this note's cycle position to get LPF cutoff etc.
		var lpf_cutoff: float = 20000.0  # Wide open by default
		for sig_pat in signal_controls:
			var sig_haps: Array = sig_pat.query_arc(onset, onset + 0.001)
			if not sig_haps.is_empty():
				var sv: Variant = sig_haps[0].value
				if sv is Dictionary and sv.has("lpf"):
					lpf_cutoff = float(sv["lpf"])

		# 1-pole IIR lowpass filter coefficient (same as Strudel reference renderer)
		var rc: float = 1.0 / (TAU * lpf_cutoff)
		var dt: float = 1.0 / RATE
		var alpha: float = dt / (rc + dt)
		var prev_filtered: float = 0.0

		var attack: int = mini(int(RATE * 0.005), note_samples / 4)
		var release: int = mini(int(RATE * 0.010), note_samples / 4)

		for i in range(note_samples):
			var idx: int = note_start + i
			if idx >= n_samples:
				break
			var t: float = float(i) / RATE
			var phase: float = fmod(freq * t, 1.0)

			var val: float = 0.0
			match waveform:
				"sine": val = sin(TAU * freq * t)
				"sawtooth": val = 2.0 * phase - 1.0
				"square": val = 1.0 if phase < 0.5 else -1.0
				"triangle": val = 4.0 * absf(phase - 0.5) - 1.0

			# Apply LPF
			var filtered: float = prev_filtered + alpha * (val - prev_filtered)
			prev_filtered = filtered

			var env: float = 1.0
			if i < attack:
				env = float(i) / maxf(attack, 1)
			elif i > note_samples - release:
				env = float(note_samples - i) / maxf(release, 1)

			buffer[idx] += filtered * gain * env

	# Convert float buffer to 16-bit PCM
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	for i in range(n_samples):
		var sample: int = clampi(int(buffer[i] * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n_samples
	return wav


static func _resolve_midi(value: Variant) -> int:
	if value is int: return value
	if value is float: return int(value)
	if value is String: return _note_to_midi(value)
	if value is Dictionary:
		for key in ["note", "value", "n"]:
			if value.has(key):
				var n: Variant = value[key]
				if n is String: return _note_to_midi(n)
				if n is int or n is float: return int(n)
	return -1


static func _note_to_midi(name: String) -> int:
	const NOTES := {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
	name = name.strip_edges().to_lower()
	if name.is_valid_int(): return int(name)
	if name.is_empty() or not NOTES.has(name[0]): return -1
	var letter: String = name[0]
	var base: int = NOTES[letter]
	var pos: int = 1
	while pos < name.length():
		if name[pos] == "#" or name[pos] == "s":
			base += 1; pos += 1
		elif name[pos] == "b" and not (letter == "b" and pos == 1):
			base -= 1; pos += 1
		elif name[pos] == "-":
			base -= 1; pos += 1
		else: break
	var octave: int = 4
	if pos < name.length() and name.substr(pos).is_valid_int():
		octave = int(name.substr(pos))
	return (octave + 1) * 12 + base
