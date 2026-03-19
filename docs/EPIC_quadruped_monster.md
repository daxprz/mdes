# EPIC: Quadruped Monster — Procedurally Animated Predator

## Overview

A physics-based procedurally animated quadruped monster that hunts players across multi-platform levels. No sprites — entirely vector-rendered via `_draw()`. Features foot-driven locomotion, 2-bone IK, head tracking, multiple attack types, pre-cognition pathfinding across platforms, and an automated testing infrastructure.

## Timeline

| Version | Milestone |
|---------|-----------|
| v0.9.5  | Archer reticle fix, migration patterns, rift tentacle physics |
| v0.9.6  | Migration: per-species, stagger, bat repulsion, editor polish |
| v0.9.7  | Rift tentacle: verlet drag, bidirectional force propagation |
| v0.9.8  | Quadruped skeleton, cave walls, debug inspector, keystone platform |
| v0.9.9  | Vertical leap with reverse trajectory planning, head pivot |
| v0.9.10 | Pre-cognition graph pathfinding, RCON server, dummy player |
| v0.9.11 | Speed overhaul, sprint slash, connected hop-up |
| v0.9.12 | 9/10 baseline, IK fixes, FPS stability |
| v0.9.13 | Realistic body radius (55px), IK scoring, 1395 damage baseline |

## Completed Work

### 1. Skeleton & Rendering (v0.9.8)
- [x] 23-point skeleton: 3 spine, 2 neck, skull+jaw, 5 tail, 4×3 legs
- [x] Pose-driven physics (not verlet) — segments spring to rest positions
- [x] All rendering via `_draw()` — body, legs, tail, neck, skull polygon, jaw, teeth, eye
- [x] Head rotates in head-local space (skull, jaw, eye, teeth all pivot)
- [x] Head stays upright on direction flip (`head_up.y > 0` correction)
- [x] Idle breathing (sinusoidal spine oscillation)
- [x] Debug entity inspector (TAB cycles enemies, shows skeleton, state, targets)

### 2. Foot-Driven Locomotion (v0.9.8-v0.9.12)
- [x] Feet grip ground in WORLD SPACE, push body forward via force
- [x] Body moves as RESULT of foot forces (not direct velocity)
- [x] World-space floor raycasting (`_raycast_floor`)
- [x] Quadratic bezier foot arcs during steps
- [x] Paired stepping: one front + one rear at a time
- [x] Diagonal gait removed in favor of independent feet with pair locking
- [x] Rear legs trail behind (stride × -0.3)
- [x] Step overshoot 10%, step threshold 25px
- [x] Re-raycast floor on foot landing (prevents floating)
- [x] Foot clamping: max reach 1.5x, max depth 1.3x, max spread 2x

### 3. 2-Bone IK (v0.9.8-v0.9.13)
- [x] Law of cosines knee solver
- [x] Mammal anatomy: front elbows backward, rear knees forward
- [x] Knee snaps at 2x stiffness (prevents oscillation)
- [x] IK disabled during leap (legs positioned manually)
- [x] IK quality scoring: spread + hover + stretch penalties

### 4. Head Tracking (v0.9.8-v0.9.9)
- [x] Skull aims at target position
- [x] Neck bends to follow (positioned between spine[0] and skull)
- [x] Smoothed via HEAD_TRACK_SPEED exponential interpolation
- [x] All head parts drawn in rotated head-local coordinate system

### 5. Basic Attacks (v0.9.8)
- [x] Bite: jaw opens, head lunges, jaw snaps, damage check at skull
- [x] Tail whip: curl + swing, stiffness loosens during whip
- [x] Claw swipe: bipedal transition, front leg arc
- [x] Lunge: velocity burst with claw hitbox
- [x] Bite range 90px, bite hit radius 50px

### 6. Sprint Slash (v0.9.11)
- [x] Same-plane charge at 250 speed
- [x] 3 rapid alternating claw swipes at 0.1s intervals
- [x] 18 damage per slash (54 total)
- [x] Diagonal slash visual effects

### 7. Connected Hop-Up (v0.9.11)
- [x] Short platform climb (< 140px height diff)
- [x] Rear legs push, body rises, front feet grab upper surface
- [x] Feet connected to both surfaces throughout
- [x] 0.4s duration, 12 damage impact

### 8. Vertical Leap Attack (v0.9.9-v0.9.13)
- [x] 5-phase: PLAN → WINDUP → AIRBORNE → STRIKE → THRASH
- [x] Reverse trajectory planning from strike zone
- [x] Arrival points sampled around target, filtered to open air above platform
- [x] Reverse kinematics: Vx=dx/t, Vy=(dy-½gt²)/t
- [x] Body-width clearance: 3 parallel arcs at LEAP_BODY_RADIUS (55px)
- [x] Destination-aware arc clearance (ignores landing platform hits)
- [x] Underside rejection: arrivals below target's platform surface rejected
- [x] Windup 0.6s: front legs tuck, tail plants, rear compresses, body aims
- [x] Airborne: body aligns like missile, collision shape rotates
- [x] Strike: 6 double-time slashes (15 dmg each = 90 max)
- [x] Thrash: bite (30 dmg) + 3 shakes with blood spatter + fling
- [x] IK off during entire leap, skeleton reset on landing

