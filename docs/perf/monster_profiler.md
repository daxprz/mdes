# Monster Section Profiler

The quadruped monster (`scripts/enemies/quadruped_monster.gd`) has a built-in section profiler that measures wall-clock time for each major phase of `_physics_process`.

## How It Works

At the top of `_physics_process`, `_perf_start()` captures the current `Time.get_ticks_usec()`. After each section, `_perf_mark("label", start)` records the elapsed microseconds since the last mark.

Results are stored in two dictionaries on the monster instance:
- `_perf_sections` — last-frame times (overwritten every frame)
- `_perf_peak_sections` — highest observed time per section (accumulates until reset)
- `_perf_total_usec` — total frame time
- `_perf_peak_total` — highest observed total

The FPS overlay reads these during snapshots and resets peaks after display.

## Probe Sections

Listed in execution order within `_physics_process`:

| Section | What It Measures | Typical | Concern Above |
|---------|-----------------|---------|---------------|
| `chain_logic` | Chained state: sleep check, suspend physics (gravity + double chain constraint + move_and_slide), limb rigidity. Returns early if chained+asleep or chained+suspended. | 3-10us | 100us |
| `movement_blend` | `_update_movement_blend()` + gravity application | 15-30us | 200us |
| `ai_state` | Full AI state machine tick: chase, attack selection, precog start, patrol, standdown transitions | 10-20us idle, 4-6ms during precog phase changes | 10ms |
| `precog_tick` | `_precog_build_graph_tick()` — builds leap connectivity graph edges (physics raycasts) | 1-2us idle, 20-50ms active | 50ms |
| `foot_push` | `_update_foot_push()` or `_update_leap_collision()` — foot forces on body, or leap collision | 10-15us | 200us |
| `chain_clamp` | `_apply_chain_constraints()` — iterates all tethers, raycasts when airborne | 0-3us unchained, 10-50us chained | 500us |
| `move_slide` | `move_and_slide()` — Godot's built-in collision resolution | 15-30us | 200us |
| `pose_solve` | Spine update, leg IK, gait cycle, foot planting, leap pose | 170-250us | 500us |
| `rigidity` | `_enforce_spine_rigid()` + limb length enforcement + hitbox position updates | 80-140us | 300us |
| `hitbox_fx` | Hitbox position updates, blood particles, visual effects, `queue_redraw()` | 25-50us | 200us |

## Reading the Data

In a perf snapshot, monster profiler data appears as:

```
quadruped_monster (@CharacterBody2D@123) state=CHASE pos=(500,890) hp=1500
  physics_frame: 380us (0.4ms) | peak: 45000us (45.0ms)
    precog_tick      last:     1us  peak: 44735us <<<
    ai_state         last:    12us  peak:  4308us <<<
    pose_solve       last:   168us  peak:   205us
    rigidity         last:    85us  peak:   136us
    ...
```

- **`last`** — time during the most recent frame
- **`peak`** — highest time since last reset
- **`<<<`** — flagged if peak > 2000us (2ms)
- Sections sorted by peak descending

## Key Lessons Learned

### The precog graph builder was the #1 spike source

Before optimization (v0.10.75): `precog_tick` peaked at **340-453ms** — a full half-second freeze. The root cause was combinatorial physics queries:

```
5 platform pairs per frame
  x N launch points per pair
    x 5 landing samples per pair
      x 7 flight times per sample
        x ~15 intersect_shape() calls per arc
= tens of thousands of physics queries per frame
```

Fix (v0.10.76):
1. **Time budget**: 2ms per frame instead of fixed 5 pairs (always does at least 1 pair)
2. **Reduced constants**: flight times 7→5, arc steps 40→32, landing samples 5→4, clearance step 2→3
3. Result: peaks at ~45ms for a single expensive pair, most frames well under 2ms

### move_and_slide() is NOT expensive

Despite initial suspicion, `move_and_slide()` consistently measures 15-30us even during high-action frames. The Godot engine's collision resolution is well-optimized for simple cases.

### The real cost is physics QUERIES, not physics SIMULATION

`intersect_shape()` and `intersect_ray()` are the expensive calls. Each one queries the physics server. When called hundreds of times per frame (arc clearance checking), they dominate the frame budget. The actual physics step (`move_and_slide`) is cheap by comparison.

### Delta clamping prevents secondary damage

A 400ms spike causes a 400ms delta on the next frame. Without clamping, this means:
- Gravity applies 400ms of acceleration → body rockets downward
- Foot push applies 400ms of force → legs fly off-screen
- Gait phase advances 400ms → stride animation teleports

The fix: `delta = minf(delta, 0.033)` at the top of `_physics_process`. This caps the effective delta at 2x the normal 60fps step. The frame still takes longer than ideal, but the physics don't go haywire.

## Adding New Probes

To add a new section probe:

```gdscript
# In _physics_process, between existing marks:
_t = _perf_mark("my_section", _t)

# ... your code ...

_t = _perf_mark("next_section", _t)
```

The `_perf_mark` function records elapsed time since the previous mark and returns the current tick for the next mark. Results automatically appear in snapshots.
