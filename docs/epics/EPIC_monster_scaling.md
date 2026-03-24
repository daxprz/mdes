# EPIC: Procedural Monster Scaling

## Overview

Make the quadruped monster's size a single runtime-configurable float (`creature_scale`). A scale of `1.0` is the current default. A scale of `4.0` produces a monster 4x larger in every linear dimension. Speed scales automatically with size (larger = faster) but can be independently overridden.

Every size-dependent system — skeleton geometry, collision shapes, hitboxes, attach points, drawing, IK, foot locomotion, floor raycasting, leap planning, precog pathfinding, and obstacle avoidance — must derive its dimensions from `creature_scale` rather than hardcoded constants.

## Design Principles

1. **Single source of truth**: `creature_scale: float = 1.0` on the monster. Everything else derives from it.
2. **No behavioral changes at scale 1.0**: The default monster must be identical before and after this work.
3. **Speed scales with size by default**: `effective_speed = base_speed * creature_scale` unless `speed_override` is set.
4. **All physics queries scale**: Raycast distances, shape radii, clearance margins, grid spacing.
5. **Drawing scales automatically**: All hardcoded pixel values in `_draw_*()` multiply by `creature_scale`.
6. **Tests validate scaling**: At least one test at a non-default scale proves the system works.

## Constant Audit

Every `const` that represents a spatial dimension must become a computed value. The pattern is:
- Keep the `const` as the **base** value (documents the design intent)
- Add a scaled getter or compute `base * creature_scale` at point of use

### Skeleton Geometry (Story 1)
| Constant | Base Value | Scales? | Notes |
|----------|-----------|---------|-------|
| `SPINE_SEG_LEN` | 28.0 | Yes | Spine segment length |
| `NECK_LEN` | 22.0 | Yes | Neck length |
| `LEG_UPPER_LEN` | 24.0 | Yes | Upper leg bone |
| `LEG_LOWER_LEN` | 22.0 | Yes | Lower leg bone |
| `LEG_FOOT_LEN` | 10.0 | Yes | Foot/claw length |
| `TAIL_SEG_LEN` | 16.0 | Yes | Per tail segment |
| `JAW_LEN` | 14.0 | Yes | Jaw bone |
| `CLAVICLE_LEN` | 12.0 | Yes | Shoulder bone |
| `HIP_BONE_LEN` | 12.0 | Yes | Hip bone |

### Collision & Hitboxes (Story 2)
| Constant/Value | Base Value | Scales? | Notes |
|----------------|-----------|---------|-------|
| Body collision radius | 14.0 | Yes | `CircleShape2D` in `_init_collision()` |
| Body collision offset | (0, -10) | Yes | Y offset from spine[1] |
| Hitbox radii | 12/8/4 | Yes | body=12, limbs=8, eye=4 |
| Attach point radii | 16/30/14/12/8 | Yes | Per point in `_init_attach_points()` |

### Foot Locomotion (Story 3)
| Constant | Base Value | Scales? | Notes |
|----------|-----------|---------|-------|
| `STEP_THRESHOLD` | 25.0 | Yes | When foot is "behind" enough to step |
| `STEP_HEIGHT` | 28.0 | Yes | Foot lift during step |
| `FOOT_PUSH_FORCE` | 200.0 | Yes | Scales with mass (mass ~ scale^2) |
| `SPEED_SLOW` | 60.0 | Auto | Scales with creature_scale unless overridden |
| `SPEED_MEDIUM` | 140.0 | Auto | Same |
| `SPEED_FAST` | 240.0 | Auto | Same |

### Combat Ranges (Story 3)
| Constant | Base Value | Scales? | Notes |
|----------|-----------|---------|-------|
| `BITE_RANGE` | 90.0 | Yes | Skull reach |
| `TAIL_RANGE` | 90.0 | Yes | Tail whip reach |
| `GRAB_RANGE` | 40.0 | Yes | Close grapple |
| `SPRINT_SLASH_RANGE` | 70.0 | Yes | Sprint attack initiation |
| `LUNGE_SPEED` | 300.0 | Yes | Burst speed |
| `SPRINT_SPEED` | 250.0 | Yes | Sprint burst |

### Leap Planning (Story 4)
| Constant | Base Value | Scales? | Notes |
|----------|-----------|---------|-------|
| `LEAP_BODY_RADIUS` | 55.0 | Yes | **Critical** — drives all clearance checks |
| `LEAP_STRIKE_REACH` | 80.0 | Yes | Arrival zone around target |
| `LEAP_RANGE` | 500.0 | Yes | Max consideration distance |
| `LEAP_LAUNCH_SPEED` | 1000.0 | Yes | Velocity magnitude cap |
| `HOP_UP_MAX_HEIGHT` | 140.0 | Yes | Connected hop threshold |

