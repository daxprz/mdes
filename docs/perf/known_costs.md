# Known Costs and Budgets

Measured performance data from DAX as of v0.10.76. Use these as baselines when evaluating optimizations or regressions.

## Frame Budget

At 60 FPS, each frame has **16.6ms** total.

| Phase | Budget | Measured Idle | Notes |
|-------|--------|---------------|-------|
| Process (`_process` + rendering) | ~10ms | **13-15ms** | OVER BUDGET — draw calls dominate |
| Physics (`_physics_process`) | ~5ms | **1-5ms** | Within budget when monster isn't in precog |
| Engine overhead | ~1ms | ~1ms | Scene tree, signals, input |

**The idle baseline (13-15ms process) leaves almost no headroom.** Any additional load pushes past 16.6ms. The primary idle cost is draw calls from `_draw()` rendering.

## Monster Physics Sections (Normal Gameplay)

Measured during CHASE/PATROL state, single monster, no chains:

| Section | Typical | Peak (normal) | Notes |
|---------|---------|---------------|-------|
| chain_logic | 3-10us | 50us | Cheap — just state checks when unchained |
| movement_blend | 15-30us | 50us | Facing, speed, landing recovery |
| ai_state | 10-20us | 6ms | Spikes during state transitions, precog phase changes |
| precog_tick | 1-2us | **45ms** | Only active during graph building; time-budgeted |
| foot_push | 10-15us | 25us | 4-leg force calculation |
| chain_clamp | 0-3us | 50us | Only active when chained |
| move_slide | 15-30us | 80us | Godot's move_and_slide — consistently cheap |
| pose_solve | 170-250us | 480us | IK, gait, foot planting — most complex section |
| rigidity | 80-140us | 250us | Spine enforcement, limb length clamping |
| hitbox_fx | 25-50us | 100us | Hitbox sync, particles, redraw |
| **TOTAL** | **350-500us** | **~50ms** | Normal frame: 0.5ms. Peak: precog-dominated. |

## Precog Graph Building

The most expensive single operation in the game.

| Metric | Before v0.10.76 | After v0.10.76 |
|--------|-----------------|----------------|
| Pairs per frame | 5 (fixed) | 1-2 (time-budgeted, 2ms budget) |
| Peak frame cost | 340-453ms | 24-47ms |
| Flight times tested | 7 | 5 |
| Arc simulation steps | 40 | 32 |
| Landing samples | 5 | 4 |
| Arc clearance step | every 2nd point | every 3rd point |
| Graph build duration | ~4 frames | ~15-20 frames |
| FPS during build | 2 FPS (freeze) | 24-38 FPS (playable) |

**Cost per pair** depends on platform layout:
- Simple (2 platforms, few launches): ~5-15ms
- Complex (5 platforms, many launches): ~30-50ms

## Physics Query Costs

Individual query costs measured on M1 Ultra:

| Query Type | Cost | Notes |
|------------|------|-------|
| `intersect_ray()` | ~15-25us | Simple ray, single collision layer |
| `intersect_shape()` (circle) | ~25-40us | CircleShape2D, collision mask 1 |
| `move_and_slide()` | ~15-30us | Single CharacterBody2D, typical collision |

**The per-query cost is low. The danger is iteration count.** 100 queries = 3ms. 1000 queries = 30ms. 10000 queries = 300ms.

## Rendering Costs

| Metric | Idle (title screen) | Active (combat) | Alert Threshold |
|--------|--------------------|--------------------|-----------------|
| Draw Calls | 400-460 | 550-700 | >500 |
| Render Objects | 16000-17000 | 18000-22000 | >20000 |
| Primitives | 30000-34000 | 35000-40000 | — |
| Process Time | 13-15ms | 14-16ms | >14ms |

Draw calls are the primary rendering cost. Each `_draw()` node adds calls. Chains add 10-15 each, debug overlays add 50-100.

## Memory

| Metric | Typical | Notes |
|--------|---------|-------|
| Static Memory | 85-90MB (compatibility), 275-280MB (forward+) | Forward+ uses more VRAM |
| Peak Memory | +15-20MB above static | Transient allocations |
| Objects | ~10200-10500 | Includes internal engine objects |
| Nodes | 220-340 | Depends on enemies + chains |
| Orphan Nodes | 0 | Should always be 0 — nonzero = leak |

## Entity Costs (Per Entity)

Rough per-entity impact on frame time:

| Entity | Physics Cost | Render Cost | Notes |
|--------|-------------|-------------|-------|
| Quadruped Monster | 0.3-0.5ms normal, up to 50ms during precog | ~20 draw calls | By far the most expensive entity |
| Chain (FABRIK) | 0.05-0.1ms | ~10-15 draw calls | Per chain instance |
| Tether | 0.02-0.05ms | ~5-8 draw calls | Simpler than chain |
| Bat | <0.01ms | ~3 draw calls | Simple AI, small sprite |
| Player | 0.1-0.2ms | ~10 draw calls | Movement, input, abilities |
| Projectile | <0.01ms | ~2 draw calls | Velocity + collision only |
| Attack Dummy | <0.01ms | ~5 draw calls | Static target |

## Test Suite Performance

Suite execution times (wall clock) on M1 Ultra:

| Suite | Tests | Duration | Spikes |
|-------|-------|----------|--------|
| Leaping | 5 | ~60s | 0-4 (24-38 FPS, playable) |
| Combat | 14 | ~120s | 10-14 (24-38 FPS, mostly level transitions) |
| Chained | 8 | ~90s | varies |

Most "spikes" during test suites are level load/clear transitions, not monster physics.
