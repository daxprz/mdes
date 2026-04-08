class_name StrudelSionTrigger extends RefCounted

## Bridges Strudel hap events to GDSiON note_on/note_off calls.
## Converts pattern values (note names, MIDI numbers, frequencies)
## to SiON driver calls.

const BATCH_RENDER_CYCLES := 16  ## Number of cycles pre-rendered for oscillator batch mode

var driver: Variant = null     ## SiONDriver (dynamic to avoid parse-time dep)
var presets: Variant = null     ## SiONVoicePresetUtil
var _voices: Dictionary = {}   ## name -> SiONVoice
var batch_cycle_count: int = 1 ## Actual cycles in current batch WAV (set by start_batch_from_tracks)
var _active_notes: Dictionary = {} ## voice_name -> Array[int] of active note numbers

## Sample library for drum/percussion playback (PCM-synthesized + external .wav)
var _sample_library: SampleLibrary = null


func _init(p_driver: Variant, p_presets: Variant) -> void:
	driver = p_driver
	presets = p_presets
	_setup_voices()
	_batch_compiler = MmlBatchCompiler.new(self)


func init_sample_library(parent: Node) -> void:
	## Create the sample library (must be called after constructor since we need a Node parent).
	_sample_library = SampleLibrary.new(parent)


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
		"sine":        "midi.lead1",    # Square is closest to pure sine in FM
		"triangle":    "midi.lead1",    # Triangle ≈ square with softer harmonics
		"supersaw":    "midi.lead2",    # Supersaw ≈ detuned saw
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
		# -- Strudel oscillator types --
		# These match Web Audio OscillatorNode type names
		# used in Strudel's s("sawtooth") etc.
		# Already mapped above: sawtooth, square, sine, triangle, supersaw
		# -- Strudel drum sample names --
		# Standard dirt-samples names used in Strudel: s("bd"), s("sd"), etc.
		# Mapped to the closest SiON percussion/drum preset
		"bd":          "midi.strings8",  # Timpani as bass drum proxy
		"sd":          "midi.strings6",  # Pizzicato as snare proxy
		"hh":          "midi.chrom2",    # Glockenspiel as hi-hat proxy
		"cp":          "midi.guitar8",   # Guitar harmonics as clap proxy
		"rim":         "midi.chrom6",    # Xylophone as rim proxy
		"rd":          "midi.chrom7",    # Tubular bells as ride proxy
		"cr":          "midi.ensemble8", # Orchestra hit as crash proxy
		"lt":          "midi.strings8",  # Timpani as low tom proxy
		"mt":          "midi.strings8",  # Timpani as mid tom proxy
		"ht":          "midi.chrom5",    # Marimba as high tom proxy
	}

	for name in map:
		_voices[name] = presets.call("get_voice_preset", map[name])

	# Create pure waveform voices using correct SiON module types.
	# GDSiON SiONModuleType enum (0-based, from binary inspection):
	#   0 = MODULE_PSG     — PSG square wave
	#   1 = MODULE_APU     — NES APU (NOT general PSG!)
	#   6 = MODULE_FM      — FM synthesis (OPM-style)
	#   8 = MODULE_PULSE   — Pulse wave with duty cycle
	#   9 = MODULE_RAMP    — Ramp/saw/triangle
	# For set_module_type(module, channel):
	#   MODULE_RAMP(9): channel selects ramp shape
	#   MODULE_PSG(0): channel selects wave table index
	var _bridge: GDScript = GDScript.new()
	_bridge.source_code = """extends RefCounted

func make_voice(module_type: int, channel: int) -> SiONVoice:
	var v := SiONVoice.new()
	v.set_module_type(module_type, channel)
	return v
"""
	if _bridge.reload() == OK:
		var helper = _bridge.new()
		# Sawtooth: MODULE_RAMP (9), channel 0 = ramp/saw wave
		_voices["sawtooth"] = helper.make_voice(9, 0)
		_voices["saw"] = _voices["sawtooth"]
		# Triangle: MODULE_RAMP (9), channel 2 (triangle variant)
		# Or try PSG(0) ch 2 if RAMP doesn't have triangle
		_voices["triangle"] = helper.make_voice(9, 2)
		# Square: MODULE_PSG (0), channel 0 = square
		_voices["square"] = helper.make_voice(0, 0)
		# Sine: MODULE_PSG (0) with wave table — try ch 0 or use FM
		# PSG ch0 is square, so for sine use MODULE_FM (6) with zero modulation
		_voices["sine"] = helper.make_voice(6, 0)
		print("STRUDEL: voices — saw=RAMP(9,0) tri=RAMP(9,2) sq=PSG(0,0) sin=FM(6,0)")
	else:
		print("STRUDEL: voice bridge failed, using FM fallback")

	_voices["default"] = _voices["piano"]
	print("STRUDEL: %d voices mapped" % _voices.size())


