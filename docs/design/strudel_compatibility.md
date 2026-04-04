# Strudel v1.2.0 Compatibility Report

## What We Support

### Mini-Notation (the text inside quotes)
| Feature | Strudel | Ours | Status |
|---------|---------|------|--------|
| Sequence `a b c` | ✓ | ✓ | MATCH |
| Sub-cycle `[a b]` | ✓ | ✓ | MATCH |
| Stack `[a, b]` | ✓ | ✓ | MATCH |
| Rest `~` | ✓ | ✓ | MATCH |
| Fast `*n` | ✓ | ✓ | MATCH |
| Slow `/n` | ✓ | ✓ | MATCH |
| Slowcat `<a b c>` | ✓ | ✓ | MATCH |
| Euclidean `(p,s)` | ✓ | ✓ | MATCH |
| Euclidean rot `(p,s,r)` | ✓ | ✓ | MATCH |
| Degrade `?` | ✓ | ✓ | MATCH |
| Replicate `!n` | ✓ | ✓ | MATCH |
| Weight `@n` | ✓ | ✓ | MATCH |
| Tail/colon `:n` | ✓ | ✓ | MATCH |
| Random choose `\|` | ✓ | ✓ | MATCH |
| Polymeter `{a b, c d}` | ✓ | ✓ | MATCH |
| Polymeter steps `{...}%n` | ✓ | ✓ | MATCH |
| Foot separator `.` | ✓ | ✓ | MATCH |
| Range `..` | ✓ | ✗ | MISSING |
| Explicit steps `^` | ✓ | partial | PARTIAL |

### Pattern Algebra (core combinators)
| Feature | Strudel | Ours | Status |
|---------|---------|------|--------|
| pure/silence/gap | ✓ | ✓ | MATCH |
| stack/sequence/cat/fastcat/slowcat | ✓ | ✓ | MATCH |
| fast/slow | ✓ | ✓ | MATCH |
| early/late | ✓ | ✓ | MATCH |
| rev | ✓ | ✓ | MATCH |
| every/firstOf/lastOf | ✓ | ✓ | MATCH |
| ply | ✓ | ✓ | MATCH |
| euclid/euclidRot | ✓ | ✓ | MATCH |
| struct/mask | ✓ | ✓ | MATCH |
| add/sub/mul/div | ✓ | ✓ | MATCH (in-mode only) |
| set/keep/keepif | ✓ | ✓ | MATCH (in/out modes) |
| appBoth/appLeft/appRight | ✓ | ✓ | MATCH |
| bind/join/outerBind/innerBind | ✓ | ✓ | MATCH |
| squeezeJoin/squeezeBind | ✓ | ✓ | MATCH |
| degrade/degradeBy | ✓ | ✓ | MATCH |
| palindrome | ✓ | ✓ | MATCH |
| jux | ✓ | ✓ | MATCH (no pan) |
| off | ✓ | ✓ | MATCH |
| inside/outside | ✓ | ✓ | MATCH |
| chunk | ✓ | ✓ | MATCH |
| compress/focus/zoom | ✓ | ✓ | MATCH |
| range/rangex | ✓ | ✓ | MATCH |
| segment | ✓ | ✓ | MATCH |
| Composer 8 "hows" (in/out/mix/squeeze/...) | ✓ | partial | Only in/out/both/squeeze for add |
| arrange | ✓ | ✗ | MISSING |
| seqPLoop | ✓ | ✗ | MISSING |
| inhabit/pick | ✓ | ✗ | MISSING |
| chooseWith/wchoose | ✓ | ✗ | MISSING |
| chop/striate/slice | ✓ | ✗ | MISSING (sample manipulation) |
| legato/sustain control | ✓ | ✗ | MISSING |

### Signals
| Feature | Strudel | Ours | Status |
|---------|---------|------|--------|
| saw/isaw | ✓ | ✓ | MATCH |
| sine/cosine | ✓ | ✓ | MATCH |
| tri/square | ✓ | ✓ | MATCH |
| rand | ✓ | ✓ | MATCH |
| run/scan | ✓ | ✓ | MATCH |
| irand | ✓ | ✓ | MATCH |
| perlin | ✓ | ✗ | MISSING |
| time | ✓ | ✓ | MATCH |

### Visualizers
| Feature | Strudel | Ours | Status |
|---------|---------|------|--------|
| .pianoroll() / .punchcard() | ✓ | ✓ | MATCH |
| .scope() / .tscope() | ✓ | ✓ | SIMULATED (no real audio analyser) |
| .fscope() | ✓ | ✓ | SIMULATED (pitch bars, not FFT) |
| .wordfall() | ✓ | ✓ | MATCH |
| .spiral() | ✓ | ✓ | MATCH |
| .pitchwheel() | ✓ | ✓ | MATCH |
| Viz options (cycles, playhead, fold, labels, etc.) | ✓ | ✓ | MATCH (pianoroll opts) |
| .onPaint() custom drawing | ✓ | ✗ | MISSING |
| Source code highlighting | ✓ | ✓ | MATCH |

