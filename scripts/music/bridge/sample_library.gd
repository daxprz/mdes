class_name SampleLibrary extends RefCounted

## Drum sample library for Strudel pattern playback.
##
## Generates synthesized drum kit at init (bd, sd, hh, oh, cp, rim, etc.)
## using PCM math — same approach as StrudelOscillator. Also loads external
## .wav files from data/samples/<name>/ directories.
##
## Strudel patterns trigger samples via s("bd sd hh") — the voice name is
## looked up in the library and played via pooled AudioStreamPlayers.
##
## Sample playback is per-note (not pre-rendered like oscillator batch mode)
## so it supports dynamic patterns with correct onset timing.

const RATE := 44100
const MAX_PLAYERS := 16  ## Polyphony limit — oldest note is stolen

## name -> Array[AudioStreamWAV]  (multiple variations per name)
var _samples: Dictionary = {}

## Active AudioStreamPlayers (recycled when finished)
var _players: Array = []  ## Array of AudioStreamPlayer

## Node to parent players under (set via init)
var _parent: Node = null


func _init(parent: Node) -> void:
	_parent = parent
	_synthesize_kit()
	_load_external_samples()


# ==============================================================================
# Public API
# ==============================================================================

func has_sample(name: String) -> bool:
	## Returns true if this voice name is a sample (not a synth voice).
	return _samples.has(name.to_lower())


func play_sample(name: String, note: int, gain: float, _duration_sec: float) -> void:
	## Play a sample by name. If note != -1, pitch-shift relative to C4 (60).
	## gain: amplitude (0.0–1.0). duration_sec: max play time.
	var key: String = name.to_lower()
	if not _samples.has(key):
		return

	var variations: Array = _samples[key]
	if variations.is_empty():
		return

	# Pick variation: use note number modulo variations length
	var idx: int = 0
	if note >= 0 and variations.size() > 1:
		idx = note % variations.size()
	var wav: AudioStreamWAV = variations[idx]

	# Get or create a player
	var player: AudioStreamPlayer = _get_player()
	player.stream = wav
	player.volume_db = linear_to_db(clampf(gain, 0.01, 1.0))

	# Pitch shift: semitones from C4 (MIDI 60) for tonal drums,
	# or from the sample's natural pitch for melodic variation
	if note >= 0 and name in ["lt", "mt", "ht"]:
		# Toms: pitch based on note number (relative to C4)
		var semitones: float = float(note - 60) / 12.0
		player.pitch_scale = pow(2.0, semitones)
	else:
		player.pitch_scale = 1.0

	player.play()

	DebugOverlay.log("music/samples", null, "SAMPLE: play '%s' var=%d gain=%.2f pitch=%.2f" % [
		key, idx, gain, player.pitch_scale])


func stop_all() -> void:
	## Stop all active sample players.
	for player in _players:
		if player.playing:
			player.stop()


func get_sample_names() -> PackedStringArray:
	## List all available sample names.
	var names: PackedStringArray = PackedStringArray()
	for key in _samples:
		names.append(key)
	names.sort()
	return names


# ==============================================================================
# Player Pool
# ==============================================================================

func _get_player() -> AudioStreamPlayer:
	## Get an idle player from the pool, or create/steal one.
	# Try to find an idle player
	for player in _players:
		if not player.playing:
			return player

	# Create new if under limit
	if _players.size() < MAX_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
		_parent.add_child(player)
		_players.append(player)
		return player

	# Steal oldest (first in array, since we append new ones)
	var oldest: AudioStreamPlayer = _players[0]
	oldest.stop()
	return oldest


# ==============================================================================
# Drum Synthesis
# ==============================================================================

func _synthesize_kit() -> void:
	## Generate the core drum kit from PCM math.
	## Each drum is a short AudioStreamWAV with characteristic timbre.

	# Bass drum: low sine with pitch sweep (150→50 Hz), 200ms
	_samples["bd"] = [_synth_bd()]

	# Snare: noise + sine body, 150ms
	_samples["sd"] = [_synth_sd()]

	# Closed hi-hat: filtered noise, very short (50ms)
	_samples["hh"] = [_synth_hh(0.05)]

	# Open hi-hat: filtered noise, longer (300ms)
	_samples["oh"] = [_synth_hh(0.30)]

	# Clap: layered noise bursts (micro-delays), 100ms
	_samples["cp"] = [_synth_cp()]

	# Rimshot: sharp sine click at 800Hz, 30ms
	_samples["rim"] = [_synth_rim()]

	# Crash: noise with long decay, moderate HPF, 800ms
	_samples["cr"] = [_synth_crash(0.8)]

	# Ride: bright noise, shorter (400ms)
	_samples["rd"] = [_synth_crash(0.4)]

	# Low tom: pitched sine + noise, 200ms at C2
	_samples["lt"] = [_synth_tom(65.0, 0.20)]

	# Mid tom: C3
	_samples["mt"] = [_synth_tom(130.0, 0.15)]

	# High tom: C4
	_samples["ht"] = [_synth_tom(260.0, 0.12)]

	# Shaker: high-pass noise, 80ms
	_samples["sh"] = [_synth_shaker()]

	# Cowbell: two detuned square waves, 120ms
	_samples["cb"] = [_synth_cowbell()]

	var total: int = 0
	for key in _samples:
		total += _samples[key].size()
	print("SAMPLES: synthesized %d samples (%d names)" % [total, _samples.size()])