### 9. Pre-Cognition Pathfinding (v0.9.10-v0.9.13)
- [x] Ball-drop platform detection (2D grid across entire map)
- [x] Y-snap deduplication + surface connectivity grouping
- [x] Platform graph: edges = viable leaps between platforms
- [x] `_plan_leap_to_surface`: targets platform surface directly
- [x] `_check_arc_clear_ignore`: ignores destination platform during clearance
- [x] Dijkstra shortest path from monster platform to target platform
- [x] Multi-hop execution: walk to waypoint, leap, repeat
- [x] Pre-cached graph at spawn (async, 5 pairs/frame)
- [x] Instant Dijkstra on subsequent precog triggers
- [x] Nearest-platform fallback (no disconnected nodes)
- [x] Precog cooldown (2s) prevents spam
- [x] Plan commitment (MAX_PLAN_ATTEMPTS = 3)

### 10. Hitboxes & Severing (v0.9.8)
- [x] 7 independently damageable zones (body, head, tail, 4 legs)
- [x] Per-part health tracking
- [x] Severed limbs fall under gravity
- [x] Degraded movement with missing legs (75/40/15/5%)
- [x] Head severed = instant death

### 11. AI / Behavior (v0.9.8-v0.9.13)
- [x] Relentless target tracking (always knows where target is)
- [x] Aggro switch after 3 hits from another player
- [x] Speed tiers: slow 60, medium 140, fast 240 px/s
- [x] Instant precog when target is >80px above or >120px below
- [x] No-hit timer (3s) triggers precog as fallback
- [x] Out-of-bounds recovery (teleport to spawn)
- [x] Strategy thrash scoring

### 12. Infrastructure (v0.9.10-v0.9.13)
- [x] RCON server (TCP port 9999): debug, spawn, tp, tab, key, clear, precog, fps, hp, ik, thrash, etc.
- [x] Dummy player: controllerless CharacterBody2D with HP tracking
- [x] Automated baseline test (`test_baseline.sh`): 10 scenarios, measures DMG/FPS/IK/thrash
- [x] Upper platform focused test (`test_upper_platforms.sh`)
- [x] Debug draw toggle (lite vs full vs off)
- [x] IK quality scoring system
- [x] Strategy thrash scoring system

### 13. Environment (v0.9.8)
- [x] Cave walls: curved CollisionPolygon2D floor-to-wall transitions
- [x] Flat ledge shelf at 1/3 height
- [x] Portal keystone standable platform (48px wide)

---

## Current Baseline (v0.9.13+)

```
SUMMARY: 7/10 hit, dmg=460, min_fps=14, worst_ik=1911, worst_thrash=31
```

| Metric | Current | Target |
|--------|---------|--------|
| Hit rate | 7/10 | 10/10 |
| Total damage | 460 | > 1000 |
| Min FPS (debug on) | 14 | > 30 |
| Min FPS (debug off) | 54 | > 50 ✓ |
| Worst IK peak | 1911 | < 100 |
| Worst thrash | 31 | < 5 |

---

## Remaining Work — Stories & Tasks

### STORY 1: Eliminate Strategy Thrashing (worst_thrash 31 → < 5)

The monster changes its mind 31 times without the target moving. This makes it look confused and wastes time.

**Root Cause:** The chase state oscillates between direct attacks, precog, and chase because the state transitions happen every frame based on distance/height checks that fluctuate.

**Tasks:**
- [ ] **1.1** Lock state for minimum duration — once an attack or precog plan starts, commit for at least 2 seconds
- [ ] **1.2** Add hysteresis to height-based precog trigger — trigger at 80px above, only reset at 40px above (prevent oscillation at boundary)
- [ ] **1.3** Once a waypoint is set, don't interrupt it with a different plan until the waypoint is reached or timeout
- [ ] **1.4** Track "plan enacted" vs "plan abandoned" — only re-plan after fully enacting or after 3 failed attempts

### STORY 2: Fix IK Leg Quality (worst_ik 1911 → < 100)

Legs stretch impossibly far, hover above the floor, or splay outward.

**Root Cause:** After leaps and platform transitions, foot world-positions are stale. The body moves but feet reference old positions. The pose-driven system doesn't enforce that feet must be ON a surface.

