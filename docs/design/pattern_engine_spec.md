# Pattern Engine Specification — The Ultimate Muffin

> Functional specification for a cycle-based algorithmic music pattern engine.
> Describes WHAT the system does, not how any specific implementation codes it.
> This document is the sole reference for clean-room implementation.

## 1. Overview

The pattern engine generates musical events by evaluating time-varying functions over rational time. A **pattern** is a function that, given a time range, returns a list of **events** (notes, control changes, silence). Patterns compose via algebraic operations — stacking, sequencing, transforming — to build complex musical structures from simple building blocks.

The system runs in a game engine (Godot 4.6) and drives an FM synthesizer (GDSiON) for audio output. It supports live-coding via an in-game editor panel and responds to game events for adaptive music.

## 2. Time Model

### 2.1 Rational Time (Fraction)

All time values are exact rational numbers (numerator/denominator pairs) to avoid floating-point drift over long compositions. Operations: add, subtract, multiply, divide, modulo, comparison, floor, min, max. Fractions auto-reduce to lowest terms.

A **cycle** is the fundamental time unit. One cycle = one repetition of a pattern. The relationship to wall-clock time is controlled by CPS (cycles per second). At CPS=0.5, one cycle = 2 seconds.

### 2.2 Time Span

A contiguous interval `[begin, end)` where begin and end are Fractions. Represents the time range of a query or the temporal extent of an event.

Key operations:
- **intersection**: overlap of two spans (null if disjoint)
- **split_cycles**: break a multi-cycle span into per-cycle segments (e.g., [0.5, 2.5) → [0.5, 1), [1, 2), [2, 2.5))
- **cycle_at_time**: which cycle contains a given time point
- **shift_by**: offset a span by a Fraction
- **duration**: end - begin

### 2.3 Event (Hap)

An event represents something happening in musical time. It has:
- **whole**: the complete span of the event (null for continuous/fragmentary events)
- **part**: the portion of the event visible in the current query window (always non-null)
- **value**: the musical content (a note name, MIDI number, dictionary of controls, or any value)
- **context**: metadata (source locations for editor highlighting, etc.)

An event has an **onset** when its `part.begin == whole.begin` — meaning the start of the event falls within the query window.

**Duration control**: the effective duration can be modified by:
- **clip** (multiplier): scales the whole-span duration. clip=0.5 → staccato (half length). clip=2 → legato (double, overlapping).
- **duration** (absolute): overrides the slot-based duration with a value in cycles.

### 2.4 Query State

A query has:
- **span**: the time range being queried
- **controls**: a dictionary of global parameters (reserved for future use)

## 3. Pattern Algebra

### 3.1 Core Type

A Pattern is an opaque function: `query(State) → Array[Event]`

Every pattern operation creates a new Pattern by wrapping the query function. Patterns are immutable and compositional.

### 3.2 Primitive Constructors

| Constructor | Behavior |
|-------------|----------|
| **pure(value)** | Repeats `value` once per cycle. Query returns one event per cycle in the range. |
| **silence** | Returns no events for any query. |
| **gap** | Same as silence. |

### 3.3 Composition

| Operation | Behavior |
|-----------|----------|
| **stack(patterns)** | All patterns play simultaneously. Query returns the union of all sub-pattern events. |
| **sequence(patterns)** | Patterns play in order within one cycle, each compressed to fill 1/N of the cycle. |
| **cat(patterns)** | Alias for sequence. |
| **fastcat(patterns)** | Alias for sequence. |
| **slowcat(patterns)** | Each pattern plays for one full cycle, cycling through the list. Pattern 0 on cycle 0, pattern 1 on cycle 1, etc. |

### 3.4 Time Transforms

| Operation | Behavior |
|-----------|----------|
| **fast(factor)** | Speed up: compress time by factor. `fast(2)` plays the pattern twice per cycle. |
| **slow(factor)** | Slow down: stretch time by factor. `slow(2)` plays half the pattern per cycle. |
| **early(offset)** | Shift pattern earlier in time by offset (in cycles). |
| **late(offset)** | Shift pattern later in time by offset. |
| **rev** | Reverse the pattern within each cycle. |
| **palindrome** | Even cycles play forward, odd cycles play reversed. |
| **inside(factor, fn)** | Apply transform `fn` within a sped-up context: fast(factor) → fn → slow(factor). |
| **outside(factor, fn)** | Apply transform `fn` within a slowed-down context. |
| **compress(span)** | Squeeze the pattern into a sub-range of the cycle. |
| **focus(span)** | Like compress but also zooms into that time range. |