func _synth_bd() -> AudioStreamWAV:
	## Bass drum: sine wave with pitch sweep (150→50 Hz), exponential decay.
	var dur: float = 0.25
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	for i in range(n):
		var t: float = float(i) / RATE
		var env: float = exp(-t * 12.0)  # Fast exponential decay

		# Pitch sweep: 150 Hz → 50 Hz exponentially via phase accumulation
		var phase: float = 0.0
		if i > 0:
			# Approximate: integrate frequency over time
			phase = TAU * (50.0 * t + (100.0 / 30.0) * (1.0 - exp(-t * 30.0)))
		var val: float = sin(phase) * env * 0.9

		# Slight click at attack
		if i < int(RATE * 0.002):
			val += 0.3 * (1.0 - float(i) / (RATE * 0.002))

		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))

	return _make_wav(data, n)


func _synth_sd() -> AudioStreamWAV:
	## Snare drum: sine body (200 Hz) + white noise, exponential decay.
	var dur: float = 0.18
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # Deterministic for consistency

	for i in range(n):
		var t: float = float(i) / RATE
		var env: float = exp(-t * 20.0)

		# Sine body
		var body: float = sin(TAU * 200.0 * t) * 0.4

		# Noise (snare wires)
		var noise: float = (rng.randf() * 2.0 - 1.0) * 0.6

		# HPF the noise slightly (1-pole, cutoff ~2kHz)
		var val: float = (body + noise) * env

		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))

	return _make_wav(data, n)


func _synth_hh(dur: float) -> AudioStreamWAV:
	## Hi-hat: high-pass filtered noise with exponential decay.
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 123

	# 1-pole HPF at ~7kHz
	var rc: float = 1.0 / (TAU * 7000.0)
	var dt: float = 1.0 / RATE
	var alpha: float = rc / (rc + dt)
	var prev_hpf: float = 0.0
	var prev_input: float = 0.0

	for i in range(n):
		var t: float = float(i) / RATE
		var env: float = exp(-t * (40.0 if dur < 0.1 else 8.0))

		var raw: float = rng.randf() * 2.0 - 1.0
		prev_hpf = alpha * (prev_hpf + raw - prev_input)
		prev_input = raw

		var val: float = prev_hpf * env * 0.5
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))

	return _make_wav(data, n)


func _synth_cp() -> AudioStreamWAV:
	## Clap: layered noise micro-bursts with gaps, simulating hand clap.
	var dur: float = 0.12
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 77

	# 3 micro-bursts at 0ms, 15ms, 25ms — each ~5ms long
	var bursts := [0.0, 0.015, 0.025]
	var burst_dur: float = 0.005

	# BPF around 1.5kHz
	var rc: float = 1.0 / (TAU * 1500.0)
	var dt_val: float = 1.0 / RATE
	var lp_alpha: float = dt_val / (rc + dt_val)
	var hp_rc: float = 1.0 / (TAU * 800.0)
	var hp_alpha: float = hp_rc / (hp_rc + dt_val)
	var prev_lp: float = 0.0
	var prev_hp: float = 0.0
	var prev_hp_in: float = 0.0

	for i in range(n):
		var t: float = float(i) / RATE
		var val: float = 0.0

		# Check if we're in a burst
		for burst_start in bursts:
			if t >= burst_start and t < burst_start + burst_dur:
				val += rng.randf() * 2.0 - 1.0
		# Plus a tail of noise
		if t > 0.03:
			val += (rng.randf() * 2.0 - 1.0) * 0.4

		# BPF: LPF then HPF
		prev_lp = prev_lp + lp_alpha * (val - prev_lp)
		prev_hp = hp_alpha * (prev_hp + prev_lp - prev_hp_in)
		prev_hp_in = prev_lp

		var env: float = 1.0 if t < 0.03 else exp(-(t - 0.03) * 25.0)
		var out: float = prev_hp * env * 0.6

		data.encode_s16(i * 2, clampi(int(out * 32767.0), -32768, 32767))

	return _make_wav(data, n)


func _synth_rim() -> AudioStreamWAV:
	## Rimshot: sharp sine click at ~800Hz, very short.
	var dur: float = 0.03
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	for i in range(n):
		var t: float = float(i) / RATE
		var env: float = exp(-t * 150.0)  # Very fast decay
		var val: float = sin(TAU * 800.0 * t) * env * 0.7

		# Add a sharp transient at the start
		if i < int(RATE * 0.001):
			val += 0.5 * (1.0 - float(i) / (RATE * 0.001))

		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))

	return _make_wav(data, n)


