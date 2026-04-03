---
assigned: 2026-04-03
source: user
priority: high
---

# Strudel v1.2.0 Integration — Active Work

## Status: PHASE 1 COMPLETE, PHASE 2 IN PROGRESS

## What Was Built (v0.10.47 → v0.10.52)

### Core Engine (fully working)
- **Pattern algebra** ported to GDScript: Fraction (exact rationals), TimeSpan, Hap, State, Pattern
- **45+ combinators**: fast, slow, early, late, every, rev, ply, palindrome, jux, off, inside, outside, zoom, chunk, compress, focus, degrade, struct, mask, add/sub/mul/div/set/keep/keepif
- **Mini-notation parser**: recursive descent replacing the 2600-line PEG-generated JS. Supports: sequences, sub-cycles, stacks, fast/slow, angle brackets, euclidean, degrade, replicate, weight, random choose, polymeter, foot separator
- **Cyclist scheduler**: cycle-based pattern scheduling with CPS tempo, frame-tick clock
- **SiON bridge**: 90+ voice presets mapped (piano, bass, strings, brass, reed, synth, drums)
- **148 unit tests** across 8 suites, all passing
- **9 listening test files** (60+ audible tests) in the test runner

### Music Drawer (Ctrl+M)
- Multi-line editor with named lines (`drums: "c4(3,8)".pianoroll()`)
- Per-line mute (Ctrl+/), per-line visualizers
- Full keybindings: selection, clipboard, emacs kill ring, word nav
- Live evaluation with hot-swap (Ctrl+Enter)
- Source highlighting (active notes glow in text)
- Import/export: `strudel save/load`

### Visualizers (all Strudel v1.2.0 types)
- `.pianoroll()` with options: labels, fold, vertical, autorange, cycles, playhead, fill, strokeActive, hideInactive, minMidi, maxMidi
- `.punchcard()` — pianoroll alias
- `.wordfall()` — vertical pianoroll with labels (delegates to pianoroll with presets)
- `.scope()` / `.tscope()` — oscilloscope (simulated, not real audio analyser)
- `.fscope()` — frequency spectrum (simulated, pitch bars not FFT)
- `.spiral()` — archimedean spiral with rotating playhead
- `.pitchwheel()` — 12-EDO pitch circle with flake/polygon modes
- Strudel-compatible syntax: `"mini".pianoroll({labels:1})`
- Quoted mini-notation: `"c4 e4 g4 c5".pianoroll()`, `note("c4 e4").scope()`

### RCON Commands
- `strudel <mini-notation>` — parse and play
- `strudel stop/start` — stop/resume with pattern preservation
- `strudel cps <value>` — tempo
- `strudel status` — show scheduler state
- `strudel edit <line1> | <line2>` — set drawer lines with visualizers
- `strudel save/load <name>` — pattern file management
- `strudel voices` — list 90+ voice presets
- `strudel test [suite]` — run unit tests
- `strudel listen` — run listening test suite
- `music help` — comprehensive reference

## What Is NOT Supported (Strudel Features We're Missing)

### Critical Gaps

**1. JavaScript Expression Language (0% coverage)**
Strudel patterns are JS programs. Users write:
```javascript
note("c4 e4 g4").s("sawtooth").lpf(800).room(0.5)
stack(drums, bass, melody).cpm(120)
```
We only parse the mini-notation inside quotes. Method chains, variables, `let`, `stack()`, `setcps()`, `samples()` — none of this works. This is the BIGGEST gap.

**2. Audio Synthesis Controls (2% coverage — 6 of 274)**
We support: `note`, `s`, `n`, `gain`, `velocity`, `cps`
Missing ALL of:
- **Filter**: `lpf`, `hpf`, `bpf`, `lpq`, `lpenv`, `lpa`, `lpd`, `lps` and all HP/BP variants
- **Envelope**: `attack`, `decay`, `sustain`, `release`, `hold`, `adsr`, `clip`
- **Effects**: `room`, `roomsize`, `delay`, `delaytime`, `delayfeedback`, `phaser`, `distort`, `crush`, `shape`
- **FM**: `fm`, `fmh`, `fmi`, `fmenv`
- **Modulation**: `vib`, `vibmod`, `tremolo`, `penv`
- **Pan**: `pan`, `panspan`

**3. Sample Playback (0% coverage)**
- `samples()` — loading .wav/.mp3 from URLs or GitHub repos
- `s("bd sd hh")` with actual audio samples (we map to FM voices, not samples)
- `.begin()`, `.end()`, `.loop()`, `.chop()`, `.striate()`, `.speed()`, `.cut()`

**4. Chord/Scale System (0% coverage)**
- `chord()`, `.voicing()`, `.scale()`, `.mode()`, `.anchor()`, `.dict()`
- The entire `@strudel/tonal` package

**5. Live Coding Features**
- `p("name")` — named pattern slots with independent lifecycle (we have named lines but not independent cycling)
- Hot-swap with transition/crossfade
- `setcps()` from code (we have it via RCON only)