### Precog Pathfinding (Story 4)
| Constant | Base Value | Scales? | Notes |
|----------|-----------|---------|-------|
| `PRECOG_GRID_SPACING` | 50.0 | Partial | Larger monster needs coarser or finer grid? Keep same — it's world-space |
| `PRECOG_CLUSTER_RADIUS` | 40.0 | No | World-space clustering |
| Landing zone insets | `effective_radius + 5` | Yes | Via LEAP_BODY_RADIUS scaling |
| Edge margin | `radius * 0.8` | Yes | Already ratio-based |
| Fade start height | `radius * 3.0` | Yes | Already ratio-based |

### Floor Raycasting (Story 3)
| Value | Base | Scales? | Notes |
|-------|------|---------|-------|
| Raycast distance | 200px down | Yes | Longer legs need longer reach |
| Fallback leg dangle | `upper + lower` | Yes | Via leg length scaling |
| Skeleton constraint margins | 8, 3, 10px | Yes | Push-out margins in `_constrain_skeleton_to_world()` |

### Drawing (Story 5)
All hardcoded pixel values in `_draw_body()`, `_draw_tail()`, `_draw_legs()`, `_draw_neck_head()`:
- Spine thickness: 10→8 lerp
- Spine circle radii: 12→10 lerp
- Tail thickness: 6→2 lerp
- Tail tip radius: 2.5
- Leg bone thickness: 5.0, 4.0
- Joint radii: 4.0, 3.5, 3.0
- Claw geometry: 6.0 length, 3.0 spread
- Neck thickness: 8.0, 7.0
- Neck joint radii: 5.0, 4.5
- Skull polygon coords: all 5 vertices
- Eye position and radii: 4.0, 2.0
- Jaw polygon coords: all 4 vertices
- Teeth spacing and length
- Selection indicator radius: 30.0
- Debug drawing sizes

## Status (v0.10.1)

Stories 1-7 COMPLETE. Additional work delivered beyond the original plan:
- `pathing_radius` override for decoupling clearance from visual size
- Splay manager scales creatures, skeleton snapshots, connection offsets, and chain distances
- Chain and tether rendering scales with creature size (link width, shackles, pegs, hooks)
- Debug drawer has live scale slider (Ctrl+D, TAB-select, drag)
- Level editor splay widget has draggable rotation handle (cyan circle) and scale handle (green diamond)
- `splay spawn` RCON and level config support `scale=N`
- All monsters auto-assign `entity_id` via static counter in `_ready()`
- Save dialog click detection fixed (world-space conversion)

## Stories

### Story 1: Scale Property & Skeleton Init DONE
**Add `creature_scale` property. Scale all skeleton geometry in `_init_skeleton()`.**

Tasks:
- Add `var creature_scale: float = 1.0` and `var speed_override: float = -1.0` to monster
- Add helper: `func s(base: float) -> float: return base * creature_scale` (scaled value shorthand)
- Modify `_init_skeleton()` to use `s()` for all segment lengths
- Skeleton rest poses, body_y computation, clavicle/hip offsets — all via `s()`
- Skull/jaw rest offsets scale
- `_init_collision()`: shape radius and offset scale
- Verify: spawn at scale 1.0, behavior identical

### Story 2: Hitboxes, Attach Points & Collision DONE
**Scale all collision shapes and interaction radii.**

Tasks:
- `_init_hitboxes()`: circle radii scale — `s(12)`, `s(8)`, `s(4)` for eye
- `_init_attach_points()`: all point radii scale
- `_constrain_skeleton_to_world()`: push-out margins scale (8→`s(8)`, 3→`s(3)`, 10→`s(10)`)
- Raycast offsets in constraint function scale (-5/+15 becomes `-s(5)`/`+s(15)`)

### Story 3: Locomotion, Speed & Combat DONE
**Scale foot-driven movement, floor raycasting, speed tiers, and combat ranges.**

Tasks:
- `_raycast_floor()`: cast distance `s(200)` instead of 200
- Fallback return: `s(LEG_UPPER_LEN) + s(LEG_LOWER_LEN)` (already correct if lengths scale)
- `STEP_THRESHOLD`, `STEP_HEIGHT`: use `s()` at point of use
- `FOOT_PUSH_FORCE`: scale by `creature_scale` (bigger feet push harder)
- Speed tiers: `effective_speed = base * creature_scale` unless `speed_override >= 0`
- `BITE_RANGE`, `TAIL_RANGE`, `GRAB_RANGE`, `SPRINT_SLASH_RANGE`: `s()` at point of use
- `LUNGE_SPEED`, `SPRINT_SPEED`: scale
- IK: `_solve_leg_ik()` takes lengths as parameters — already correct if callers pass scaled values
- Stride computation (if hardcoded) must scale