func _synth_crash(dur: float) -> AudioStreamWAV:
	## Crash/ride: white noise with slow decay, moderate HPF.
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 200 + int(dur * 100)

	# HPF at ~3kHz
	var rc: float = 1.0 / (TAU * 3000.0)
	var dt: float = 1.0 / RATE
	var alpha: float = rc / (rc + dt)
	var prev_hpf: float = 0.0
	var prev_input: float = 0.0

	for i in range(n):
		var t: float = float(i) / RATE
		var env: float = exp(-t * (3.0 if dur > 0.5 else 6.0))

		var raw: float = rng.randf() * 2.0 - 1.0
		prev_hpf = alpha * (prev_hpf + raw - prev_input)
		prev_input = raw

		# Add some metallic resonance (two detuned sines)
		var metallic: float = (sin(TAU * 3200.0 * t) + sin(TAU * 4800.0 * t)) * 0.15

		var val: float = (prev_hpf + metallic) * env * 0.45
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))

	return _make_wav(data, n)


func _synth_tom(base_freq: float, dur: float) -> AudioStreamWAV:
	## Tom: pitched sine with slight pitch drop + noise body.
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(base_freq)

	for i in range(n):
		var t: float = float(i) / RATE
		var env: float = exp(-t * 15.0)

		# Pitch drops slightly over duration (via phase integral)
		var phase: float = TAU * (base_freq * t + (base_freq * 0.3 / 25.0) * (1.0 - exp(-t * 25.0)))

		var body: float = sin(phase) * 0.7
		var noise: float = (rng.randf() * 2.0 - 1.0) * 0.15

		var val: float = (body + noise) * env * 0.7
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))

	return _make_wav(data, n)


func _synth_shaker() -> AudioStreamWAV:
	## Shaker: band-pass noise, short and bright.
	var dur: float = 0.08
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 333

	# BPF around 5kHz
	var rc_lp: float = 1.0 / (TAU * 8000.0)
	var dt: float = 1.0 / RATE
	var lp_alpha: float = dt / (rc_lp + dt)
	var hp_rc: float = 1.0 / (TAU * 3000.0)
	var hp_alpha: float = hp_rc / (hp_rc + dt)
	var prev_lp: float = 0.0
	var prev_hp: float = 0.0
	var prev_hp_in: float = 0.0

	for i in range(n):
		var t: float = float(i) / RATE
		var env: float = exp(-t * 30.0)

		var raw: float = rng.randf() * 2.0 - 1.0
		prev_lp = prev_lp + lp_alpha * (raw - prev_lp)
		prev_hp = hp_alpha * (prev_hp + prev_lp - prev_hp_in)
		prev_hp_in = prev_lp

		var val: float = prev_hp * env * 0.5
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))

	return _make_wav(data, n)


func _synth_cowbell() -> AudioStreamWAV:
	## Cowbell: two detuned square waves at ~560Hz and ~845Hz.
	var dur: float = 0.12
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)

	for i in range(n):
		var t: float = float(i) / RATE
		var env: float = exp(-t * 18.0)

		var sq1: float = 1.0 if fmod(560.0 * t, 1.0) < 0.5 else -1.0
		var sq2: float = 1.0 if fmod(845.0 * t, 1.0) < 0.5 else -1.0

		# BPF: simple LPF to remove harsh edges
		var val: float = (sq1 + sq2) * 0.25 * env

		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))

	return _make_wav(data, n)


# ==============================================================================
# External Sample Loading
# ==============================================================================

func _load_external_samples() -> void:
	## Load .wav and .ogg files from data/samples/<name>/ directories.
	## Each subdirectory becomes a sample name; files become variations.
	var base_path: String = "res://data/samples"
	if not DirAccess.dir_exists_absolute(base_path):
		return

	var dir := DirAccess.open(base_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	var loaded_count: int = 0

	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var sample_name: String = entry.to_lower()
			var sample_dir: String = base_path + "/" + entry
			var variations: Array = _load_sample_dir(sample_dir)
			if not variations.is_empty():
				# External samples override synthesized ones
				_samples[sample_name] = variations
				loaded_count += variations.size()
		entry = dir.get_next()
	dir.list_dir_end()

	if loaded_count > 0:
		print("SAMPLES: loaded %d external samples" % loaded_count)


func _load_sample_dir(dir_path: String) -> Array:
	## Load all .wav/.ogg files from a directory as AudioStream variations.
	var variations: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return variations

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	var files: PackedStringArray = PackedStringArray()

	while entry != "":
		if not dir.current_is_dir():
			var ext: String = entry.get_extension().to_lower()
			if ext in ["wav", "ogg", "mp3"]:
				files.append(dir_path + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()

	files.sort()  # Consistent ordering

	for file_path in files:
		var stream: Variant = load(file_path)
		if stream != null:
			# Convert to AudioStreamWAV if needed (for consistency)
			if stream is AudioStreamWAV:
				variations.append(stream)
			else:
				# Keep as-is — AudioStreamOggVorbis, AudioStreamMP3
				variations.append(stream)

	return variations


# ==============================================================================
# Helpers
# ==============================================================================

func _make_wav(data: PackedByteArray, _n_samples: int) -> AudioStreamWAV:
	## Create a one-shot AudioStreamWAV from PCM data.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	# No loop — drums are one-shot
	return wav