### Minor Gaps

- Mini-notation `..` range operator — not implemented
- `perlin` signal — not implemented
- `arrange`, `seqPLoop`, `inhabit`, `pick`, `chooseWith`, `wchoose` combinators
- `chop`, `striate`, `slice` — sample manipulation (depends on sample system)
- Pianoroll options not yet supported: `smear`, `colorizeInactive`, `fontFamily`
- Viz options for spiral: `stretch`, `size`, `thickness`, `cap`, `inset`, `steady`, `fade`
- Viz options for pitchwheel: `hapcircles`, `circle`, `edo`, `root`, `mode`, `margin`
- Viz options for scope: `align`, `thickness`, `scale`, `pos`, `trigger`
- `.onPaint()` custom drawing callback

## Key Architecture Decisions

1. **GDSiON for audio** — FM synthesis, not Web Audio. Different sound character.
   - Pro: runs in-process, 650+ presets, no sample loading needed
   - Con: can't reproduce Web Audio oscillator or sample-based sounds exactly
   - SiON `note_on(note, voice, length_ticks)` is the only audio output primitive
   - BPM synced to CPS for correct note duration

2. **Mini-notation only** — we parse the text inside quotes, not JavaScript
   - Pro: self-contained, no JS runtime needed
   - Con: can't run real Strudel programs, only the pattern DSL
   - The transpiler/evaluate path from Strudel is NOT ported

3. **Per-line patterns** — each drawer line is independently parsed and stacked
   - Patterns stored in `_line_patterns[]` for per-line visualization
   - Combined with `Strudel.stack()` for playback
   - External sync via `MusicManager._strudel_source_text`

4. **Rolling hap buffer** — pianoroll accumulates haps incrementally
   - Prunes left edge, queries right edge only
   - Resets on pattern change (detected via `_last_known_pattern`)
   - `_self_triggered` flag prevents sync from overwriting drawer state

5. **Dynamic GDScript bridge** — GDSiON types accessed via runtime-compiled GDScript
   - Avoids parse-time type dependency on GDExtension
   - Graceful fallback if GDSiON missing

## File Layout

```
scripts/music/
  core/
    strudel_fraction.gd      — exact rational arithmetic (~210 lines)
    strudel_timespan.gd      — time intervals (~110 lines)
    strudel_hap.gd           — events (~180 lines)
    strudel_state.gd         — query input (~20 lines)
    strudel_pattern.gd       — pattern algebra + combinators (~700 lines)
    strudel_signal.gd        — continuous signals (~100 lines)
    strudel.gd               — static factories (~200 lines)
    strudel_test.gd          — 148 unit tests (~400 lines)
  mini/
    strudel_mini_parser.gd   — recursive descent parser (~320 lines)
    strudel_mini.gd          — AST to Pattern + leaf locations (~250 lines)
  scheduler/
    strudel_clock.gd         — frame-based tick clock (~50 lines)
    strudel_cyclist.gd       — cycle-based scheduler (~130 lines)
  bridge/
    sion_trigger.gd          — hap → SiON note_on (~270 lines)
  ui/
    music_drawer.gd          — Music Drawer panel (~1400 lines)

scripts/autoload/
  music_manager.gd           — GDSiON driver + Strudel engine (~650 lines)

data/music/
  scores.json                — 18 community MML arrangements
data/tests/
  music_*.json               — 9 listening test files
  suites/music.json          — music test suite

docs/
  epics/EPIC_strudel_integration.md   — design doc (all phases COMPLETE)
  design/strudel_compatibility.md     — compatibility audit
```

## Strudel Source Reference
- Frozen checkout: `/var/tumu/repos/strudel-v1.2.0/`
- Research notes: `/var/tumu/research/gamedev/strudel/viz_options.md`
- DO NOT update the checkout — pinned to v1.2.0

## Priority Path Forward

1. **More controls via SiON mapping** — `attack`/`release` → SiON envelope, `lpf` → SiON filter effect, `room` → SiON reverb. Won't sound identical to Web Audio but functionally equivalent.
2. **JS expression subset** — support `stack()`, `setcps()`, simple variable assignment. NOT a full JS runtime, just the common patterns.
3. **Sample playback** — bundled drum kit (bd, sd, hh, cp as .wav), played via Godot AudioStreamPlayer instead of SiON.
4. **Game event patterns** — replace MML adaptive layers with Strudel patterns driven by game intensity.

## Known Bugs

- Scope/fscope are simulated (sine wave at pitch, not real audio FFT)
- Spiral viz options (stretch, size, steady) not yet configurable from options syntax
- Pitchwheel viz options not yet configurable
- `.note()` and `.s()` pattern methods exist but aren't parsed from the drawer text (only via RCON `s=voice`)

## Status Notes
- 2026-04-03: Full session — built entire engine from zero to v0.10.52
- All 148 unit tests passing
- All 9 listening test suites working
- LSP diagnostics tool now available via `/gd diagnostics`