## Audio control keys that the trigger extracts from hap values
## and forwards to MusicManager.set_music_effects() per-note.
const EFFECT_KEYS := [
	"lpf", "hpf", "lpq", "hpq",
	"room", "roomsize", "roomlp",
	"delay", "delaytime", "delayfeedback",
	"distort", "crush", "shape",
	"pan",
	# NOTE: "gain" and "velocity" are intentionally NOT here.
	# They are per-note properties handled by _resolve_velocity(), not bus effects.
	# Routing them to set_music_effects() would cause the bus amplifier to bounce
	# between different track gains on every note trigger.
]
## Per-note ADSR keys — these are NOT bus effects, they modify the SiON voice
## envelope on a per-note basis. Extracted in _do_emit, not set_music_effects.
const ADSR_KEYS := ["attack", "att", "decay", "dec", "sustain", "sus", "release", "rel"]

## Last-applied effect controls — used for change detection.
## Only calls set_music_effects() when the values actually differ,
## avoiding redundant AudioServer updates every trigger.
var _last_fx: Dictionary = {}

## Signal control patterns evaluated per-note at trigger time.
## Array of StrudelPattern, each producing {control_key: value} dicts.
var _signal_controls: Array = []

## Scheduling mode: "note" = per-note frame-dispatch, "batch" = MML batch compilation.
## Batch mode is the default — sample-accurate timing via SiON's internal sequencer.
var batch_mode: bool = true

## MML batch compiler — converts hap arrays to MML strings for sequence_on.
var _batch_compiler: MmlBatchCompiler = null

## AudioStreamPlayer for oscillator-based playback (bypasses SiON)
var _osc_player: AudioStreamPlayer = null

## Active sequence tracks from batch mode: { track_key: track_id }
var _active_tracks: Dictionary = {}

## Track ID counter for batch sequences (starts high to avoid collision with layer tracks)
var _batch_track_base: int = 100

## Cycle buffer: accumulate haps until a full cycle boundary is reached, then compile.
## The cyclist delivers haps in small tick windows (~50ms); we need a full cycle to
## produce compact per-voice MML with proper inter-note timing.
var _cycle_buffer: Array = []
var _cycle_buffer_int: int = -1   ## Which cycle integer the buffer is for
var _last_batch_cps: float = 0.5  ## CPS at time of buffering

## Deferred note queue: the cyclist dispatches haps into a lookahead window
## (50ms tick + 100ms overlap = up to 150ms early). Instead of firing note_on
## immediately, we enqueue notes and emit them at the correct wall-clock time.
## process() is called each frame from MusicManager._process().
var _pending_notes: Array[Dictionary] = []

## Timing instrumentation — records actual note_on wall-clock times
## for comparison against theoretical schedule. Enabled by setting
## timing_log = true (via RCON: strudel timing on).
var timing_log: bool = false
var _timing_records: Array[Dictionary] = []  ## [{note, actual_ms, target_ms, deadline_ms, cycle_pos, delta_ms}]
var _timing_start_ms: float = 0.0            ## Wall-clock reference (Time.get_ticks_msec at first note)


func trigger(hap: StrudelHap, deadline: float, duration: float, cps: float, target_time: float) -> void:
	## Called by the Cyclist for each hap with an onset.
	## Does NOT fire note_on immediately — enqueues the note for deferred
	## emission at the correct wall-clock time via process().
	if not driver:
		return

	var note_num: int = _resolve_note(hap.value)

	# For sample voices, note_num -1 is OK (drums don't need a pitch).
	# For SiON voices, we must have a valid MIDI note.
	var voice_name_check: String = _resolve_voice_name(hap.value)
	var is_sample: bool = _sample_library != null and _sample_library.has_sample(voice_name_check)
	if note_num < 0 and not is_sample:
		return

	var voice: Variant = _resolve_voice(hap.value)

	# Apply legato (stored as "clip" in hap value) to note duration.
	# Without this, all notes get their raw hap span which is often tiny.
	var legato: float = 1.0
	if hap.value is Dictionary and hap.value.has("clip"):
		legato = float(hap.value["clip"])
	var length_sec: float = maxf(duration * legato, 0.02)

	# SiON note_on length is in 64th-note ticks at the driver's current BPM.
	# (Empirically verified: 8 ticks at 60 BPM = 514ms ≈ 64ms/tick = 64th note)
	var bpm: float = maxf(cps * 120.0, 30.0)
	var length_ticks: float = maxf(2.0, length_sec * bpm * 16.0 / 60.0)

	# Compute wall-clock emit time from the absolute target_time.
	# deadline = target_time - phase (clock's virtual tick time, NOT wall-clock now).
	# We must translate to wall-clock: how many strudel-seconds until target_time,
	# then convert to wall-clock milliseconds.
	var strudel_now: float = MusicManager._strudel_time
	var wait_sec: float = target_time - strudel_now
	var now_ms: float = Time.get_ticks_msec()
	var emit_at_ms: float = now_ms + wait_sec * 1000.0

	if wait_sec <= 0.003:
		# 3ms or less — fire immediately (already late or on-time)
		_emit_note(note_num, voice, length_ticks, hap.value, target_time, hap)
	else:
		# Defer: enqueue for later emission
		_pending_notes.append({
			"emit_at_ms": emit_at_ms,
			"note_num": note_num,
			"voice": voice,
			"length_ticks": length_ticks,
			"hap_value": hap.value,
			"target_time": target_time,
			"cycle_pos": hap.w().begin.to_float() if hap.whole != null else 0.0,
		})