### Story 4: Leap Planning & Precog DONE
**Scale all leap trajectory, body clearance, and precog pathfinding dimensions.**

Tasks:
- `LEAP_BODY_RADIUS`: `s()` at point of use (affects `_plan_leap_to_surface`, `_check_arc_body_clearance`, bounding arcs)
- `LEAP_STRIKE_REACH`, `LEAP_RANGE`, `LEAP_LAUNCH_SPEED`: `s()`
- `HOP_UP_MAX_HEIGHT`: `s()`
- `_check_arc_body_clearance()`: receives radius as parameter — caller passes `s(LEAP_BODY_RADIUS)`. Internal ratios (`radius * 3.0`, `radius * 0.8`) already scale correctly.
- Landing zone insets: already use `effective_radius` which will be scaled
- `_plan_leap_to_surface()`: `effective_radius` computed from `s(LEAP_BODY_RADIUS)`
- Precog ball grid: keep `PRECOG_GRID_SPACING` world-space (level doesn't change)
- Precog platform edge refinement: lateral clearance check uses body radius — will auto-scale
- Precog entity platform matching tolerances: ±30px Y, ±40px X — scale these

### Story 5: Drawing DONE
**Scale all hardcoded pixel values in _draw_*() functions.**

Tasks:
- `_draw_body()`: spine thickness `s(10)→s(8)` lerp, circle radii `s(12)→s(10)` lerp
- `_draw_tail()`: thickness `s(6)→s(2)`, tip radius `s(2.5)`
- `_draw_legs()`: bone thickness `s(5)`, `s(4)`, joint radii `s(4)`, `s(3.5)`, `s(3)`, claw length `s(6)`, spread `s(3)`
- `_draw_neck_head()`: neck thickness `s(8)`, `s(7)`, joint radii `s(5)`, `s(4.5)`
- Skull polygon: all 5 vertex coordinates × `creature_scale`
- Eye: position `s(16,5)`, radii `s(4)`, `s(2)`
- Jaw polygon: all 4 vertices × `creature_scale`
- Teeth: spacing and length scale
- `_draw_debug()`: selection ring `s(30)`, floor line extent `s(120)`, belly arc `s(14)`

### Story 6: RCON Integration & Test DONE
**Add RCON `spawn monster` scale parameter. Create test for scaled monster.**

Tasks:
- Extend `spawn monster X Y [state] [scale=N]` syntax in RCON
- Parse `scale=4.0` from spawn args, set `monster.creature_scale` before `_ready()` or re-init skeleton after
- Since `_init_skeleton()` runs in `_ready()`, set `creature_scale` before `add_child()` or call `reinit_skeleton()` after
- Add `reinit_skeleton()` that re-runs `_init_skeleton()`, `_init_collision()`, `_init_hitboxes()`, `_init_attach_points()` with current scale
- Add `debug log` aspect: `scaling/active_scale` — logs current scale factor
- Create test: `giant_floor_to_P3.json` — 4x monster from floor center to P3 (upper platform)
- Add to `all.json` suite

### Story 7: Debug Aspects DONE
**Add debug aspects for scale diagnostics.**

Tasks:
- Register `scaling/active_scale` — shows current scale factor on overlay
- Register `scaling/effective_radii` — draws body radius circle, leap radius, hitbox extents
- Register `scaling/speed_info` — logs effective speeds vs base speeds
- Render scaled body circle in `_draw_debug()` when aspect enabled

## RCON Command Changes

```
spawn monster 960 885 standdown scale=4.0
```

Parse key=value pairs after the positional args. `scale=N` sets `creature_scale`.

## Risk Analysis

| Risk | Mitigation |
|------|------------|
| Scale 1.0 regression | Run full `suite all owait=0` before and after |
| Giant monster can't fit through gaps | Expected — larger monster needs wider clearances. Arc planner handles this via body radius |
| Performance at large scale | More raycast distance, same step count. Monitor FPS |
| Skeleton instability at extreme scales | Test at 0.5, 1.0, 2.0, 4.0. Stiffness may need scale adjustment |
| Hitbox scaling breaks damage | Verify damage tests still pass at scale 1.0 |
