# EPIC: Strudel Integration — Procedural Music Pattern Engine

## Overview

Port Strudel v1.2.0's pattern algebra and mini-notation to GDScript, driving GDSiON synthesis with a live-editing Music Drawer UI. The integration prioritizes **depth-first compatibility** — one complete user-feedback path working fully before broadening.

### Target Release
Strudel v1.2.0 (tag `5702914661`, latest stable as of April 2026)

### Source Reference
`/var/tumu/repos/strudel-v1.2.0/` — frozen checkout, do not update

### Design Principles
1. **Encapsulated resource bundles** — separable like character classes (ClassComponent pattern)
2. **Tree-like architecture** — later extractable as a plug-in
3. **Depth-first** — one thing working deeply before adding a second
4. **End-to-end first** — user input through to visual feedback in one path
5. **No feature additions** — match Strudel, don't extend it
6. **Retain compatibility** — same mini-notation, same pattern algebra semantics

---

## Architecture

### Strudel's Core Model (What We're Porting)

Strudel's architecture is a pure functional pattern algebra. Understanding this model precisely is critical — everything else (mini-notation, visualization, scheduling) is built on top.

#### The Five Core Types

```
Fraction    — exact rational number (numerator/denominator)
             Used for ALL time values. No floats in the time domain.
             Key ops: sam() (cycle start), nextSam(), cyclePos(), wholeCycle()

TimeSpan    — (begin: Fraction, end: Fraction)
             A time interval. Key ops: spanCycles (split across cycle boundaries),
             intersection(), duration, cycleArc(), withTime()

Hap         — (whole: TimeSpan?, part: TimeSpan, value: Variant, context: Dictionary)
             An event. "whole" is the full event duration; "part" is the visible
             fragment (may be smaller if the event spans cycle boundaries).
             whole=null means continuous (signal) value.
             context carries source locations for highlighting.

State       — (span: TimeSpan, controls: Dictionary)
             Query input. Pattern.query(State) -> Array[Hap]

Pattern     — (query: Callable)
             THE core type. A function: State -> Array[Hap]
             Everything is a Pattern. All transformations return new Patterns.
```

#### The Pattern Algebra

Patterns compose via applicative/monadic operations inherited from Haskell:

- **fmap/withValue**: transform event values (functor)
- **appBoth/appLeft/appRight**: combine two patterns (applicative)
- **bind/join**: flatten Pattern<Pattern<T>> (monad)
- **squeezeJoin/resetJoin/outerJoin/innerJoin**: different flattening strategies

User-facing operations are built from these primitives:
- `fast(n)` / `slow(n)` — time stretching via query/hap time manipulation
- `early(n)` / `late(n)` — time shifting
- `every(n, f)` — apply function f every n cycles
- `stack(...)` — layer patterns simultaneously
- `sequence(...)` / `fastcat(...)` — concatenate patterns within one cycle
- `cat(...)` / `slowcat(...)` — one pattern per cycle
- `euclid(pulses, steps)` — Bjorklund euclidean rhythms
- `rev()` — reverse a cycle
- `add/sub/mul/div` — arithmetic on pattern values
- `struct(pattern)` — impose rhythmic structure
- `set/keep/keepif` — pattern combination operators
- 8 "hows" for each operator: In, Out, Mix, Squeeze, SqueezeOut, Reset, Restart, Poly

#### Mini-Notation

A compact DSL parsed by a PEG grammar (krill.pegjs, 303 lines):
```
"bd sd [hh hh] cp"     — sequence
"bd, sd, hh"            — stack (simultaneous)
"bd*2"                  — fast (repeat)
"bd/2"                  — slow
"<bd sd hh>"            — slowcat (one per cycle)
"bd?"                   — degrade (random drop)
"bd(3,8)"               — euclidean rhythm
"bd:2"                  — sample index
"bd!3"                  — replicate
"[bd sd]*2"             — group + fast
"~"                     — silence/rest
```

The parser (krill-parser.js, ~2600 lines generated from PEG) produces an AST that `mini.mjs` (261 lines) converts to Pattern trees via `patternifyAST()`.

#### Scheduling (Cyclist)

The Cyclist maintains:
- `cps` (cycles per second, default 0.5 = 120 BPM)
- A clock (zyklus.mjs) that fires callbacks at fixed intervals
- Each tick: query the pattern for haps in the upcoming time window
- Haps with onsets get scheduled via `onTrigger` callback