func process() -> void:
	## Called every frame from MusicManager._process().
	## Fires any notes whose deadline has arrived.
	if _pending_notes.is_empty():
		return

	var now_ms: float = Time.get_ticks_msec()
	var i: int = 0
	while i < _pending_notes.size():
		if _pending_notes[i]["emit_at_ms"] <= now_ms:
			var p: Dictionary = _pending_notes[i]
			_emit_note_deferred(p)
			_pending_notes.remove_at(i)
		else:
			i += 1


func clear_pending() -> void:
	## Clear the deferred note queue (called on stop/pattern change).
	_pending_notes.clear()


func silence_all() -> void:
	## Kill all currently sounding notes by sending note_off for the full range.
	## Called on section transitions to prevent note bleed across movements.
	if driver:
		for n in range(128):
			driver.call("note_off", n)
	clear_pending()


# ==============================================================================
# Batch Mode: MML Compilation → sequence_on
# ==============================================================================

var _batch_dispatched: bool = false  ## True once the looping MML has been compiled and dispatched
var _last_batch_cycle: int = -1     ## Last cycle rendered in trigger_batch (for per-cycle re-render)
var _pending_batch_haps: Array = [] ## Accumulated haps for current cycle (rendered at boundary)

func trigger_batch(haps: Array, cps: float, cycle_begin: float, cycle_end: float) -> void:
	## In batch mode, the cyclist still calls this per-tick but we ignore it.
	## The actual rendering happens in start_batch_from_tracks which pre-renders
	## multiple cycles to handle time-dependent patterns like degrade.
	pass



