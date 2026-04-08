# Godot Performance Reference

Quick reference for Godot's built-in performance infrastructure and constraints relevant to DAX.

## Performance Singleton

`Performance.get_monitor(monitor_id)` returns a float for any of 31+ built-in monitors. Polled once per frame in the FPS overlay.

### Most Useful Monitors

| Monitor | What It Tells You |
|---------|-------------------|
| `TIME_FPS` | Frames per second |
| `TIME_PROCESS` | Time spent in `_process()` callbacks (ms) |
| `TIME_PHYSICS_PROCESS` | Time spent in `_physics_process()` callbacks (ms) |
| `TIME_NAVIGATION_PROCESS` | Navigation server time (ms) |
| `OBJECT_COUNT` | Total Objects in memory (includes resources, not just nodes) |
| `OBJECT_NODE_COUNT` | Nodes in the scene tree |
| `OBJECT_ORPHAN_NODE_COUNT` | Nodes not in any tree — potential leak indicator |
| `OBJECT_RESOURCE_COUNT` | Loaded resources |
| `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` | Draw calls sent to GPU — primary rendering cost metric |
| `RENDER_TOTAL_OBJECTS_IN_FRAME` | Objects submitted for rendering |
| `RENDER_TOTAL_PRIMITIVES_IN_FRAME` | Triangles/lines rendered |
| `MEMORY_STATIC` | Static memory allocation (MB) |
| `MEMORY_STATIC_MAX` | Peak static memory (MB) |
| `MEMORY_MESSAGE_BUFFER_MAX` | Message buffer peak (KB) |

### Delta Tracking

Comparing a metric's current value to its value 60 frames ago reveals trends:
- **Object count climbing** → possible leak (nodes or resources not freed)
- **Draw calls spiking** → something spawned many visible nodes
- **Memory climbing** → resource leak or unbounded cache

## Renderers

### Forward+ (`forward_plus`)
- Uses RenderingDevice (RD) pipeline — Metal on macOS
- Better batching, fewer crash-prone code paths
- Supports advanced effects (SSR, SSAO, volumetric fog)
- **Used by DAX since v0.10.76**

### Compatibility (`gl_compatibility`)
- OpenGL ES 3.0 / WebGL 2.0
- Wider device support, simpler pipeline
- **Known bug**: batch boundary crash in `RasterizerCanvasGLES3::_render_batch` when freeing nodes during `_draw()` (Godot #117602). Fix merged to master but not in 4.6.x stable releases.
- **Not recommended for DAX** — the `_draw()`-heavy rendering approach triggers this bug

### Defensive Practices (Both Renderers)

When freeing nodes that have visual representation:

```gdscript
# GOOD: Remove from renderer BEFORE invalidating the RID
hide()                        # Removes from canvas batch list
set_physics_process(false)    # Stop processing
set_process(false)
queue_free()                  # Safe — node is already invisible

# BAD: Free while still visible and processing
queue_free()  # Renderer may reference stale RID next frame
```

This pattern is used in `chain.gd`, `tether.gd`, and `splay_manager.gd`.

## Threading Constraints

### What CAN run on background threads
- Pure math (arc simulation, pathfinding on a pre-built graph, scoring)
- Array/Dictionary manipulation
- String processing
- File I/O (with care)

### What CANNOT run on background threads
- `get_tree()` — scene tree access
- `get_node()` / `add_child()` / `remove_child()` — scene tree mutation
- `intersect_ray()` / `intersect_shape()` — physics space queries
- `move_and_slide()` — physics body movement
- `queue_redraw()` — rendering requests
- Any signal emission that connects to scene tree operations

### Implications for DAX

The precog graph builder does heavy physics queries (`intersect_shape` for arc clearance). These **cannot** be threaded. The fix must be algorithmic:
- Time-budget amortization (spread across frames)
- Fewer queries (reduced iteration counts)
- Spatial caching (pre-built grid instead of live queries)

If the graph were built on a pre-computed collision grid (no live physics queries), THEN the pathfinding and scoring could run on a `WorkerThreadPool` task.

## Godot Thread API

```gdscript
# Simple thread
var thread := Thread.new()
thread.start(my_function)
# ... later ...
thread.wait_to_finish()

# Worker pool (better for short tasks)
var task_id := WorkerThreadPool.add_task(my_function)
# ... later ...
WorkerThreadPool.wait_for_task_completion(task_id)

# Group tasks (parallel map)
var group_id := WorkerThreadPool.add_group_task(my_func, element_count)
WorkerThreadPool.wait_for_group_task_completion(group_id)
```

Thread-safe communication back to main thread:
```gdscript
# From thread: queue a callable on the main thread
call_deferred("_on_thread_result", result)
# Or use a Mutex + shared variable
```

## Draw Call Budget

DAX renders everything via `_draw()` — no sprites. Each node with `_draw()` generates draw calls. Current baseline:

| Source | Approx Draw Calls |
|--------|-------------------|
| Monster body + legs + skeleton | ~15-20 |
| Each chain (FABRIK links) | ~10-15 per chain |
| Each tether (rope segments) | ~5-8 per tether |
| Platform geometry | ~20-30 |
| Debug overlay (when enabled) | ~50-100 |
| HUD elements | ~10-20 |
| Bats, fireflies, particles | ~5-10 each |

Total at idle: **400-600 draw calls**. This consumes ~13-15ms of Process time even with nothing happening — 85% of the 16.6ms budget at 60fps. Reducing draw calls (batching, culling off-screen nodes) is the primary path to lower idle overhead.

## Useful Commands

```
# In-game console or RCON
perf                    # Current status
perf snapshot           # Full dump
perf reset              # Clear peaks
debug on perf/fps       # Show overlay
debug log perf/snapshot_log  # Enable auto-spike logging

# Godot editor
Monitor tab in Debugger panel shows Performance monitors graphically
```