#### Visualization (Draw)

Pianoroll visualization (pianoroll.mjs, 317 lines):
- Queries the pattern for haps in a time window around "now"
- Renders hap rectangles on a 2D canvas: X=time, Y=pitch/value
- Active haps (playing now) get highlighted
- Playhead line shows current position

Source highlighting (highlight.mjs, 139 lines):
- Mini-notation leaf nodes carry source locations in hap.context.locations
- Each frame, active haps' locations are used to highlight code in the editor
- Highlights are transient decorations overlaid on the text

### Our Architecture (GDScript Port)

```
scripts/
  music/                              # NEW — separable plugin tree
    core/                             # Pattern algebra (pure, no Godot deps)
      strudel_fraction.gd             # Fraction (exact rationals)
      strudel_timespan.gd             # TimeSpan
      strudel_hap.gd                  # Hap (event)
      strudel_state.gd                # State (query input)
      strudel_pattern.gd              # Pattern + all combinators
      strudel_euclid.gd               # Euclidean rhythms
      strudel_signal.gd               # Continuous patterns (saw, sine, rand)
    mini/                             # Mini-notation parser
      strudel_mini_parser.gd          # PEG parser port (recursive descent)
      strudel_mini.gd                 # AST -> Pattern conversion
    scheduler/                        # Timing and dispatch
      strudel_cyclist.gd              # Cycle-based scheduler
      strudel_clock.gd                # Timer (replaces zyklus.mjs)
    bridge/                           # GDSiON output bridge
      sion_trigger.gd                 # Hap -> SiONDriver.note_on/note_off
      sion_voice_map.gd               # Pattern value -> SiON voice mapping
    draw/                             # Visualization (Godot _draw())
      strudel_pianoroll.gd            # Pianoroll renderer
      strudel_highlight.gd            # Source location highlighting
    ui/                               # Music Drawer UI
      music_drawer.gd                 # Drawer panel (like debug_drawer.gd)
      music_line.gd                   # Single editor line (text + viz + widgets)
      music_editor.gd                 # Multi-line editor with cursor/selection
  autoload/
    music_manager.gd                  # Existing — will gain strudel_pattern support
```

---

## EPICs

### EPIC 1: Pattern Core — The Algebra

Port the five core types and the pattern algebra to GDScript. This is the foundation — everything depends on it. Must be mathematically identical to Strudel v1.2.0.

**Exit criteria:** `Pattern.new(query).fast(2).queryArc(0, 1)` returns the same haps as Strudel.

#### Story 1.1: Fraction Type
Port exact rational arithmetic. GDScript has no built-in rationals.

| Task | Description | Est |
|------|-------------|-----|
| 1.1.1 | Implement `StrudelFraction` class: construct from int, float, string, or n/d pair | 2h |
| 1.1.2 | Arithmetic: add, sub, mul, div, mod, gcd, lcm | 2h |
| 1.1.3 | Comparison: lt, gt, lte, gte, eq, ne, compare | 1h |
| 1.1.4 | Cycle ops: sam(), nextSam(), wholeCycle(), cyclePos() | 1h |
| 1.1.5 | Conversion: toFloat(), show(), floor(), ceil() | 1h |
| 1.1.6 | Test suite: verify against Strudel's fraction test cases | 2h |

#### Story 1.2: TimeSpan
| Task | Description | Est |
|------|-------------|-----|
| 1.2.1 | Implement `StrudelTimeSpan`: construct from two Fractions | 1h |
| 1.2.2 | `spanCycles`: split a span across cycle boundaries | 2h |
| 1.2.3 | `intersection`, `duration`, `cycleArc`, `withTime`, `withEnd` | 1h |
| 1.2.4 | Test suite: verify span splitting matches Strudel | 1h |

#### Story 1.3: Hap and State
| Task | Description | Est |
|------|-------------|-----|
| 1.3.1 | Implement `StrudelHap`: whole, part, value, context, stateful flag | 1h |
| 1.3.2 | `hasOnset`, `duration`, `endClipped`, `isActive`, `combineContext` | 1h |
| 1.3.3 | `withSpan`, `withValue`, `setContext`, `withLoc` (source locations) | 1h |
| 1.3.4 | Implement `StrudelState`: span + controls, setSpan/withSpan | 0.5h |