func start_batch_from_tracks(tracks: Array, cps: float) -> void:
	## Compile multiple independent tracks into a multi-track MML string.
	## Each track has: {pattern, voice, gain, name}
	## This avoids set_in fragmentation by querying each pattern separately.
	if not driver or not _batch_compiler:
		return

	# Stop any current playback before starting new
	driver.call("stop")
	MusicManager._sion_streaming = false

	# BPM = 240 * CPS: 1 cycle = 1 whole note = 4 beats = 240/BPM seconds = 1/CPS seconds.
	var bpm: int = maxi(30, int(240.0 * cps))
	var mml_parts: Array[String] = []
	var total_notes: int = 0

	# Pre-render N cycles for oscillator tracks to handle time-dependent patterns
	# (like degrade) that produce different notes each cycle.
	batch_cycle_count = BATCH_RENDER_CYCLES
	var osc_groups: Dictionary = {}  # waveform_name -> {haps: [], gain: float}

	for track in tracks:
		var pat: StrudelPattern = track["pattern"]
		var voice_name: String = track.get("voice", "")
		var gain: float = track.get("gain", 1.0)

		# Query N cycles to capture time-dependent variation
		var all_onset_haps: Array = []
		for cycle_i in range(BATCH_RENDER_CYCLES):
			var haps: Array = pat.query_arc(float(cycle_i), float(cycle_i + 1))
			for hap in haps:
				if hap.has_onset():
					all_onset_haps.append(hap)
		if all_onset_haps.is_empty():
			continue

		all_onset_haps.sort_custom(MmlBatchCompiler._sort_by_onset)

		# Route: sample voices play per-note via sample library (skip MML/oscillator)
		var use_sample: bool = _sample_library != null and _sample_library.has_sample(voice_name)
		if use_sample:
			# Samples are played per-note via the cyclist's trigger() → _do_emit() path.
			# In batch mode, we pre-schedule them here instead.
			_schedule_batch_samples(all_onset_haps, cps, gain)
			total_notes += all_onset_haps.size()
			DebugOverlay.log("music/batch", null, "BATCH: track '%s' → samples (%d notes)" % [
				track.get("name", "?"), all_onset_haps.size()])
			continue

		# Route: oscillator types (or default/no voice) bypass SiON entirely
		var use_osc: bool = voice_name.is_empty() or StrudelOscillator.is_oscillator(voice_name)
		if use_osc:
			# Group haps by per-note voice (from hap.value.s) or track voice
			for hap in all_onset_haps:
				var hap_voice: String = voice_name
				if hap_voice.is_empty() and hap.value is Dictionary:
					hap_voice = str(hap.value.get("s", ""))
				if hap_voice.is_empty():
					hap_voice = "sine"
				hap_voice = hap_voice.to_lower()
				if not osc_groups.has(hap_voice):
					osc_groups[hap_voice] = {"haps": [], "gain": gain}
				osc_groups[hap_voice]["haps"].append(hap)
			total_notes += all_onset_haps.size()
			DebugOverlay.log("music/batch", null, "BATCH: track '%s' → oscillator (%d notes across %d cycles, %d voice groups)" % [
				track.get("name", "?"), all_onset_haps.size(), BATCH_RENDER_CYCLES, osc_groups.size()])
			continue

		# SiON path: build MML (uses cycle-0 haps only — MML loops)
		var c0_haps: Array = pat.query_arc(0.0, 1.0)
		var c0_onset: Array = []
		for hap in c0_haps:
			if hap.has_onset():
				c0_onset.append(hap)
		c0_onset.sort_custom(MmlBatchCompiler._sort_by_onset)
		var mml: String = _batch_compiler._haps_to_mml(c0_onset, bpm)
		if mml.is_empty():
			continue
		if not voice_name.is_empty() and MmlBatchCompiler.VOICE_TO_MML.has(voice_name.to_lower()):
			mml = mml.replace("t%d " % bpm, "t%d %s " % [bpm, MmlBatchCompiler.VOICE_TO_MML[voice_name.to_lower()]])
		if gain < 0.99:
			var vol: int = clampi(int(gain * 15.0), 0, 15)
			mml = mml.replace("t%d " % bpm, "t%d v%d " % [bpm, vol])
		mml_parts.append(mml)
		total_notes += c0_onset.size()
		DebugOverlay.log("music/batch", null, "BATCH: track '%s' → SiON MML (%d notes)" % [
			track.get("name", "?"), c0_onset.size()])

	# Play oscillator tracks via AudioStreamPlayer (pure waveforms)
	# Each voice group gets its own render, then they're mixed together.
	if not osc_groups.is_empty():
		var mixed_wav: AudioStreamWAV = null
		for waveform in osc_groups:
			var group: Dictionary = osc_groups[waveform]
			var wav: AudioStreamWAV = StrudelOscillator.render_cycle(
				group["haps"], cps, waveform, group["gain"], _signal_controls, BATCH_RENDER_CYCLES)
			if mixed_wav == null:
				mixed_wav = wav
			else:
				# Mix: add samples from wav into mixed_wav
				var mix_data := mixed_wav.data
				var add_data := wav.data
				var len_samples: int = mini(mix_data.size() / 2, add_data.size() / 2)
				for s_i in range(len_samples):
					var existing: int = mix_data.decode_s16(s_i * 2)
					var adding: int = add_data.decode_s16(s_i * 2)
					var combined: int = clampi(existing + adding, -32768, 32767)
					mix_data.encode_s16(s_i * 2, combined)
				mixed_wav.data = mix_data
			DebugOverlay.log("music/batch", null, "BATCH: oscillator group '%s' (%d notes)" % [waveform, group["haps"].size()])
		if mixed_wav != null:
			_play_oscillator(mixed_wav)
			DebugOverlay.log("music/batch", null, "BATCH: oscillator playing (%d voice groups)" % osc_groups.size())

	# Play SiON tracks via driver.play()
	if not mml_parts.is_empty():
		var full_mml: String = ";".join(PackedStringArray(mml_parts))
		DebugOverlay.log("music/batch", null, "BATCH: SiON playing (%d tracks, mml=%s)" % [mml_parts.size(), full_mml.substr(0, 80)])
		driver.call("play", full_mml)
	elif osc_groups.is_empty():
		DebugOverlay.log("music/batch", null, "BATCH: nothing to play")
	_batch_dispatched = true


func _schedule_batch_samples(haps: Array, cps: float, gain: float) -> void:
	## Schedule sample playback for batch mode. Samples are one-shot and don't loop,
	## so we use a Timer-based approach: compute onset times and queue them.
	## For short patterns, this provides correct timing with the cyclist.
	if not _sample_library:
		return

	var cycle_dur: float = 1.0 / cps
	for hap in haps:
		var voice_name: String = _resolve_voice_name(hap.value)
		if not _sample_library.has_sample(voice_name):
			continue
		var note_num: int = _resolve_note(hap.value)
		var onset: float = hap.w().begin.to_float() if hap.whole != null else 0.0
		var dur: float = hap.get_duration().to_float() * cycle_dur

		# Merge track-level gain into hap value so _do_emit sees it
		var hap_value: Variant = hap.value
		if gain < 0.99 and hap_value is Dictionary:
			hap_value = hap_value.duplicate()
			hap_value["gain"] = float(hap_value.get("gain", 1.0)) * gain

		# For batch mode, we fire samples immediately at their onset offset.
		# The cyclist handles cycling — we just need onset-relative scheduling.
		# Wrap onset to [0, batch_cycle_count) and compute delay.
		var onset_sec: float = fmod(onset, float(BATCH_RENDER_CYCLES)) * cycle_dur
		# Queue via the pending notes mechanism (same deferred dispatch)
		var now_ms: float = Time.get_ticks_msec()
		_pending_notes.append({
			"emit_at_ms": now_ms + onset_sec * 1000.0,
			"note_num": note_num,
			"voice": null,  # null voice — sample path in _do_emit
			"length_ticks": dur * 4.0,  # Approximate
			"hap_value": hap_value,
			"target_time": onset_sec,
			"cycle_pos": onset,
		})


