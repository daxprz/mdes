# Quadruped Monster (Procedural Animation)

## Overview

A procedurally animated quadruped enemy. No sprites — entirely vector-rendered via `_draw()`. Movement is pose-driven with 2-bone IK legs and foot-driven locomotion. The creature's feet grip the ground and push its body forward. Its head actively tracks its target. Multiple independently damageable/severable body parts, each eligible for rift tentacle attachment.

**File:** `scripts/enemies/quadruped_monster.gd` (~2000 lines, self-contained)

## Skeleton Layout

23 tracked points in local space, organized by limb chain:

```
              skull--jaw
                 |
                neck
                 |
    leg0 -- spine[0] -- spine[1] -- spine[2] -- tail[0]..tail[4]
    leg1 --                          -- leg2
                                     -- leg3
```

| Chain       | Points | Anchor Point | Notes                          |
|-------------|--------|--------------|--------------------------------|
| Spine       | 3      | Body center  | Pose-driven, idle breathing    |
| Neck        | 2      | spine[0]     | Bends to follow head aim       |
| Head        | 2      | neck tip     | Skull + jaw (jaw hinges open)  |
| Tail        | 5      | spine[2]     | Rigid (stiffness 14), loose only during whip |
| Front legs  | 3 each | spine[0]     | Upper leg, lower leg, foot     |
| Rear legs   | 3 each | spine[2]     | Upper leg, lower leg, foot     |

## Pose-Driven Physics

The skeleton is **not** verlet-based. Every segment has a rest pose relative to its parent and springs toward it each frame with configurable stiffness (`STIFFNESS = 12.0`). No gravity on skeleton segments — only the `CharacterBody2D` gets gravity for floor collision.

The tail is rigid by default (`TAIL_STIFFNESS = 14.0`), only loosening to `2.0` during whip attacks.

## Foot-Driven Locomotion

The body does **not** move itself. Instead:

1. **AI sets `_want_direction`** (-1, 0, or +1) and `_move_speed`
2. **Planted feet push**: Each planted foot exerts `FOOT_PUSH_FORCE` (120) in the desired direction. More planted feet = more traction.
3. **Body moves as a result** of foot push forces, with grip damping (`FOOT_GRIP = 0.92`) to prevent sliding
4. **Feet are fixed in world space** while planted — the body moves past them
5. **When a foot falls too far behind** (>`STEP_THRESHOLD` = 60px from its ideal position), it lifts in a **quadratic bezier arc** to a new position with 25% overshoot
6. **Paired stepping**: Only one front foot and one rear foot can step at a time. Within each pair, the foot furthest behind gets priority. This ensures maximum spread.
7. **Rear legs trail**: Front legs target ahead of the hip (`stride * 0.35`), rear legs target behind (`stride * -0.5 * 0.35`)

### World-Space Floor Raycasting

Feet find the real floor via `_raycast_floor()`, which casts 200px downward on collision layer 1 (world). This means feet land on platforms, cave walls, slopes — any physical surface.

## 2-Bone IK (Legs)

Given a hip position (pinned to spine) and foot position (driven by gait), the knee is solved analytically using the **law of cosines**:

```
cos(angle) = (L1² + d² - L2²) / (2 * L1 * d)
knee = hip + Vector2(cos(knee_angle), sin(knee_angle)) * L1
```

**Mammal anatomy**: Front elbows bend backward, rear knees bend forward. The `bend_dir` parameter controls which side of the hip-foot line the knee appears on.

IK is disabled during leap attacks (`_leap_ik_off = true`) — legs are positioned manually.

## Head Tracking

The skull actively aims at the target. The neck bends to follow:

1. Skull position is placed along the aim direction from `spine[0]` at `NECK_LEN + skull_offset` distance
2. Neck tip is positioned between `spine[0]` and skull, creating a natural bend
3. Smoothed via `HEAD_TRACK_SPEED` (6.0/s) exponential interpolation

### Head Rotation for Drawing

All head parts (skull polygon, eye, jaw, teeth) are drawn in **head-local coordinates**:
- `head_fwd` = direction from neck tip to skull (the facing direction)
- `head_up` = perpendicular to `head_fwd`, forced to always point screen-up (`if head_up.y > 0: flip`)

