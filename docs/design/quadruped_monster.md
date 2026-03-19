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

## Integration

- `add_to_group("enemies")` — standard enemy group
- Standard interface: `take_damage()`, `apply_knockback()`, `died` signal
- Rift tentacle absorption via meta (per-part, multiple tentacles possible)
- `mass = 200.0` (very heavy — knockback barely moves it)
- Debug spawn: press M in debug mode on title screen
- Self-contained: no changes to any existing file (except title_screen.gd for M key)