func start_batch_playback(pattern: StrudelPattern, cps: float) -> void:
	## Eagerly query one full cycle from the pattern, compile to looping MML,
	## and play() once. SiON handles all repetitions internally at sample precision.
	## Called directly from strudel_play() — no buffering, no cyclist dependency.
	if not driver or not _batch_compiler:
		return

	# Query all haps for cycle 0 (one full cycle)
	var haps: Array = pattern.query_arc(0.0, 1.0)
	var onset_haps: Array = []
	for hap in haps:
		if hap.has_onset():
			onset_haps.append(hap)

	if onset_haps.is_empty():
		DebugOverlay.log("music/batch", null, "BATCH: no onset haps in cycle 0")
		return

	# Debug: show hap count and first few values+timing
	DebugOverlay.log("music/batch", null, "BATCH: %d onset haps for cycle 0" % onset_haps.size())
	for j in range(mini(onset_haps.size(), 6)):
		var h: StrudelHap = onset_haps[j]
		var w_str: String = "%s→%s" % [h.w().begin.show(), h.w().end.show()] if h.whole != null else "null"
		DebugOverlay.log("music/batch", null, "BATCH: hap[%d] whole=%s value=%s" % [j, w_str, str(h.value).substr(0, 60)])

	# Compile and play
	_compile_and_play(onset_haps, cps)
	_batch_dispatched = true

	# Apply bus effects from hap controls
	_apply_batch_effects(onset_haps)


func _compile_and_play(haps: Array, cps: float) -> void:
	## Compile haps into looping MML and play via driver.play().
	## Multiple voice groups are joined with semicolons (MML multi-track).
	if haps.is_empty():
		return

	var compiled: Dictionary = _batch_compiler.compile_cycle(haps, cps)
	if compiled.is_empty():
		DebugOverlay.log("music/batch", null, "BATCH: compile_cycle returned empty")
		return

	# Stop any current playback
	driver.call("stop")
	MusicManager._sion_streaming = false

	# Join all voice group MML strings with semicolons (SiON multi-track).
	var mml_parts: Array[String] = []
	var total_notes: int = 0
	for track_key in compiled:
		var entry: Dictionary = compiled[track_key]
		mml_parts.append(entry["mml"])
		total_notes += entry["notes"]

	var full_mml: String = ";".join(PackedStringArray(mml_parts))
	DebugOverlay.log("music/batch", null, "BATCH: play %d voices, %d notes, mml=%s" % [compiled.size(), total_notes, full_mml.substr(0, 100)])
	driver.call("play", full_mml)

	DebugOverlay.log("music/batch", null, "BATCH: playing — %d voices, %d notes" % [
		compiled.size(), total_notes])


## Tracks from previous cycles that should be retired (stopped after they finish)
var _retiring_tracks: Array[int] = []

func _retire_old_tracks() -> void:
	## Stop tracks from 2+ cycles ago, move current tracks to retiring.
	for tid in _retiring_tracks:
		driver.call("sequence_off", tid, 0, 0, true)
	_retiring_tracks.clear()
	# Move current active tracks to retiring (they'll be stopped next cycle)
	for track_key in _active_tracks:
		_retiring_tracks.append(_active_tracks[track_key])
	_active_tracks.clear()


func _play_oscillator(wav: AudioStreamWAV) -> void:
	## Play a rendered oscillator WAV via AudioStreamPlayer on the Music bus.
	if _osc_player:
		_osc_player.stop()
		_osc_player.queue_free()
		_osc_player = null
	_osc_player = AudioStreamPlayer.new()
	_osc_player.stream = wav
	_osc_player.bus = MusicManager.MUSIC_BUS_NAME if MusicManager._music_bus_idx > 0 else "Master"
	MusicManager.add_child(_osc_player)
	_osc_player.play()


func stop_oscillator() -> void:
	## Stop the oscillator player immediately.
	if _osc_player:
		_osc_player.stop()
		# Free immediately, not deferred — prevents bleed into next test
		if _osc_player.get_parent():
			_osc_player.get_parent().remove_child(_osc_player)
		_osc_player.free()
		_osc_player = null