### 3.5 Conditional / Selective Transforms

| Operation | Behavior |
|-----------|----------|
| **every(n, fn)** | Apply transform `fn` every N cycles. |
| **sometimes(fn)** | Apply `fn` ~50% of the time (alias: every(2, fn)). |
| **often(fn)** | Apply `fn` ~75% of the time. |
| **rarely(fn)** | Apply `fn` ~25% of the time. |
| **chunk(n, fn)** | Divide cycle into N chunks, rotate which chunk gets `fn` applied. |
| **degrade(amount)** | Randomly drop events with probability `amount` (default 0.5). Uses deterministic pseudo-random signal seeded by cycle position. |

### 3.6 Value Transforms

| Operation | Behavior |
|-----------|----------|
| **fmap(fn)** | Apply function `fn` to each event's value. |
| **filter_values(fn)** | Keep only events where `fn(value)` is true. |
| **with_value(fn)** | Alias for fmap. |
| **set_in(other)** | Merge values from `other` pattern into this pattern (left structure). For dicts, overlays keys. |
| **add/sub/mul** | Arithmetic composition — add/subtract/multiply corresponding values. For dicts, operates per matching key. |

### 3.7 Structural Transforms

| Operation | Behavior |
|-----------|----------|
| **ply(n)** | Repeat each event N times within its slot (subdivide). |
| **euclid(pulses, steps, rotation)** | Euclidean rhythm — distribute `pulses` events as evenly as possible across `steps` slots. Optional rotation offset. |
| **off(time, fn)** | Superimpose a time-shifted, transformed copy: stack(self, early(time).fn()). |
| **jux(fn)** | Juxtapose: stack original with a transformed copy (in stereo, panned opposite). |
| **superimpose(fns)** | Stack original with one or more transformed copies. |
| **iter(n)** | Shift pattern by 1/n each cycle. |
| **segment(n)** | Sample the pattern N times per cycle, creating a stepped version. |

### 3.8 Application (Applicative)

| Operation | Behavior |
|-----------|----------|
| **app_left(other)** | Apply a pattern of functions to a pattern of values, using left (this) pattern's structure for timing. |
| **app_right(other)** | Use right (other) pattern's structure. |
| **app_both(other)** | Use intersection of both structures. |
| **squeeze_join** | Like join but compresses the inner pattern into the outer event's time span. |

## 4. Signals (Continuous Patterns)

Signals are patterns that produce continuous values (0.0–1.0) rather than discrete events. Used for modulating controls over time.

| Signal | Behavior |
|--------|----------|
| **sine** | Sine wave, one complete cycle per pattern cycle |
| **cosine** | Cosine wave |
| **saw** | Ascending sawtooth 0→1 |
| **isaw** | Descending sawtooth 1→0 |
| **tri** | Triangle wave |
| **square** | Square wave (0 or 1) |
| **rand** | Deterministic pseudo-random (same seed = same sequence) |
| **irand(n)** | Random integers 0..n-1 |
| **run(n)** | Count 0,1,...,n-1 per cycle |
| **scan(n)** | Count 0,1,...,n-1 across N cycles |

Signals support `.range(lo, hi)` to remap from [0,1] to [lo,hi], and `.segment(n)` to sample discretely.

## 5. Mini-Notation

A compact text notation for building patterns inline. Parsed by a recursive-descent parser.

### 5.1 Grammar (informal)

```
pattern   = sequence
sequence  = element (" " element)*
element   = atom [operators]
atom      = rest | group | slowcat | polymeter | literal
rest      = "~"
group     = "[" sequence ("," sequence)* "]"     -- sub-cycle or stack
slowcat   = "<" element (" " element)* ">"       -- one per cycle
polymeter = "{" sequence ("," sequence)* "}" ["%" number]
literal   = note_name | number | word

operators = ("*" number | "/" number | "!" number | "@" number
            | "(" number "," number ["," number] ")"   -- euclidean
            | "?" [number]                              -- degrade
            | ":" number                                -- sample index
            )*
```

### 5.2 Elements