**Tasks:**
- [ ] **2.1** After every state transition, force all feet to re-plant at floor level below their hips
- [ ] **2.2** Every N frames, validate that each planted foot's world position is on a solid surface (raycast down from foot). If not, replant.
- [ ] **2.3** Reduce max horizontal foot-to-hip distance to 30px (from 40px)
- [ ] **2.4** When body Y changes rapidly (landing, falling), immediately replant all feet
- [ ] **2.5** Benchmark: target IK score avg < 20, peak < 100

### STORY 3: Improve Debug Draw Performance (min_fps 14 → > 30 with debug on)

Debug drawing causes severe frame drops.

**Root Cause:** `_draw_debug()` renders hundreds of lines (platform bars, skeleton points, text) every frame. Each `draw_string` and `draw_line` call has overhead.

**Tasks:**
- [ ] **3.1** Only redraw debug info every 3rd frame (`Engine.get_frames_drawn() % 3`)
- [ ] **3.2** Cache platform bar geometry instead of recomputing every frame
- [ ] **3.3** Reduce text labels — combine into fewer draw_string calls
- [ ] **3.4** Skip precog visualization when not in PRECOGNITION state

### STORY 4: Reach All Platforms Reliably (7/10 → 10/10 hit rate)

Three scenarios consistently fail: `cross_P1_to_P2`, `P1_to_P3`, `P2_to_P4`.

**Root Cause:** The leap trajectory either doesn't reach the upper platform or lands on the edge and slides off. The precog graph finds a path but the execution is inaccurate.

**Tasks:**
- [ ] **4.1** Add post-leap floor detection — if not on the target platform after landing, immediately try again
- [ ] **4.2** Increase flight time range (0.2-1.5s → 0.15-2.0s) for more arc options
- [ ] **4.3** When the leap edge was computed from position A but the monster launches from position B, adjust the velocity vector proportionally (not just horizontal direction)
- [ ] **4.4** Add a "landing correction" — if the monster is within 30px of a platform edge after landing, nudge it onto the platform
- [ ] **4.5** Score the ARRIVAL ACCURACY for each scenario (how close to the target platform center)

### STORY 5: Maximize Damage Output (460 → > 1000)

Even when the monster reaches the target, it doesn't always deal damage efficiently.

**Tasks:**
- [ ] **5.1** After reaching the target's platform, immediately enter chase+bite mode (no more precog)
- [ ] **5.2** Increase bite damage check frequency — currently only checks on jaw snap frame
- [ ] **5.3** Add a "pounce" mechanic — when landing from a leap within 60px of target, instant damage
- [ ] **5.4** Sprint slash should trigger more aggressively on same-level scenarios
- [ ] **5.5** Track damage-per-second as a metric in the baseline

### STORY 6: New Moves & Polish (Future)

**Tasks:**
- [ ] **6.1** Standing hop-up for short climbs (< 140px) — currently implemented but rarely triggers
- [ ] **6.2** Wall-cling: grab cave walls temporarily during multi-hop routes
- [ ] **6.3** Pounce landing impact: area damage + screen shake when landing from a leap
- [ ] **6.4** Death animation: part-by-part collapse with physics
- [ ] **6.5** Audio: growl, footstep sounds, leap whoosh, bite crunch
- [ ] **6.6** Health bar rendering

---

## Implementation Priority

1. **Story 1 (Thrash)** — Biggest visible problem. Makes the monster look broken.
2. **Story 2 (IK)** — Second most visible. Floating/stretched legs destroy immersion.
3. **Story 4 (Hit rate)** — Core gameplay. Must reach the player reliably.
4. **Story 3 (FPS)** — Only affects debug mode. Low priority for gameplay.
5. **Story 5 (Damage)** — Polish. Improves after 1+2+4 are fixed.
6. **Story 6 (New moves)** — Future scope.

---

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `scripts/enemies/quadruped_monster.gd` | ~3200 | Monster: skeleton, physics, AI, attacks, precog, rendering |
| `scripts/autoload/rcon.gd` | ~300 | RCON server for automated testing |
| `scripts/effects/cave_wall.gd` | ~140 | Cave wall rendering + collision |
| `scripts/test_baseline.sh` | ~80 | Automated 10-scenario baseline |
| `scripts/test_upper_platforms.sh` | ~60 | Focused upper-platform test |
| `docs/design/quadruped_monster.md` | ~300 | Detailed design document |

## Key Metrics (tracked automatically via RCON)

| Metric | RCON Command | Measures |
|--------|-------------|----------|
| Damage dealt | `hp` | `damage_taken` on dummy player |
| Frame rate | `fps` | `Engine.get_frames_per_second()` |
| IK quality | `ik` | Spread + hover + stretch penalty score |
| Strategy thrash | `thrash` | State changes since target last moved |
| Monster position | `enemies` | World coordinates |
| Player position | `players` | World coordinates |