func stop_all_sequences() -> void:
	## Stop all active batch-mode sequence tracks, oscillator, samples, and clear buffers.
	stop_oscillator()
	if _sample_library:
		_sample_library.stop_all()
	DebugOverlay.log("music/batch", null, "BATCH_DBG: stop_all_sequences (active=%d, retiring=%d, streaming=%s)" % [
		_active_tracks.size(), _retiring_tracks.size(), str(MusicManager._sion_streaming)])
	if MusicManager._sion_streaming and driver:
		for track_key in _active_tracks:
			var track_id: int = _active_tracks[track_key]
			DebugOverlay.log("music/batch", null, "BATCH_DBG: sequence_off track=%d" % track_id)
			driver.call("sequence_off", track_id, 0, 0, true)
		for tid in _retiring_tracks:
			driver.call("sequence_off", tid, 0, 0, true)
	_active_tracks.clear()
	_retiring_tracks.clear()
	_cycle_buffer.clear()
	_cycle_buffer_int = -1
	_batch_dispatched = false
	_last_batch_cycle = -1
	_pending_batch_haps.clear()


func _apply_batch_effects(haps: Array) -> void:
	## Extract audio controls from haps and apply bus effects once per batch.
	var merged: Dictionary = {}
	for hap in haps:
		if hap.value is Dictionary:
			for key in EFFECT_KEYS:
				if hap.value.has(key):
					merged[key] = float(hap.value[key])

	if merged.is_empty():
		if not _last_fx.is_empty():
			MusicManager.reset_music_effects()
			_last_fx.clear()
	elif merged != _last_fx:
		MusicManager.set_music_effects(merged)
		_last_fx = merged.duplicate()


func _emit_note(note_num: int, voice: Variant, length_ticks: float,
				hap_value: Variant, target_time: float, hap: Variant) -> void:
	## Fire note_on immediately (for notes with deadline <= 0).
	var cycle_pos: float = hap.w().begin.to_float() if hap != null and hap is StrudelHap and hap.whole != null else 0.0
	_do_emit(note_num, voice, length_ticks, hap_value, target_time, cycle_pos)


func _emit_note_deferred(p: Dictionary) -> void:
	## Fire a note from the deferred queue.
	_do_emit(p["note_num"], p["voice"], p["length_ticks"],
			 p["hap_value"], p["target_time"], p["cycle_pos"])


static func _seconds_to_rate(seconds: float) -> int:
	## Convert Strudel ADSR time (seconds) to SiON envelope rate (0-63).
	## SiON: 63 = instant, 0 = slowest (~10s). Logarithmic mapping.
	if seconds <= 0.001:
		return 63  # Instant
	if seconds >= 6.0:
		return 1   # Very slow
	# Logarithmic curve: rate = 63 - log2(1 + seconds * 8) * 8
	var rate: int = 63 - int(log(1.0 + seconds * 8.0) / log(2.0) * 8.0)
	return clampi(rate, 1, 63)