This means the head rotates to face the target — looking up, down, or sideways — and stays right-side-up when the creature turns around.

## Idle Breathing

Sinusoidal vertical offset on all spine points: `sin(time * 2.0) * 1.5`. Always running, creates subtle "living" motion even when stationary.

## Attacks

| Attack        | State                  | Posture   | Range  | Damage        |
|---------------|------------------------|-----------|--------|---------------|
| Bite          | ATTACK_BITE            | Quadruped | Close  | 25            |
| Tail Whip     | ATTACK_TAIL            | Quadruped | Rear   | 18 + knockback|
| Claw Swipe    | ATTACK_SWIPE           | Bipedal   | Close  | 20 + knockback|
| Lunge         | ATTACK_LUNGE           | Quadruped | Mid    | 20            |
| Vertical Leap | ATTACK_LEAP_* (5 states)| Special  | 80-500 | 90+30+thrash  |

### Vertical Leap (5-Phase Attack)

The most complex attack. Uses reverse trajectory planning to find a clear flight path.

#### Phase 1: PLAN (`ATTACK_LEAP_PLAN`)

**Reverse trajectory planning** — starts at the target, works backward to the monster:

1. **Find the strike zone**: Sample 12 arrival angles on a circle of `LEAP_STRIKE_REACH` (80px) around the target
2. **Filter to open air**: Each arrival point is tested with 4-directional raycasts (`_is_point_in_solid`). Points inside walls/platforms are rejected. Points below the target are rejected (can't attack from below).
3. **Reverse-solve launch velocities**: For each valid arrival point, try 5 flight times (0.3s to 1.0s). The required launch velocity is computed analytically:
   ```
   Vx = (arrival.x - monster.x) / t_flight
   Vy = (arrival.y - monster.y - 0.5 * gravity * t²) / t_flight
   ```
4. **Body-width clearance**: Simulate 3 parallel arcs (center, left edge, right edge at `LEAP_BODY_RADIUS` = 22px). All 3 must be clear of obstacles.
5. **Scoring**: Clear paths are scored by `arrival_distance_to_target + flight_time_penalty`. Moderate flight times (0.5s) are preferred.

**Phase 2 refinement**: If phase 1 finds no clear path, the best near-miss arrival points are refined with 5 nearby launch positions × 7 flight times centered on the candidate.

#### Phase 2: WINDUP (`ATTACK_LEAP_WINDUP`, 1.2s)

The creature coils up for launch:
- **0.0-0.3s**: Front legs lift off ground, retract toward chest. Body starts tilting toward target.
- **0.3-0.6s**: Tail lowers, last 3 segments plant on the ground one at a time (stabilization).
- **0.6-1.0s**: Rear legs compress (feet move closer to hips). Spine tilts near-vertical.
- **1.0-1.2s**: Full coil. Head locked on target.

IK is disabled from the start of windup. All legs are positioned manually.

At the end of windup, the pre-computed launch velocity from the PLAN phase is applied. The horizontal direction is adjusted for the target's current position (allows tracking a moving target), but the arc angle is committed.

#### Phase 3: AIRBORNE (`ATTACK_LEAP_AIRBORNE`)

Parabolic flight with full body alignment:
- **Body aims like a missile**: Spine rotates to align with a blend of velocity direction (60%) and target direction (40%)
- **Collision shape rotates** to match body angle
- **Rear legs fully stretched behind** (pushing-off pose)
- **Front legs tucked against chest**
- **Tail streams straight behind**
- Gravity applies normally for parabolic arc

Transitions to STRIKE when within `LEAP_STRIKE_REACH` of target. Times out after 2.5s or on floor landing.

#### Phase 4: STRIKE (`ATTACK_LEAP_STRIKE`)

Double-time slash barrage:
- **6 slashes** at 0.08s intervals (alternating front legs)
- Each slash spawns **3 diagonal slash lines** that fade (visual effect)
- `LEAP_SLASH_DAMAGE` = 15 per slash (90 total if all connect)
- Body velocity zeroed (hovering during strike)

#### Phase 5: THRASH (`ATTACK_LEAP_THRASH`)

Bite and shake:
- Jaw bites (`LEAP_BITE_DAMAGE` = 30)
- **3 thrash shakes** at 0.2s intervals with blood spatter particles
- Target knocked sideways each thrash
- Final thrash **flings the player** at 600 speed in the direction of the last swing

## Hitboxes & Severing

7 independently damageable zones, each an `Area2D` repositioned per-frame:

| Part   | Health | Severable | Effect of Severing              |
|--------|--------|-----------|---------------------------------|
| Body   | 200    | No (main) | Death at 0                      |
| Head   | 60     | Yes       | Instant death                   |
| Tail   | 50     | Yes       | Removes tail whip attack        |
| Leg ×4 | 40 ea  | Yes       | Degraded movement (75/40/15/5%) |

Part damage also deals half damage to the main health pool.

Severed limbs fall under gravity. Stumps are drawn as red circles at the attachment point.

## AI / Behavior

- **Target selection**: Picks nearest player. Relentless — always knows where target is.
- **Aggro switch**: If a different player hits the monster 3+ times (`AGGRO_SWITCH_HITS`), switches target. Hit counter resets on switch.
- **Speed tiers**: Slow (30, patrol), Medium (80, chase), Fast (160, charge) — based on distance to target.
- **Attack selection**: Tail whip if target behind, vertical leap at 80-500px (8s cooldown), lunge at 80-200px, bite or swipe at close range.
- **Centralized state transitions**: All state changes route through `_change_state()`, which logs transitions via `DebugOverlay.log("monster/state", ...)` and tracks strategy-change counts. Enable with `debug log monster/state`.
- **Enter/exit hooks**: `_change_state()` calls `_exit_state(old, new)` and `_enter_state(new, old)`. Exit hooks handle per-state cleanup (tail whip flag, grab collision restore, leap IK/snap reset, posture finalization). Enter hooks reset `_attack_timer` for all combat/transition/precog states, and set `_attack_cooldown` for attack-entry states (bite, swipe, tail, lunge, sprint slash, hop up, grab, leap plan). `_start_*` functions now only set state-specific data (targets, counters, skeleton poses). Leap sub-state transitions skip full cleanup — only applied when leaving the leap state group entirely.

### Movement Blending

Instead of instant state snaps, movement properties blend smoothly:

- **Facing blend**: `_facing` lerps toward `_facing_target` at `TURN_SPEED` (5.0/s). During turns, `_get_facing_offset()` applies cosine easing — the body stays near full width and snaps through the compressed midpoint quickly (symmetric in and out). Leap launches set facing instantly (no mid-flight turns).
- **2.5D projection**: All segment rigidity enforcement uses `_projected_len()` which computes the 2D projection of a 3D segment rotated by the facing angle. Horizontal segments (spine, tail) compress during turns while vertical segments (legs) maintain length. Uses REST-POSE direction (not current direction) to avoid feedback where collapsed segments appear vertical and resist compression.
- **3D shoulder rotation**: Clavicles and hip bones rotate around the spine in 3D via `_enforce_shoulder_3d()`. Each bone pair has a Z-depth (`SHOULDER_Z_DEPTH=8`). The near-side shoulder sweeps inward during a turn while the far-side sweeps outward, crossing at the midpoint — creating the visual of a body rotating in depth.
- **Turn commitment**: Once a turn is underway (`|_facing| < 0.9`), `_facing_target` reversals are blocked until the current turn completes. Prevents oscillation when the target is nearly overhead.
- **Head tracking**: Skull aims from body center (stable anchor, no breathing feedback) with aim blend increasing to 100% during turns to override rest-pose snap. Head tracking distances are 2.5D projected.
- **Speed blend**: `_move_speed` lerps toward `_target_move_speed` at `SPEED_BLEND_RATE` (400 px/s²). Gait (stride, step frequency) transitions smoothly as speed ramps.
- **Landing recovery**: After `FALL_THRESHOLD` (0.15s) of airborne time, landing triggers a `LANDING_RECOVERY_TIME` (0.25s) compression. Spine dips by `LANDING_COMPRESS` (8px, scaled), foot push force is reduced up to 70%, then eases back to normal. Debug aspect: `monster/blend`.

### Runtime Config Stack (`cfg()`)

All monster constants are configurable via a stack of config providers (`scripts/systems/monster_config.gd`). When `cfg(key, default)` is called, providers are checked in priority order (index 0 = highest). First non-null result wins. GDScript `const` values are the absolute fallback.

**Provider types:**
- `DictProvider` — wraps a Dictionary (JSON files, spawn overrides)
- `CallableProvider` — calls a function per lookup (dynamic state-based values)
- `TimedProvider` — wraps any provider with an expiry (buffs/debuffs, auto-pruned)

**Stack layers (typical order):**
1. Timed buffs/debuffs (highest priority, expire automatically)
2. Spawn overrides (`config={k=v}` from RCON)
3. Base defaults (`data/config/monster_defaults.json`, 60+ values)
4. GDScript `const` (absolute fallback)

**RCON commands:**
- `spawn monster X Y config={turn_speed=2.0,stiffness=6.0}` — permanent overrides
- `buff <duration> <key=value> ...` — timed overrides on all monsters

All 60+ monster constants are now routed through `cfg()` — every physics, movement, combat, leap, health, grab, sprint, hop-up, and precog value is runtime-configurable. See `exaggerated_animations` suite for test scripts using config overrides.

## Debug Inspector

When the quadruped is TAB-selected in debug mode (Ctrl+D):

- **Red crosshair** at origin (0,0)
- **Rotated purple rectangle**: collision shape (rotates during leap)
- **Yellow floor line**: raycast floor position
- **Green dots**: spine segments with coordinates
- **Cyan dots**: neck/skull/jaw
- **Orange dots**: tail segments
- **Colored leg dots** (FL/FR/RL/RR): joints, foot positions, world targets (X), ideal positions (circles), planted/stepping state
- **Red crosshair on target**: "TARGET P# dist:###"
- **Aim line**: skull to target
- **State info panel**: state, facing, speed, HP, legs, posture, velocity, floor status
- **Leap planning**: yellow strike zone circle, arrival point markers (green=open/red=blocked), all tested arcs (dim), chosen trajectory (bright green), phase summary

## Pre-cognition (Multi-Hop Platform Pathfinding)

When the monster hasn't landed a hit on any player for `PRECOG_TRIGGER_TIME` (5s), it curls up and enters a thinking phase that solves how to reach the target across arbitrary platform layouts.

### Phase 0 — Platform Detection

1. **Ball drop**: Virtual balls are dropped in a 2D grid (`PRECOG_GRID_SPACING` = 50px) covering the entire screen. Each ball falls straight down via raycast until it hits a surface.
2. **Y-snap**: All landing Y values are snapped to a 15px grid so flat surfaces become one Y level.
3. **Deduplication**: Identical snapped positions are merged.
4. **Surface grouping**: Within each Y level, adjacent X values (gap ≤ 1.5× grid spacing) are grouped into a single platform.
5. **Entity tagging**: The monster's and target's current platforms are identified by raycasting the floor beneath them and matching to the nearest platform (±30px Y, ±40px X tolerance).

Result: typically 5-8 platforms on the title screen (floor, 2 lower platforms, 2 upper platforms, cave ledges).

### Phase 1 — Graph Building (one pair per frame)

For every pair of platforms (i, j), the system tries to find a leap trajectory:

1. **Launch points**: All ball landing positions on platform i are used as candidates (already computed).
2. **Lateral clearance**: Launch points too close to walls (< `LEAP_BODY_RADIUS * 1.2` = 26px) are rejected.
3. **Trajectory planning**: For each launch point, `_plan_leap_to_surface` targets the destination platform's surface directly (y = plat_y - 5, sampled across the platform width with body-radius inset from edges).
4. **Reverse kinematics**: For each (launch, arrival) pair and each of 7 flight times (0.2s-1.5s), the required launch velocity is computed analytically: `Vx = dx/t`, `Vy = (dy - ½gt²)/t`.
5. **Arc clearance**: 3 parallel arcs (center, left, right at body radius) are simulated and raycasted. Hits within the destination platform rect are ignored (`_check_arc_clear_ignore`).
6. **Best edge**: The launch point with the best score (closest arrival to platform center + flight time preference) becomes the graph edge.

### Phase 2 — Dijkstra Pathfinding

Standard Dijkstra from the monster's platform to the target's platform on the edge graph. Edge cost = distance between platform centers. Produces an ordered sequence of hops.

### Phase 3 — Execution

1. The first hop's launch position becomes the **waypoint**. The monster walks there using foot-driven locomotion.
2. On arrival (within 10px horizontally), the pre-computed launch velocity is applied — the monster enters `ATTACK_LEAP_WINDUP`.
3. After landing (`_end_leap`), the skeleton resets to standing pose (spine horizontal, feet raycast to floor).
4. If more hops remain in the path, the next waypoint is set automatically.
5. If no more hops, normal chase resumes.

### Debug Visualization

When TAB-selected in debug mode:
- **Purple dots**: raw ball landings
- **Colored horizontal bars**: detected platforms (green = monster, red = target, purple = other) with P# labels
- **Blue arcs**: all viable edges in the connectivity graph
- **Yellow lines + circles**: the chosen Dijkstra path
- **Green arcs**: leap trajectories along the chosen path
- **Orange circle + "WAYPOINT"**: current walk destination
- **Status line**: `PRECOG: GRAPH plats:5 edges:20 path:2 hop:1/1`

## Procedural Scaling

The monster's size is controlled by a single `creature_scale` float (default `1.0`). All spatial dimensions are derived via the `sc(base)` helper which returns `base * creature_scale`.

### What Scales
- **Skeleton geometry**: all bone lengths, rest poses, body height
- **Collision**: body sphere, hitbox radii, attach point radii
- **Locomotion**: step threshold/height, foot push force, stride, floor raycast distance
- **Speed**: auto-scales with size (`base * creature_scale`) unless `speed_override >= 0`
- **Combat ranges**: bite, tail, grab, sprint slash, lunge — all via `sc()`
- **Leap planning**: body clearance radius, strike reach, launch speed cap, bounding arcs
- **Drawing**: every line thickness, circle radius, polygon vertex, joint size
- **Chains/tethers**: link width, shackle size, peg/ring, rope thickness, hook circles

### Pathing Radius Override
`pathing_radius` (default -1 = auto) overrides the body clearance radius for leap planning. Allows a visually large monster to path through gaps sized for a smaller one.

### Entity ID
Every monster is guaranteed a unique `entity_id`. Auto-assigned as `monster_N` in `_ready()` via static counter if not pre-set by the spawner.

### RCON
```
spawn monster 960 885 standdown scale=2.0 pathing_radius=55
splay spawn t-pose 960 500 0 asleep scale=2.0
```

## RCON Server

TCP server on port 9999 for external tool control. Enables automated testing without a controller.

### Commands

| Command | Description |
|---------|-------------|
| `help` | List all commands |
| `debug` | Toggle debug mode |
| `spawn monster [x y] [state] [scale=N] [pathing_radius=N] [config={k=v,...}]` | Spawn quadruped at position with optional config overrides |
| `spawn dummy [x y]` | Spawn controllerless dummy player |
| `tp <x> <y>` | Teleport first player to position |
| `tab [n]` | Cycle debug selection n times |
| `key <name>` | Simulate key press (e.g. `key ctrl+d`) |
| `clear` | Remove all enemies, disable respawning |
| `precog` | Force precognition on all quadrupeds |
| `enemies` | List all enemies with positions |
| `players` | List all players with positions |
| `status` | Show debug state, counts, selection |
| `quit` | Exit game |

### Dummy Player

A `CharacterBody2D` in the `players` group with gravity, collision, and green circle rendering. Has `player_index = 0`. Teleportable via RCON `tp` command. No controller required — the monster targets it like a real player.

## Integration

- `add_to_group("enemies")` — standard enemy group
- Standard interface: `take_damage()`, `apply_knockback()`, `died` signal
- Rift tentacle absorption via meta (per-part, multiple tentacles possible)
- `mass = 200.0` (very heavy — knockback barely moves it)
- Debug spawn: press M in debug mode on title screen, or via RCON `spawn monster`
- RCON server: autoload, port 9999, `scripts/autoload/rcon.gd`
- Automated test: `scripts/test_precog.sh` — spawns dummy + monster, teleports to 6 positions, verifies path + leap execution
- Self-contained: no changes to existing gameplay files