#### Story 1.4: Pattern — Foundation
| Task | Description | Est |
|------|-------------|-----|
| 1.4.1 | `StrudelPattern` class: constructor takes `query: Callable`, holds `_steps` | 1h |
| 1.4.2 | `queryArc(begin, end)`: create State, call query, return haps | 1h |
| 1.4.3 | Elemental patterns: `pure(value)`, `silence`, `gap(steps)` | 1h |
| 1.4.4 | `reify(thing)`: convert value/string/Pattern to Pattern | 1h |
| 1.4.5 | `withValue`, `fmap`, `withHapSpan`, `withHapTime`, `withQueryTime`, `withQuerySpan` | 2h |
| 1.4.6 | `filterHaps`, `filterValues`, `onsetsOnly`, `discreteOnly`, `removeUndefineds` | 1h |
| 1.4.7 | `splitQueries` | 1h |
| 1.4.8 | `firstCycle`, `firstCycleValues` (debugging helpers) | 0.5h |

#### Story 1.5: Pattern — Applicative and Monadic
| Task | Description | Est |
|------|-------------|-----|
| 1.5.1 | `appWhole`, `appBoth`, `appLeft`, `appRight` | 3h |
| 1.5.2 | `bindWhole`, `bind`, `join`, `outerBind`, `outerJoin`, `innerBind`, `innerJoin` | 3h |
| 1.5.3 | `squeezeJoin`, `squeezeBind`, `resetJoin`, `restartJoin` | 3h |
| 1.5.4 | Test: verify `pure(x).appBoth(pure(y))` matches Strudel | 2h |

#### Story 1.6: Pattern — Combinators
| Task | Description | Est |
|------|-------------|-----|
| 1.6.1 | `stack(...)`, `sequence(...)` / `fastcat(...)`, `slowcat(...)` / `cat(...)` | 3h |
| 1.6.2 | `fast(factor)`, `slow(factor)`, `early(offset)`, `late(offset)` | 2h |
| 1.6.3 | `every(n, func)` / `firstOf`, `lastOf` | 1h |
| 1.6.4 | `rev()` | 1h |
| 1.6.5 | `compress`, `focus`, `zoom` | 2h |
| 1.6.6 | `layer(...)`, `superimpose(...)` | 1h |
| 1.6.7 | `ply(factor)` | 0.5h |
| 1.6.8 | `inside(factor, f)`, `outside(factor, f)` | 1h |

#### Story 1.7: Pattern — Composers (Arithmetic + Structure)
| Task | Description | Est |
|------|-------------|-----|
| 1.7.1 | Composer framework: generate set/keep/keepif/add/sub/mul/div + 8 "hows" | 3h |
| 1.7.2 | `struct`, `mask`, `reset`, `restart` (binary composers) | 2h |
| 1.7.3 | Test: `"0 1 2 3".add("<0 5>")` matches Strudel output | 2h |

#### Story 1.8: Euclidean Rhythms
| Task | Description | Est |
|------|-------------|-----|
| 1.8.1 | Port Bjorklund algorithm (`bjork()`) | 1h |
| 1.8.2 | `euclid(pulses, steps)`, `euclidRot(pulses, steps, rotation)` | 1h |
| 1.8.3 | `euclidLegato`, `euclidLegatoRot` | 1h |
| 1.8.4 | Test: verify `euclid(3,8)` = `[1,0,0,1,0,0,1,0]` | 0.5h |

#### Story 1.9: Continuous Signals
| Task | Description | Est |
|------|-------------|-----|
| 1.9.1 | `signal(func)`, `steady(value)` | 1h |
| 1.9.2 | `saw`, `isaw`, `sine`, `cosine`, `tri`, `square`, `rand` | 2h |
| 1.9.3 | `range(min, max)`, `rangex(min, max)`, `segment(n)` | 1h |

---

### EPIC 2: Mini-Notation Parser

Port the krill PEG grammar to a GDScript recursive-descent parser. This is the primary user input format.

**Exit criteria:** `mini("bd sd [hh hh] cp")` produces the same Pattern as Strudel.

