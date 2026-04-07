# Music Composition Architecture

## Context

The music system currently has no data abstraction layer. Everything flows through the MusicDrawer (a dev UI) which owns the only line parser, or through a flat "segment queue" bolted onto MusicManager. The result:

- The drawer is coupled to playback — game code can't use music without the drawer
- Per-voice gain/controls break when segments are stacked into one pattern
- No concept of musical structure (movements, bridges, transitions)
- No playback history or lookahead

The goal: a proper **Composition / Movement / Bridge / Turnaround / Record** architecture where music is data — independent of any UI.

## Terminology

| Term | Definition |
|------|-----------|
| **Composition** | The full piece — all movements, bridges, turnarounds. Pure data. |
| **Movement** | A section with a unique feel/tone, lasting N bars. N can be infinite (procedural loops). |
| **Bridge** | A transition between two movements, lasting M bars. M is always fixed and finite (usually 1-2). |
| **Turnaround** | A toggleable variation of a movement. When activated, it modifies the current movement for a few bars, then hands off to a bridge. |
| **Record** | What was actually played / is playing — history + playhead + cued future bars. |
| **Bar** | One cycle of pattern output. The atomic unit of playback scheduling. |
| **PlayHead** | High-precision position within the current bar. |
| **Track** | One voice/instrument line within a movement (e.g., "sub", "pad", "sparkle"). |

## New Files

```
scripts/music/composition/
  strudel_line_compiler.gd    — Line parser extracted from drawer (~800 lines)
  composition.gd              — Composition: movements + bridges + turnarounds
  movement.gd                 — Movement: N tracks, N bars (-1 = infinite)
  movement_bridge.gd          — Bridge: M tracks, M bars (always finite)
  turnaround.gd               — Turnaround: toggleable, leads to bridge
  track.gd                    — MusicTrack: one voice's compiled pattern + metadata
  composition_loader.gd       — JSON + .strudel files -> Composition

scripts/music/playback/
  record.gd                   — Played bars + cued bars + signals
  bar.gd                      — MusicBar: one cycle, references movement/bridge/turnaround
  play_head.gd                — High-precision position in current bar
  bar_scheduler.gd            — Detects cycle boundaries, advances Record, hot-swaps cyclist

data/compositions/
  title_screen.json           — First composition definition
```

## Modified Files

| File | Change |
|------|--------|
| `scripts/music/ui/music_drawer.gd` | Remove ~800 lines of parser. Delegate to StrudelLineCompiler. Read Record for playback display. |
| `scripts/autoload/music_manager.gd` | Remove segment queue. Add Composition/Record/BarScheduler. New API: `load_composition()`, `play_composition()`, `transition_to()`, `activate_turnaround()`. |
| `scripts/ui/title_screen.gd` | Use `MusicManager.load_composition()` / `transition_to()` instead of scene_load_segment. |
| `scripts/autoload/rcon.gd` | `_merge_continuation_lines` and `_expand_stacks_for_drawer` move to StrudelLineCompiler. Scene RCON commands become composition commands. |

## Data Model

### MusicTrack
```gdscript
class_name MusicTrack extends RefCounted
var name: String            # "sub", "pad", "sparkle"
var pattern: StrudelPattern # Compiled pattern
var voice: String           # "sine", "sawtooth"
var gain: float             # Track-level gain (0.0-1.0)
var controls: Dictionary    # {lpf, room, etc.}
var signal_controls: Array  # Signal-modulated controls
var source_text: String     # Original line text
```

### Movement
```gdscript
class_name Movement extends RefCounted
var id: String              # "light", "dark"
var bars: int               # -1 = infinite loop
var cps: float              # Tempo
var tracks: Array[MusicTrack]
var turnarounds: Array[Turnaround]
var strudel_file: String
func get_stacked_pattern() -> StrudelPattern  # All tracks combined (lazy, cached)
```

### MovementBridge
```gdscript
class_name MovementBridge extends RefCounted
var id: String              # "bridge_to_dark"
var bars: int               # Always finite (1-2)
var cps: float
var from_movement_id: String
var to_movement_id: String
var tracks: Array[MusicTrack]
func get_stacked_pattern() -> StrudelPattern
```

### Turnaround
```gdscript
class_name Turnaround extends RefCounted
var id: String              # "light_wind_down"
var bars: int               # Fixed duration before bridge
var tracks: Array[MusicTrack]  # Override tracks
var target_bridge_id: String   # Which bridge to enter after turnaround completes
```