- **Sequence** `a b c`: elements divide the cycle equally (3 elements = 1/3 each)
- **Sub-cycle** `[a b]`: compresses a sequence into one slot
- **Stack** `[a, b]`: elements play simultaneously
- **Rest** `~`: silence for one slot
- **Slowcat** `<a b c>`: one element per cycle, rotating
- **Polymeter** `{a b, c d e}`: each voice maintains its own step count
- **Euclidean** `a(3,8)`: 3 pulses across 8 steps
- **Fast** `a*2`: repeat twice per slot
- **Slow** `a/2`: stretch across 2 slots
- **Replicate** `a!3`: duplicate 3 times (each gets its own slot)
- **Weight** `a@2`: this slot is twice as wide
- **Degrade** `a?`: random 50% chance to play
- **Tail** `a:2`: sample index / secondary value

### 5.3 Source Locations

The parser tracks character positions for each leaf element. These positions are attached to events as context metadata, enabling source code highlighting in the editor — as a note plays, the corresponding text in the editor glows.

## 6. Scheduler (Cyclist)

### 6.1 Clock

A frame-driven clock ticks at configurable intervals (default ~50ms). Each tick:
1. Compute the current cycle position: `phase = elapsed_time * cps`
2. Query the active pattern for events in the window `[last_phase, phase + lookahead]`
3. For each event with an onset, compute wall-clock target time and enqueue

### 6.2 CPS (Cycles Per Second)

Global tempo control. CPS=0.5 → 1 cycle every 2 seconds → 120 BPM (if 1 cycle = 1 bar of 4/4). Changeable at runtime via `setcps()`.

### 6.3 Latency

Configurable lookahead (default ~100ms) to pre-schedule events for tighter timing. Events are enqueued with wall-clock target times and fired from the process loop.

## 7. Audio Bridge

### 7.1 Note Resolution

Each event's value resolves to a MIDI note number. Supports:
- Note names: `c4`, `eb3`, `f#5` → MIDI number
- Plain numbers: `60` → MIDI 60
- Dictionary with `note` key: `{note: "c4"}` → MIDI 60

### 7.2 Voice Resolution

Events can specify a synthesizer voice via the `s` key: `{s: "sawtooth"}`, `{s: "square"}`, etc. Maps to FM synthesis presets.

### 7.3 Per-Note Controls

Events carry per-note parameters in their value dictionaries:
- **gain**: amplitude (0.0–1.0+)
- **attack/decay/sustain/release**: ADSR envelope
- **clip**: duration multiplier (legato/staccato)
- **duration**: absolute duration in cycles
- **pan**: stereo position

### 7.4 Bus Effects

Applied at the audio bus level (shared across all notes):
- **lpf/hpf**: low/high pass filter with resonance (lpq/hpq)
- **room/roomsize**: reverb
- **delay/delaytime/delayfeedback**: echo
- **distort/crush/shape**: distortion variants

## 8. Editor (Music Drawer)

An in-game panel (toggled via Ctrl+M) for live-coding patterns:
- Multi-line editor with named lines and mute toggles
- Per-line pattern parsing and independent visualization
- Inline visualizers: pianoroll, scope, wordfall, spiral, pitchwheel, fscope
- Source code highlighting: active notes glow in the text
- Real-time hot-swap: editing a line instantly changes the playing pattern

### 8.1 Line Parsing

Each line is parsed as a Strudel-compatible expression:
- `"mini-notation"` — bare quoted mini-notation
- `note("mini")` — note wrapper
- `s("voices")` — voice/sample wrapper
- `.method()` chains — transforms, audio controls, visualizers
- `stack(expr, expr, ...)` — multi-expression stacking
- `setcps(N)` — global tempo (not a pattern, side-effect)
- `// comment` — ignored
- `name: pattern` — named label for the line

### 8.2 File Loading

Loads `.strudel` files from disk. Multi-line expressions (e.g., `stack()` across lines) are merged by tracking parenthesis depth before feeding to the line parser.

## 9. Testing Infrastructure

### 9.1 A/B Comparison

A reference audio server renders the same pattern expression through the canonical implementation. Both outputs are compared via:
- Spectral band energy (lo/mid/hi) per 100ms window
- Spectral shape (normalized band ratios)
- Zero-crossing frequency match (with harmonic tolerance: 2x ratio accepted)
- Onset timing alignment
- Centroid correlation (for filter sweep patterns)

### 9.2 Highlight Verification

Per-beat tracking records which source substrings are highlighted at each beat fraction. Tests assert expected highlights with set semantics for simultaneous notes:
```
check 0/1:[L1:c4|L1:c5]    -- at beat 0, both c4 and c5 highlighted on line 1
check 1/4:[L1:e4]           -- at beat 1/4, e4 highlighted
```

---

*This specification describes musical concepts and system behaviors. It does not reference any specific implementation's source code.*