#### Story 2.1: Lexer / Tokenizer
| Task | Description | Est |
|------|-------------|-----|
| 2.1.1 | Token types: atom, number, rest(~), open/close brackets, comma, star, slash, angle brackets, parens, question mark, colon, exclamation, at, pipe, whitespace | 2h |
| 2.1.2 | Tokenize a mini-notation string into a token stream | 2h |
| 2.1.3 | Test: verify token stream for `"bd sd [hh*2, cp?] <sn bd>/3"` | 1h |

#### Story 2.2: Parser (Recursive Descent)
| Task | Description | Est |
|------|-------------|-----|
| 2.2.1 | AST node types: AtomNode, PatternNode(alignment: seq/stack/polymeter/rand), ElementNode, OperatorNode(stretch/replicate/bjorklund/degradeBy) | 2h |
| 2.2.2 | Parse sequences: space-separated atoms | 2h |
| 2.2.3 | Parse stacks: comma-separated sequences | 2h |
| 2.2.4 | Parse groups: `[...]` | 1h |
| 2.2.5 | Parse operators: `*n`, `/n`, `(p,s,r)`, `?`, `!n`, `@w` | 3h |
| 2.2.6 | Parse angle brackets: `<...>` (slowcat) | 1h |
| 2.2.7 | Parse polymeter: `{...}` and `{...}%n` | 2h |
| 2.2.8 | Source locations: track start/end offset for every leaf node | 2h |
| 2.2.9 | Error messages with line/column | 1h |

#### Story 2.3: AST to Pattern
| Task | Description | Est |
|------|-------------|-----|
| 2.3.1 | Port `patternifyAST()`: walk AST, produce Pattern tree | 3h |
| 2.3.2 | `applyOptions()`: handle stretch, replicate, bjorklund, degradeBy, tail, range operators | 2h |
| 2.3.3 | Alignment dispatch: sequence (default), stack, polymeter, polymeter_slowcat, rand, feet | 2h |
| 2.3.4 | `getLeafLocations()`: extract source locations for highlighting | 1h |
| 2.3.5 | `mini(string)` top-level function with string parser registration | 1h |
| 2.3.6 | Test: compare `mini("bd sd [hh hh] cp").firstCycleValues` against Strudel | 2h |

---

### EPIC 3: Scheduler + GDSiON Bridge

Connect the pattern engine to real-time audio output through GDSiON.

**Exit criteria:** `mini("c4 e4 g4 c5").note()` plays the notes in time through GDSiON.

#### Story 3.1: Clock
| Task | Description | Est |
|------|-------------|-----|
| 3.1.1 | Port zyklus.mjs clock to GDScript using Godot's frame timing | 2h |
| 3.1.2 | Configurable interval, latency, overlap | 1h |

#### Story 3.2: Cyclist (Scheduler)
| Task | Description | Est |
|------|-------------|-----|
| 3.2.1 | Port Cyclist: cps tracking, num_cycles_at_cps_change, query window | 3h |
| 3.2.2 | `setPattern(pat)`, `start()`, `stop()`, `pause()`, `setCps(cps)` | 1h |
| 3.2.3 | `now()`: current cycle position for visualization | 1h |
| 3.2.4 | onTrigger callback with (hap, deadline, duration, cps, targetTime) | 1h |