func _do_emit(note_num: int, voice: Variant, length_ticks: float,
			  hap_value: Variant, target_time: float, cycle_pos: float) -> void:
	## Actually fire note_on on the SiON driver and record timing.
	## If hap_value has ADSR controls, clone the voice and apply custom envelope.
	## If the voice name is a sample, route to SampleLibrary instead of SiON.
	var emit_ms: float = Time.get_ticks_msec()

	# Check if this note should be played as a sample instead of SiON
	var voice_name: String = _resolve_voice_name(hap_value)
	if _sample_library != null and _sample_library.has_sample(voice_name):
		var gain: float = _resolve_velocity(hap_value)
		var bpm: float = maxf(MusicManager._cyclist.cps * 120.0, 30.0) if MusicManager._cyclist != null else 120.0
		var dur_sec: float = length_ticks / (bpm * 4.0 / 60.0)
		_sample_library.play_sample(voice_name, note_num, gain, dur_sec)
		# Still record timing and apply effects below
	else:
		# SiON path: apply ADSR envelope and note_on
		var final_voice: Variant = voice

		# Per-note ADSR: extract attack/decay/sustain/release from hap value
		if hap_value is Dictionary:
			var has_adsr: bool = false
			var att: float = -1.0
			var dec: float = -1.0
			var sus: float = -1.0
			var rel: float = -1.0
			for key in ["attack", "att"]:
				if hap_value.has(key):
					att = float(hap_value[key])
					has_adsr = true
			for key in ["decay", "dec"]:
				if hap_value.has(key):
					dec = float(hap_value[key])
					has_adsr = true
			for key in ["sustain", "sus"]:
				if hap_value.has(key):
					sus = float(hap_value[key])
					has_adsr = true
			for key in ["release", "rel"]:
				if hap_value.has(key):
					rel = float(hap_value[key])
					has_adsr = true

			if has_adsr and voice != null:
				# Clone the voice and apply custom envelope.
				# SiON envelope rates: 0 = slowest, 63 = instant.
				# Strudel uses seconds. Convert: rate = 63 - clamp(seconds * 10, 0, 62)
				# (0s → rate 63 instant, 6.2s → rate 1 very slow)
				final_voice = voice.call("duplicate") if voice.has_method("duplicate") else voice
				if final_voice != voice:  # Only if clone succeeded
					var ar: int = _seconds_to_rate(att) if att >= 0.0 else 48  # Default fast attack
					var dr: int = _seconds_to_rate(dec) if dec >= 0.0 else 32  # Default moderate decay
					var sr: int = 0 if sus >= 0.0 else 0  # Sustain rate: 0 = hold level
					var rr: int = _seconds_to_rate(rel) if rel >= 0.0 else 32  # Default moderate release
					var sl: int = int(clampf((1.0 - sus) * 15.0, 0, 15)) if sus >= 0.0 else 4  # 0=full, 15=quiet
					final_voice.call("set_envelope", ar, dr, sr, rr, sl, 0)

		if final_voice != null:
			# Kill any previous instance of this pitch to prevent stacking.
			# SiON note_on doesn't auto-cut previous notes on the same pitch.
			driver.call("note_off", note_num)
			var track: Variant = driver.call("note_on", note_num, final_voice, length_ticks)
			# Apply per-note velocity from the hap's gain/velocity value.
			# SiON velocity range: 0-256 (256 = full volume).
			if track != null:
				var vel: float = _resolve_velocity(hap_value)
				if vel < 1.0:
					track.set("velocity", clampi(int(vel * 256.0), 0, 256))

	# Timing instrumentation
	if timing_log:
		if _timing_records.is_empty():
			_timing_start_ms = emit_ms - target_time * 1000.0
		var actual_ms: float = emit_ms - _timing_start_ms
		var target_ms: float = target_time * 1000.0
		var rec := {
			"note": note_num, "actual_ms": snapped(actual_ms, 0.1),
			"target_ms": snapped(target_ms, 0.1),
			"delta_ms": snapped(actual_ms - target_ms, 0.1),
			"cycle": snapped(cycle_pos, 0.001),
		}
		_timing_records.append(rec)
		print("TIMING: note=%d cycle=%.3f actual=%.1f target=%.1f delta=%+.1fms" % [
			note_num, cycle_pos, actual_ms, target_ms, rec["delta_ms"]])

	# Per-note effect correction
	_apply_hap_effects(hap_value)

	# Evaluate signal controls at this cycle position (e.g., sine.range(200, 2000))
	if not _signal_controls.is_empty() and cycle_pos >= 0:
		var sig_fx: Dictionary = {}
		for sig_pat in _signal_controls:
			var sig_haps: Array = sig_pat.query_arc(cycle_pos, cycle_pos + 0.001)
			if not sig_haps.is_empty():
				var val: Variant = sig_haps[0].value
				if val is Dictionary:
					for k in val:
						sig_fx[k] = float(val[k])
		if not sig_fx.is_empty():
			DebugOverlay.log("music/effects", null, "SIGNAL_FX: cycle=%.3f %s" % [cycle_pos, str(sig_fx)])
			MusicManager.set_music_effects(sig_fx)
		else:
			DebugOverlay.log("music/effects", null, "SIGNAL_FX: cycle=%.3f no values (signals=%d)" % [cycle_pos, _signal_controls.size()])

	DebugOverlay.log("strudel/trigger", null, "STRUDEL_TRIGGER: note=%d ticks=%.1f val=%s" % [
		note_num, length_ticks, str(hap_value)])


func timing_start() -> void:
	## Start timing capture — clears previous records.
	_timing_records.clear()
	_timing_start_ms = 0.0
	timing_log = true
	print("TIMING: capture started")


func timing_stop() -> String:
	## Stop capture and return analysis.
	timing_log = false
	return timing_analyze()