## What We DON'T Support

### Major Missing Systems

**1. JavaScript Expression Language**
Strudel patterns are JavaScript programs. Users write:
```javascript
note("c4 e4 g4").s("sawtooth").lpf(800).room(0.5)
```
We only parse the mini-notation inside quotes. The JS method chains, variables, `let`, `stack()`, `setcps()`, `samples()` — none of this works.

**2. Sample Playback**
- `samples()` — loading .wav/.mp3 from URLs or GitHub repos
- `s("bd sd hh")` — triggering drum samples by name
- `.bank()` — sample bank selection
- `.begin()`, `.end()`, `.loop()` — sample slice/loop
- `.chop()`, `.striate()`, `.slice()` — granular sample manipulation
- `.speed()` — sample playback speed
- `.cut()` — cut groups (monophonic voice management)

**3. Audio Synthesis Controls (274 registered)**
We support 19 of 274 controls. Supported (bus-level post-processing):
- **Filter**: `lpf`, `hpf`, `lpq`, `hpq` — via Godot AudioEffectLowPassFilter/HighPassFilter (bus-level, not per-note)
- **Effects**: `room`, `roomsize`, `roomlp` — via AudioEffectReverb (bus-level, matches Strudel's orbit-shared reverb)
- **Effects**: `delay`, `delaytime`, `delayfeedback` — via AudioEffectDelay (bus-level, matches Strudel's orbit-shared delay)
- **Effects**: `distort`, `crush`, `shape` — via AudioEffectDistortion (bus-level, clip/lofi/waveshape modes)
- **Pan**: `pan` — via AudioEffectPanner (bus-level)
- **Note**: `note`, `s`, `n`, `gain`, `velocity`, `cps` — per-note via SiON

Missing:
- **Oscillator**: `s("sawtooth")`, `s("square")`, `s("triangle")` — mapped to FM voices (approximate)
- **Filter**: `bpf`, `lpenv`, `lpd`, `lpa`, `lps` — envelope-modulated filters
- **Envelope**: `attack`, `decay`, `sustain`, `release`, `hold` — per-note ADSR (SiON voices have baked envelopes)
- **FM**: `fm`, `fmh`, `fmi`, `fmenv`, `fmattack`, `fmdecay`
- **Modulation**: `vib`, `vibmod`, `tremolo`
- **Pan**: `panspan` — stereo width
- **MIDI**: `ccn`, `ccv`, `channel`
- **Phaser**: `phaser` — not yet mapped to AudioEffectPhaser

**4. Chord/Scale System** (from @strudel/tonal)
- `chord()` — chord name to notes
- `.voicing()` — voice leading
- `.scale()` — scale mapping
- `.mode()` — scale mode
- `.anchor()` — voice anchor
- `.dict()` — chord dictionary

**5. Live Coding Features**
- `setcps()` — global tempo from code
- `hush` — silence all
- `p("name")` — named pattern slots with independent lifecycle
- Hot-swap with transition (crossfade between patterns)

**6. Import/Export** *(partially supported)*
- ✓ `strudel save/load` — save/load pattern files
- ✗ No way to share patterns externally
- ✗ No clipboard format for patterns

## What We Have That Strudel Doesn't

**Game integration hooks:**
- Monster state → music intensity
- Player damage → intensity push
- Game state (title/overworld/tower/boss) → pattern switching
- Per-voice SiON FM synthesis (87 preset voices)
- MML score playback alongside Strudel patterns
- RCON console control
- In-game test runner for audio verification

## Priority Path to Better Compatibility

1. ~~**Oscillator types**: mapped to closest SiON FM voices~~ ✓ DONE
2. **Basic ADSR**: `attack`, `release`, `decay`, `sustain` → per-note SiON envelope (requires GDSiON API investigation)
3. ~~**Basic filter**: `lpf`, `hpf` → Godot AudioBus effects~~ ✓ DONE (bus-level)
4. **Sample loading**: Bundled drum samples (`bd`, `sd`, `hh`, `cp`) as .wav via AudioStreamPlayer
5. ~~**Import/export**: `strudel save/load`~~ ✓ DONE
6. ~~**Viz options**: `pianoroll({labels: 1, fold: 0, cycles: 8})`~~ ✓ DONE
7. **JS expression subset**: `stack()`, `setcps()`, `.s()`, `.lpf()` method chains (partial — method chains parsed in drawer)
8. **Phaser**: map to AudioEffectPhaser
9. **Game event patterns**: replace MML adaptive layers with Strudel patterns