#### Story 3.3: SiON Trigger Bridge
| Task | Description | Est |
|------|-------------|-----|
| 3.3.1 | Map hap.value to SiON note_on params: note number, voice, duration | 2h |
| 3.3.2 | Handle `note`, `n`, `s`, `freq` value types (like Strudel's controls) | 2h |
| 3.3.3 | Voice mapping: `s("bd sd hh")` maps to drumkit voices, `note("c4")` maps to melodic voices | 2h |
| 3.3.4 | Integrate with existing MusicManager (bridge Cyclist output to SiON driver) | 2h |

#### Story 3.4: Controls
| Task | Description | Est |
|------|-------------|-----|
| 3.4.1 | Port control registration: `note()`, `s()`, `n()`, `gain()`, `speed()` | 2h |
| 3.4.2 | `cps()` / `cpm()` pattern-driven tempo | 1h |
| 3.4.3 | `velocity()`, `pan()`, `cutoff()` — mapped to SiON effect params | 2h |

---

### EPIC 4: Music Drawer — Editor UI

Build the in-game editor panel modeled on Strudel's REPL, using Godot's `_draw()` rendering.

**Exit criteria:** User types mini-notation in the drawer, sees pianoroll, hears music, active notes highlight in the text.

#### Story 4.1: Music Drawer Panel
| Task | Description | Est |
|------|-------------|-----|
| 4.1.1 | `music_drawer.gd`: slide-out panel (like debug_drawer.gd) with play/stop/BPM controls | 3h |
| 4.1.2 | Panel layout: toolbar at top, editor lines below, pianoroll at bottom | 2h |
| 4.1.3 | Play/Stop button: creates Cyclist, sets pattern from editor content | 1h |
| 4.1.4 | BPM slider/field: maps to cyclist.setCps() | 1h |
| 4.1.5 | Keyboard shortcut to open drawer (e.g., Ctrl+M) | 0.5h |

#### Story 4.2: Music Line — Text Editing
| Task | Description | Est |
|------|-------------|-----|
| 4.2.1 | `music_line.gd`: single line with text input, cursor, selection | 3h |
| 4.2.2 | Keyboard handling: type, backspace, delete, arrows, home/end, Ctrl+A/C/V/X | 2h |
| 4.2.3 | Multi-line support: up/down arrows, enter to create new line | 2h |
| 4.2.4 | Syntax coloring: mini-notation keywords, brackets, operators | 3h |
| 4.2.5 | Live evaluation: re-parse on every keystroke (debounced), update pattern | 2h |

#### Story 4.3: Source Highlighting (The Key Visual Feedback)
| Task | Description | Est |
|------|-------------|-----|
| 4.3.1 | Track mini-notation leaf source locations through the pattern | 2h |
| 4.3.2 | Each frame: query active haps, extract context.locations | 1h |
| 4.3.3 | Draw highlight rectangles behind active leaf text spans | 2h |
| 4.3.4 | Color coding: match hap value color or default highlight color | 1h |
| 4.3.5 | Fade: highlights fade out as the hap progresses (opacity = remaining %) | 1h |

#### Story 4.4: Pianoroll Visualization
| Task | Description | Est |
|------|-------------|-----|
| 4.4.1 | Port `__pianoroll()` rendering to Godot `_draw()` | 3h |
| 4.4.2 | Scrolling time window: configurable cycles, playhead position | 2h |
| 4.4.3 | Value axis: auto-range from visible haps, fold mode | 2h |
| 4.4.4 | Active/inactive hap coloring, playhead line | 1h |
| 4.4.5 | Labels on hap bars (note names, sample names) | 1h |
| 4.4.6 | Options: vertical/horizontal, flipTime, flipValues | 1h |

#### Story 4.5: Live Editing / Hot Reload
| Task | Description | Est |
|------|-------------|-----|
| 4.5.1 | On edit: re-parse mini-notation, compile to new Pattern | 1h |
| 4.5.2 | Hot-swap pattern on Cyclist without restarting (Cyclist.setPattern) | 1h |
| 4.5.3 | Flash feedback on successful eval (brief screen flash like Strudel) | 1h |
| 4.5.4 | Error display: parse errors shown inline below the line | 1h |

---

### EPIC 5: RCON Integration + Debug Aspects

Wire the Strudel system into the existing RCON/console infrastructure.

**Exit criteria:** `strudel "bd sd [hh hh] cp"` from RCON plays the pattern; debug aspects show scheduler state.

#### Story 5.1: RCON Commands
| Task | Description | Est |
|------|-------------|-----|
| 5.1.1 | `strudel <mini-notation>` — parse and play | 1h |
| 5.1.2 | `strudel stop` — stop the cyclist | 0.5h |
| 5.1.3 | `strudel cps <value>` — set cycles per second | 0.5h |
| 5.1.4 | `strudel hush` — silence all patterns | 0.5h |
| 5.1.5 | Console autocomplete for strudel commands | 1h |

#### Story 5.2: Debug Aspects
| Task | Description | Est |
|------|-------------|-----|
| 5.2.1 | Register: `strudel/scheduler`, `strudel/haps`, `strudel/pattern`, `strudel/parse` | 1h |
| 5.2.2 | Log scheduler ticks, hap triggers, pattern compilation, parse events | 1h |
| 5.2.3 | Visual: current cycle position, active hap count, CPS overlay | 1h |

---

## Implementation Order (Depth-First Path)

The single end-to-end path that must work first:

```
[User types "bd sd hh cp" in Music Drawer]
       ↓
[mini parser tokenizes + parses to AST]
       ↓
[patternifyAST converts AST to Pattern of string values]
       ↓
[Pattern.note() wraps values as {note: "bd"} objects]
       ↓
[Cyclist queries Pattern for haps in upcoming time window]
       ↓
[SiON Trigger bridge converts haps to SiONDriver.note_on calls]
       ↓
[GDSiON synthesizes audio output]
       ↓
[Pianoroll draws hap bars scrolling across time]
       ↓
[Source highlighter illuminates "bd" "sd" "hh" "cp" as they play]
```

### Phase 1: Silent Algebra (EPICs 1.1–1.6)
Get the pattern engine producing correct haps without audio.
Validate by comparing `firstCycleValues` against Strudel.

### Phase 2: Make Sound (EPIC 3)
Connect scheduler → GDSiON bridge. One pattern plays notes.

### Phase 3: Mini-Notation (EPIC 2)
Parse `"bd sd [hh hh] cp"` into patterns. Now users can type music.

### Phase 4: See It (EPIC 4.3–4.4)
Pianoroll + source highlighting. The visual feedback loop closes.

### Phase 5: Edit It (EPIC 4.1–4.2, 4.5)
The Music Drawer UI. Live editing with hot-swap.

### Phase 6: Wire It (EPIC 5)
RCON commands, debug aspects, console integration.

### Phase 7: Complete (EPICs 1.7–1.9, remaining combinators)
Composers, signals, advanced combinators. Full Strudel compatibility.

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Fraction arithmetic performance in GDScript | Profile early. GDScript ints are 64-bit. If too slow, critical path can move to a GDExtension later. Strudel's own docs note Fraction.js Farey sequences made querying 20x slower — we can avoid that. |
| PEG parser complexity (303-line grammar) | Port as recursive descent, not PEG engine. Grammar is well-structured. |
| GDSiON single-driver constraint | One driver shared between MusicManager (MML layers) and Strudel (note_on). May need to sequence or priority-gate. |
| Mini-notation edge cases | Pin to v1.2.0 test suite. Run same inputs, compare outputs. |
| Frame-rate dependent scheduling | Use Godot's `_physics_process` for clock ticks (fixed 60Hz), not `_process`. |
| Live edit latency | Pattern swap is instant (Cyclist.setPattern is atomic). Parse is the bottleneck — debounce to 100ms. |

---

## File Size Estimates

| Component | Strudel JS | GDScript Est | Notes |
|-----------|-----------|-------------|-------|
| Fraction | ~130 lines (+ fraction.js dep) | ~250 lines | No external dep, self-contained |
| TimeSpan | 117 lines | ~150 lines |  |
| Hap | 183 lines | ~180 lines |  |
| State | 28 lines | ~30 lines |  |
| Pattern (core) | 872 lines | ~900 lines | Up to `drawLine()` |
| Pattern (combinators) | ~2400 lines | ~2000 lines | Registered functions, less metaprogramming |
| Mini parser | 2600 lines (generated) + 261 lines | ~800 lines | Hand-written recursive descent |
| Cyclist | 139 lines | ~150 lines |  |
| Clock | 54 lines | ~60 lines |  |
| Pianoroll | 317 lines | ~350 lines | Godot _draw() instead of Canvas2D |
| Highlight | 139 lines | ~150 lines |  |
| SiON Bridge | N/A (new) | ~200 lines |  |
| Music Drawer UI | N/A (new) | ~500 lines |  |
| **Total** | **~7200 lines** | **~5700 lines** |  |

---

## Compatibility Testing Strategy

For each ported component, maintain a test file that runs the same inputs as Strudel's test suite and compares outputs:

```gdscript
# test_strudel_pattern.gd
func test_fast():
    var pat = S.pure("a").fast(2)
    var haps = pat.queryArc(0, 1)
    assert(haps.size() == 2)
    assert(haps[0].value == "a")
    assert(haps[0].whole.begin.eq(S.frac(0)))
    assert(haps[0].whole.end.eq(S.frac(1, 2)))
```

Source of truth: `/var/tumu/repos/strudel-v1.2.0/packages/core/test/`