### Composition
```gdscript
class_name Composition extends RefCounted
var id: String
var movements: Dictionary     # id -> Movement
var bridges: Dictionary       # id -> MovementBridge
var default_movement_id: String
func get_bridge_between(from_id, to_id) -> MovementBridge
```

### MusicBar
```gdscript
class_name MusicBar extends RefCounted
var movement: Movement
var turnaround: Turnaround    # null if not in turnaround
var bridge: MovementBridge    # null if not in bridge
var index: int                # Nth bar into the movement/turnaround/bridge
var cycle_number: int         # Absolute cycle
func get_pattern() -> StrudelPattern  # bridge > turnaround > movement
func get_tracks() -> Array[MusicTrack]
func get_cps() -> float
```

### PlayHead
```gdscript
class_name PlayHead extends RefCounted
var cycle_position: float     # [0.0, 1.0) within current bar
var absolute_cycle: float     # Total cycles since start
var bar_index: int            # Index into Record.played_bars
```

### MusicRecord
```gdscript
class_name MusicRecord extends RefCounted
signal bar_completed(bar)
signal bar_started(bar)
signal cue_changed(cued)

var composition: Composition
var played_bars: Array[MusicBar]
var play_head: PlayHead
var cued_bars: Array[MusicBar]    # Upcoming bars (modifiable by game events)
var is_playing: bool

func advance_bar()                # Pop cued -> played, emit signals
func replace_cued(new_cued)       # Game/manager changes what's coming
```

### BarScheduler
```gdscript
class_name BarScheduler extends RefCounted
var record: MusicRecord
var cyclist: StrudelCyclist

func process()                    # Called every frame, detects bar boundaries
func transition_to_movement(target_id, bridge_id)  # Replaces cued bars
func activate_turnaround(turnaround)               # Inserts turnaround -> bridge -> target
```

## Composition JSON Format

```json
{
  "id": "title_screen",
  "default_movement": "light",
  "movements": [
    {"id": "light", "file": "intro_light", "bars": -1},
    {"id": "dark",  "file": "intro_dark",  "bars": -1}
  ],
  "bridges": [
    {"id": "bridge_to_dark",  "file": "intro_bridge_to_dark",  "bars": 1, "from": "light", "to": "dark"},
    {"id": "bridge_to_light", "file": "intro_bridge_to_light", "bars": 1, "from": "dark",  "to": "light"}
  ],
  "turnarounds": []
}
```

Existing `.strudel` files are unchanged. The JSON is a structural layer on top.

## Data Flow

```
title_screen.json
  -> CompositionLoader.load_from_json()
    -> For each movement/bridge:
        -> StrudelLineCompiler.compile_strudel_file(path)
          -> merge_continuation_lines() + expand_stacks()
          -> For each line: parse_line() -> compile_parsed()
          -> Returns Array[MusicTrack] + cps
    -> Assembles Composition with typed Movement/Bridge/Turnaround objects

MusicManager.play_composition(composition)
  -> Creates MusicRecord, BarScheduler
  -> Starts first bar of default movement
  -> BarScheduler.process() every frame:
      -> Updates PlayHead from cyclist.now()
      -> At cycle boundary: advance_bar(), hot-swap cyclist pattern, refill cued bars

Game event (monster wakes):
  -> MusicManager.transition_to("dark")
    -> BarScheduler: looks up bridge_between("light","dark")
    -> replace_cued: [bridge_to_dark/0, dark/0, dark/1, dark/2, dark/3]
    -> Current bar plays to completion
    -> Next bar is bridge, then dark movement loops
```

## Bar Boundary Timeline Example

```
Bar 5: Movement "light", index 1   [playing at cycle 5.3]
  cued: [light/2, light/3, light/0, light/1]

-> monster_woke fires -> MusicManager.transition_to("dark")
  cued becomes: [bridge_to_dark/0, dark/0, dark/1, dark/2, dark/3]

Bar 5 completes (cycle 6.0)
Bar 6: Bridge "bridge_to_dark"     -> cyclist.set_pattern(bridge.get_stacked_pattern())
Bar 7: Movement "dark", index 0   -> cyclist.set_pattern(dark.get_stacked_pattern())
... dark loops indefinitely
```

## StrudelLineCompiler Extraction

The largest code change. Move from `music_drawer.gd` to `strudel_line_compiler.gd`:

| Method | Drawer Lines | Notes |
|--------|-------------|-------|
| `AUDIO_CONTROL_METHODS` | 123-141 | Constant |
| `SIGNAL_NAMES` | 144 | Constant |
| `_parse_signal_expr` | 146-225 | Already static |
| `_parse_line_text` -> `parse_line` | 963-1303 | Remove `line[]=` side-effects; return in result dict |
| `_split_top_level_commas` | 1313-1338 | Already static |
| `_eval_sub_expr` | 1341-1460 | Already static |
| `_parse_transform_fn` | 1463-1499 | Already static |
| `_parse_method_chain_transform` | 1502-1548 | Already static |
| `_parse_transform_arg` | 1551+ | Already static |
| `_apply_deferred_ops` | 1660-1797 | Already static |
| `_compile_parsed` | 1803-1834 | Uses `_eval_sub_expr`, `_apply_deferred_ops` |
| `_parse_viz_options` | 451-482 | Already static |

Also extract from `rcon.gd`:

| Method | RCON Lines | Notes |
|--------|-----------|-------|
| `_merge_continuation_lines` | 2027+ | Static text processing |
| `_expand_stacks_for_drawer` -> `expand_stacks` | 1999-2024 | Uses `_split_top_level_commas` |

New convenience method:
```gdscript
static func compile_strudel_file(path: String) -> Dictionary:
    # Returns {tracks: Array[MusicTrack], cps: float}
    # Handles file reading, merging, expanding, parsing, compiling
```

After extraction, `music_drawer.gd` delegates:
```gdscript
# Old: var parsed = _parse_line_text(line_dict)
# New: var parsed = StrudelLineCompiler.parse_line(line_dict)
```

The `_parse_line_text` side-effects (`line["name"] = ...`, `line["viz"] = ...`) move to the drawer's `_resolve_line`, which applies them AFTER calling the compiler.

## MusicManager Changes

**Remove:** `_segments`, `_segment_queue`, `_current_segment`, `_segment_cycles_remaining`, `_last_cycle_boundary`, `scene_load_segment()`, `scene_play()`, `scene_transition()`, `scene_jump()`, `_check_segment_boundary()`, `_advance_segment_queue()`, `scene_get_segments()`

**Add:**
```gdscript
var _composition: Composition = null
var _record: MusicRecord = null
var _bar_scheduler: BarScheduler = null

func load_composition(json_path: String) -> String
func play_composition(composition: Composition = null) -> void
func get_record() -> MusicRecord
func transition_to(movement_id: String) -> void
func activate_turnaround(turnaround_id: String) -> void
```

**In `_process()`:** Replace `_check_segment_boundary()` with `_bar_scheduler.process()`

**Unchanged:** `strudel_play()`, `strudel_play_batch()`, `strudel_stop()`, `_cyclist`, `_sion_trigger`, intensity/layer system, audio bus effects, MML/score code, `record_start()`, `record_stop()`.

## A/B Test Impact Analysis

### Summary: A/B tests are unaffected by this architecture change.

The 47 existing A/B tests (`data/tests/ab_*.json`, `music_ab_*.json`) use a completely separate code path from the Composition system:

```
A/B Test Path:                    Composition Path:
  strudel ref <pattern>             CompositionLoader.load_from_json()
  strudel edit <pattern>            MusicManager.play_composition()
  strudel record start/stop         BarScheduler.process()
  ab_compare ref.wav ours.wav       MusicManager.transition_to()
```

These paths do not overlap. Here is the detailed analysis:

### What A/B Tests Touch

| RCON Command | Used By A/B Tests | Affected By Composition? |
|-------------|-------------------|-------------------------|
| `strudel edit <pattern>` | Yes (all tests) | **No** — drawer pipeline unchanged |
| `strudel ref <pattern>` | Yes (all tests) | **No** — external Node.js server |
| `strudel record start/stop` | Yes (all tests) | **No** — `record_start()/stop()` on MusicManager unchanged |
| `ab_compare` | Yes (all tests) | **No** — WAV spectral analysis, no music system deps |
| `ab_harmonics` | Yes (some tests) | **No** — external Python script |
| `ab_show` | Yes (some tests) | **No** — texture overlay |
| `strudel stop` | Yes (setup) | **No** — unchanged |
| `strudel cps` | Yes (some) | **No** — sets cyclist CPS directly |
| `scene_*` commands | **No** | Removed and replaced |

### Why No Changes Are Needed

1. **A/B tests use `strudel edit`**, which loads lines into the drawer and calls `_play_current()`. The Composition system does NOT change this path. The drawer still parses lines — it just delegates to `StrudelLineCompiler` (same logic, different location).