func timing_analyze() -> String:
	## Analyze captured timing data: jitter, drift, statistics.
	if _timing_records.is_empty():
		return "TIMING: no records captured"

	var lines: Array[String] = []
	lines.append("=== TIMING ANALYSIS (%d notes) ===" % _timing_records.size())

	# Compute statistics on delta (actual - target)
	var deltas: Array[float] = []
	var abs_deltas: Array[float] = []
	for rec in _timing_records:
		deltas.append(rec["delta_ms"])
		abs_deltas.append(absf(rec["delta_ms"]))

	var min_d: float = deltas[0]
	var max_d: float = deltas[0]
	var sum_d: float = 0.0
	var sum_abs: float = 0.0
	for d in deltas:
		min_d = minf(min_d, d)
		max_d = maxf(max_d, d)
		sum_d += d
	for d in abs_deltas:
		sum_abs += d
	var mean_d: float = sum_d / deltas.size()
	var mean_abs: float = sum_abs / abs_deltas.size()

	# Variance and stddev
	var sum_sq: float = 0.0
	for d in deltas:
		sum_sq += (d - mean_d) * (d - mean_d)
	var stddev: float = sqrt(sum_sq / deltas.size())

	lines.append("  Notes captured:  %d" % _timing_records.size())
	lines.append("  Mean delta:      %+.1f ms (bias)" % mean_d)
	lines.append("  Mean |delta|:    %.1f ms (avg error)" % mean_abs)
	lines.append("  Std deviation:   %.1f ms (jitter)" % stddev)
	lines.append("  Min delta:       %+.1f ms" % min_d)
	lines.append("  Max delta:       %+.1f ms" % max_d)
	lines.append("  Range:           %.1f ms" % (max_d - min_d))

	# Inter-note intervals: compare actual gaps to theoretical gaps
	if _timing_records.size() >= 2:
		var interval_errors: Array[float] = []
		for i in range(1, _timing_records.size()):
			var actual_gap: float = _timing_records[i]["actual_ms"] - _timing_records[i - 1]["actual_ms"]
			var target_gap: float = _timing_records[i]["target_ms"] - _timing_records[i - 1]["target_ms"]
			if target_gap > 0:
				interval_errors.append(actual_gap - target_gap)
		if not interval_errors.is_empty():
			var ie_sum: float = 0.0
			var ie_abs_sum: float = 0.0
			for e in interval_errors:
				ie_sum += e
				ie_abs_sum += absf(e)
			lines.append("  --- Inter-note Intervals ---")
			lines.append("  Mean interval err: %+.1f ms" % (ie_sum / interval_errors.size()))
			lines.append("  Mean |interval|:   %.1f ms" % (ie_abs_sum / interval_errors.size()))

	# Drift: is there a trend? Compare first-half mean to second-half mean
	if deltas.size() >= 10:
		var half: int = deltas.size() / 2
		var first_sum: float = 0.0
		var second_sum: float = 0.0
		for i in range(half):
			first_sum += deltas[i]
		for i in range(half, deltas.size()):
			second_sum += deltas[i]
		var first_mean: float = first_sum / half
		var second_mean: float = second_sum / (deltas.size() - half)
		var drift: float = second_mean - first_mean
		lines.append("  --- Drift ---")
		lines.append("  First half mean:   %+.1f ms" % first_mean)
		lines.append("  Second half mean:  %+.1f ms" % second_mean)
		lines.append("  Drift:             %+.1f ms (%s)" % [
			drift, "drifting late" if drift > 2.0 else "drifting early" if drift < -2.0 else "stable"])

	# Per-note detail (first 20 and last 5)
	lines.append("  --- Per-note (first 20) ---")
	for i in range(mini(_timing_records.size(), 20)):
		var r: Dictionary = _timing_records[i]
		lines.append("    #%02d note=%d cy=%.3f actual=%.1f target=%.1f Δ=%+.1fms" % [
			i, r["note"], r["cycle"], r["actual_ms"], r["target_ms"], r["delta_ms"]])
	if _timing_records.size() > 20:
		lines.append("    ... (%d more) ..." % (_timing_records.size() - 25))
		for i in range(maxi(_timing_records.size() - 5, 20), _timing_records.size()):
			var r: Dictionary = _timing_records[i]
			lines.append("    #%02d note=%d cy=%.3f actual=%.1f target=%.1f Δ=%+.1fms" % [
				i, r["note"], r["cycle"], r["actual_ms"], r["target_ms"], r["delta_ms"]])

	var result: String = "\n".join(lines)
	print(result)
	return result


func _apply_hap_effects(value: Variant) -> void:
	## Read audio control keys from a hap's value dict and forward
	## to MusicManager. Skips if nothing changed since last trigger.
	if not (value is Dictionary):
		# No controls on this hap — if effects were active, clear them
		if not _last_fx.is_empty():
			MusicManager.reset_music_effects()
			_last_fx.clear()
		return

	var fx: Dictionary = {}
	for key in EFFECT_KEYS:
		if value.has(key):
			fx[key] = float(value[key])

	if fx.is_empty():
		if not _last_fx.is_empty():
			MusicManager.reset_music_effects()
			_last_fx.clear()
		return

	# Only update if the controls actually changed (avoid redundant AudioServer calls)
	if fx != _last_fx:
		MusicManager.set_music_effects(fx)
		_last_fx = fx.duplicate()


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


func _resolve_voice_name(value: Variant) -> String:
	## Get the voice name string from a hap value (for sample library lookup).
	if value is Dictionary:
		for key in ["s", "sound", "voice"]:
			if value.has(key):
				return str(value[key]).to_lower()
	if value is String:
		return value.to_lower()
	return ""


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
	## Returns explicit gain/velocity from hap value, or 1.0 if not specified.
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
