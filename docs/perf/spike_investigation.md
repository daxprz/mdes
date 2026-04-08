# Case Study: The 450ms Precog Spike

How we found and fixed the biggest performance problem in DAX — a half-second freeze every time the monster started planning a leap.

## The Symptom

During gameplay, FPS would drop to **2 FPS** (~500ms per frame) when the monster entered precognition state. The player experienced a visible freeze, and the monster's legs would wildly flail when it recovered.

## Investigation Methodology

### Step 1: Build the tools

The existing FPS counter showed drops but couldn't explain them. We built a full performance monitor:

1. **Godot `Performance` singleton** — 19 built-in monitors (process time, physics time, draw calls, memory, objects)
2. **Auto-spike detection** — captures a snapshot when FPS < 40, with 5s cooldown to prevent self-inducing cycles
3. **Entity census** — lists every entity with state, position, HP, process flags
4. **Section profiler** — microsecond-precision timing probes inside `_physics_process`

### Step 2: Capture spikes

Ran the leaping test suite with perf monitoring enabled. Auto-spike captured 3 events, each showing:

```
Physics: 454.7ms [ALERT]
```

But the snapshot couldn't tell us WHERE inside `_physics_process` the time was spent.

### Step 3: Add section probes

Inserted `_perf_mark()` calls between each major section of `_physics_process`. Initial probes divided the frame into 7 sections: chain_logic, movement_blend, ai_state, **physics_move**, pose_solve, rigidity, hitbox_fx.

First result:
```
physics_move     last:    33us  peak:396876us <<<
```

`physics_move` was the culprit — but it contained 5 different operations.

### Step 4: Sub-divide the suspect

Split `physics_move` into 4 sub-sections: precog_tick, foot_push, chain_clamp, move_slide.

Second result:
```
precog_tick      last:     1us  peak:452722us <<<
move_slide       last:    20us  peak:    30us
chain_clamp      last:     0us  peak:     3us
```

**`precog_tick` was 99.9% of the spike.** `move_and_slide()` was 30 microseconds — completely innocent.

### Step 5: Analyze the algorithm

`_precog_build_graph_tick()` evaluates platform-to-platform leap connectivity. The combinatorial explosion:

```
5 pairs per frame (graph tick limit)
x ~10 launch points per pair (ball landings on source platform)
x ~5 landing samples per pair (evenly spaced across destination)
x 7 flight times per sample (different arc heights)
x ~8 intersect_shape() calls per arc (body clearance sweep)
------
= ~14,000 physics shape queries per frame
```

At ~30us per query, that's **420ms**.

### Step 6: Fix it

Three-pronged approach:

1. **Time budget** (primary fix): Replace "5 pairs per frame" with "2ms budget per frame." Always processes at least 1 pair (can't subdivide a pair), but won't start another if budget is exceeded. This spreads graph building across more frames.

2. **Reduce inner iterations**: 
   - Flight times: 7 → 5
   - Arc simulation steps: 40 → 32
   - Landing samples: 5 → 4
   - Arc clearance check step: every 2nd → every 3rd point

3. **Delta clamp** (damage control): `delta = minf(delta, 0.033)` prevents the spike frame from causing wild physics on the recovery frame.

### Step 7: Verify

Ran the same leaping suite:

| Metric | Before | After |
|--------|--------|-------|
| precog_tick peak | 340-453ms | 24-47ms |
| FPS at spike | 2 | 24-38 |
| Leaping tests | — | 5/5 PASS |
| Combat tests | — | 14/14 PASS |

The monster still finds valid leap arcs and executes them correctly. The graph just takes more frames to build (spread across ~20 frames at 1-2 pairs each instead of 4 frames at 5 pairs each).

## Key Takeaways

### 1. Profile before you guess

Initial hypothesis: "`move_and_slide()` is slow." Actual cause: precog graph building. Without section profiling, we would have optimized the wrong thing.

### 2. Sub-divide until you find the leaf

The first profiler pass showed "physics_move" was slow. That was a 40-line span containing 5 different operations. Only after splitting into sub-sections did the true culprit appear.

### 3. Physics queries are expensive — count them

A single `intersect_shape()` or `intersect_ray()` costs ~30us. That's nothing in isolation. But nested loops (platforms × launches × landings × flight times × arc points) turn 30us into 400ms. Always estimate the total query count before writing nested physics loops.

### 4. Time budgets > fixed iteration counts

"5 pairs per frame" seemed reasonable — but the cost per pair varies 100x depending on platform layout and launch point count. A time budget adapts automatically: simple pairs get more per frame, complex pairs get fewer.

### 5. Delta clamping is mandatory for physics-heavy games

Any frame spike (from any cause — GC, level load, shader compile, precog) produces a proportionally large delta on the next frame. Without clamping, this causes velocity/position overshoots that look like bugs. A simple `minf(delta, 0.033)` at the top of physics_process prevents all of them.

### 6. Can't thread physics queries in Godot

Godot's `intersect_ray()` and `intersect_shape()` are NOT thread-safe. They must run on the main thread (or physics thread in 3D, which IS the main thread in 2D). This means physics-heavy algorithms like arc clearance checking can't be trivially offloaded. The fix must be algorithmic (fewer queries, better amortization) rather than architectural (background threads).

## Future Opportunities

- **Graph caching**: Static platforms don't change between precog runs. Cache the full graph and only rebuild when the level changes.
- **Cheaper clearance**: Replace physics shape queries with a pre-built spatial grid that can be queried in O(1) instead of O(N).
- **Async pre-computation**: Build the graph during idle moments (STANDDOWN, PATROL) so it's ready when PRECOGNITION triggers.
- **LOD for arc checking**: Use coarse clearance for distant platforms, fine clearance only for the most promising candidates.