2. **Audio recording** (`record_start/stop`) attaches to the Music audio bus. It captures whatever is playing regardless of whether the source is the Composition system, the drawer, or raw `strudel_play()`. No change needed.

3. **Spectral comparison** (`ab_compare`, `ab_harmonics`) operates on WAV files. It has zero coupling to how patterns are scheduled.

4. **Test setup/teardown** (`strudel stop`, `music off`, `wait 1`) silences the engine before each test. This is unaffected — `strudel_stop()` is unchanged.

### What WOULD Need A/B Tests: New Composition Features

If we want to **test composition transitions** (bridge timing, turnaround smoothness, CPS changes at bar boundaries), we should create NEW A/B tests:

```json
{
  "name": "ab_composition_bridge",
  "description": "A/B: bridge transition timing — light -> bridge -> dark",
  "script": [
    "ab_dismiss",
    "strudel stop",
    "music off",
    "wait 1",
    "ab_dir ab_composition_bridge",
    "composition load title_screen",
    "composition play",
    "strudel record start",
    "wait 12",
    "composition transition dark",
    "wait 12",
    "strudel stop",
    "strudel record stop bridge_test",
    "check ab_compare bridge_ref.wav bridge_test.wav 0.08 0.5 500 0"
  ]
}
```

These would be added in Phase 4 (Scheduler verification) as new tests, not modifications to existing ones.

### Potential Edge Case: Drawer Parser Extraction

Phase 1 (StrudelLineCompiler extraction) changes how `strudel edit` lines are parsed — the drawer calls `StrudelLineCompiler.parse_line()` instead of its own `_parse_line_text()`. If the extraction introduces any parsing difference, ALL 47 A/B tests would catch it because they compare spectral output against reference recordings. This makes the A/B suite an excellent regression gate for Phase 1.

**Recommendation:** Run the full A/B suite after Phase 1 as a regression check. No test modifications needed — the existing suite already covers this.

## Implementation Order

| Phase | Step | Description | Depends On |
|-------|------|-------------|------------|
| **1: Extract** | 1 | Create `strudel_line_compiler.gd` — copy methods from drawer | -- |
| | 2 | Update drawer to delegate to StrudelLineCompiler | 1 |
| | 3 | Update `music_manager.gd` scene_load_segment to use compiler | 1 |
| | 4 | Update `rcon.gd` — move merge/expand, fix parser refs | 1 |
| | 5 | **Gate: Run A/B suite** — all 47 tests must pass identically | 1-4 |
| **2: Data** | 6 | Create Track, Movement, MovementBridge, Turnaround, Composition | -- |
| | 7 | Create Bar, PlayHead, Record | -- |
| **3: Loader** | 8 | Create CompositionLoader | 1, 6 |
| | 9 | Create `title_screen.json` | -- |
| | 10 | **Verify**: loader produces valid Composition from JSON via RCON | 8-9 |
| **4: Scheduler** | 11 | Create BarScheduler | 7 |
| | 12 | Wire into MusicManager (new API, parallel with old segment queue) | 8, 11 |
| | 13 | **Verify via RCON**: `composition play`, `transition`, inspect Record | 12 |
| | 14 | Create composition-specific A/B tests (bridge timing, movement swap) | 12 |
| **5: Migrate** | 15 | Update `title_screen.gd` to use Composition API | 12 |
| | 16 | Remove old segment queue code from MusicManager | 15 |
| | 17 | Update drawer to read Record for playback/cue display | 12 |
| | 18 | Update RCON scene commands -> composition commands | 12 |
| | 19 | **Gate: Run full A/B suite + new composition tests** | 14-18 |

Phase 1 is a **pure refactor** — zero behavior change, can ship independently.
Phase 2-4 builds the new system alongside the old (no removal yet).
Phase 5 migrates callers and removes the old code.

## Verification

1. **After Phase 1**: `strudel load intro_light` -> same 6-voice playback, same pianoroll, same sound. **Run all 47 A/B tests as regression gate.**
2. **After Phase 3**: RCON `composition load title_screen` -> "OK: 2 movements, 2 bridges"
3. **After Phase 4**: RCON `composition play` -> light theme plays; `composition transition dark` -> bridge -> dark
4. **After Phase 5**: Title screen startup -> light plays; wake monster -> bridge -> dark; kill monster -> bridge -> light
5. **Record inspection**: RCON `composition record` -> shows played bars, cued bars, current playhead position
6. **Final gate**: All 47 A/B tests pass + new composition A/B tests pass
