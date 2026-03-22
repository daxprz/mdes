# EPIC: Arc Planning & Precog Pathfinding Fixes

## Overview

The quadruped monster's platform-to-platform leap system has multiple interacting bugs that prevent reliable multi-hop pathfinding. A previous session applied 401 lines of fixes all at once, resulting in an unstable state where fixes interact poorly and tests fail. This EPIC tracks the incremental re-application of those fixes, tested one at a time.

## Current State (2026-03-22)

- `quadruped_monster.gd` has 401 unstable lines of changes (uncommitted)
- The debug overlay migration (Story 5) is also in these changes — all debug rendering now routes through `DebugOverlay.should_draw()` / `DebugOverlay.log()`
- Test `leap_floor_to_P1` FAILS: monster deals damage on the floor but never reaches P1 (ETZ zone not entered)
- Root diagnostic: `PRECOG PATHFIND: monster=P-1` — monster can't locate itself on a platform, so precog aborts

## Key Discovery: Platforms are SOLID

The platforms do NOT have `one_way_collision`. They block movement in **both** directions:
- Forward raycasts DO detect platforms going up (no need for one-way probes)
- The monster CANNOT pass through platforms from below
- Arcs must go OVER platforms, approaching from ABOVE (descending)

## Fixes — Ordered by Independence (apply & test one at a time)

### Fix A: Arrival Velocity Check
**Risk: Low | Impact: High | Lines: ~3**

The cleanest single check. Prevents arcs that arrive while still ascending (would pass through the platform from below).

```
arrival_vy = launch_vy + gravity * t_flight
```
Must be > 0 (descending at arrival). Reject arcs where arrival_vy <= 0.

Location: `_plan_leap_to_surface()`, after arc simulation.

### Fix B: peak_i Default
**Risk: Low | Impact: High | Lines: 1**

`peak_i` (the index of the arc's peak point) defaults to `0` for long arcs where the peak is beyond the 16-step simulation. This causes the ascending-arc-vs-platform check to use index 0 (the launch point) instead of the actual peak, allowing through-floor arcs.

Fix: default `peak_i` to `arc_c.size() - 1` (the last simulated point).

### Fix C: floor_snap_length = 0 During Leap
**Risk: Low | Impact: Medium | Lines: ~4**

Godot's `floor_snap_length` pulls the CharacterBody2D back to the floor during `move_and_slide()`. During a leap, this prevents the monster from leaving the ground.

Fix: Set `floor_snap_length = 0` when entering `ATTACK_LEAP_AIRBORNE`. Reset to `1.0` in `_end_leap()`.

### Fix D: Chained-Suspended Skip During Leap
**Risk: Medium | Impact: Medium | Lines: ~2**

The chained-suspended physics code (extra gravity + chain position clamping + double `move_and_slide()`) runs during leap states, fighting the planned trajectory.

Fix: Add `and _state != State.ATTACK_LEAP_AIRBORNE and _state != State.ATTACK_LEAP_WINDUP` to the chained-suspended elif.

### Fix E: Precog Facing
**Risk: Medium | Impact: Medium | Lines: ~5**

At precog waypoint arrival, the monster should face the direction of the planned launch velocity, not toward the target. The windup phase also checks target direction and may override the launch facing.

Fix:
- Force `_facing = signf(launch_vel.x)` at precog arrival
- Set `_precog_leap` meta flag on the entity
- In windup, skip the target-direction facing check when `_precog_leap` is set

### Fix F: Precog Waypoint Protection
**Risk: Low | Impact: Medium | Lines: ~4**

During the walk-to-waypoint phase, `_choose_attack()` and precog re-triggering can interrupt the planned path.

Fix:
- Check `_precog_has_waypoint` at the top of `_choose_attack()` — early return
- Check `_precog_has_waypoint` before triggering new precog

### Fix G: Launch-Under-Platform Filter
**Risk: High | Impact: Medium | Lines: ~8**

Reject launch points that are directly below the destination platform — the monster can't leap upward through a solid platform.

Filter: reject if launch X is within `[plat_min_x - margin, plat_max_x + margin]` AND launch Y > plat Y (below it).

Dynamic margin: `height_diff * 0.15` clamped to `[20, 120]`.

**Caution:** This filter is sensitive to margin tuning. Too aggressive = breaks valid arcs. Too loose = allows through-platform arcs.

## DO NOT Apply

- **Swept circle check** — tested, too aggressive. Broke ALL pathfinding. Needs a more targeted approach.
- **LEAP_STRIKE_REACH changes** — breaks existing combat tests.

## New Issue Found This Session

### Entity-Platform Matching (`monster=P-1`)

The test-spawned monster sometimes can't locate itself on a platform. `_precog_add_entity_platform()` uses `_raycast_floor()` to find the floor beneath the monster and matches against known platforms by Y proximity. This fails when:
- The monster is spawned by RCON (different initialization order than scene monsters)
- The raycast floor Y doesn't match any platform within the 30px tolerance
- Multiple monsters exist and labels get overwritten

This may be a race condition (monster spawned before platforms are cached) or a coordinate-space issue (raycast in local space vs world space).

**Priority:** Must fix BEFORE the arc fixes matter — if the monster can't find its platform, precog never starts.

## Test Plan

Each fix should be tested individually:

| Fix | Test | Expected |
|-----|------|----------|
| A | `run leap_floor_to_P1` | Monster attempts leaps (may not land yet) |
| B | `run leap_floor_to_P1` | Through-floor arcs eliminated |
| C | `run leap_floor_to_P1` | Monster actually leaves the ground |
| D | `run chained_upper_platform` | Chained monster leaps without gravity fighting |
| E | `run leap_P2_to_P4` | Monster faces correct direction for upward leaps |
| F | `run leap_floor_to_P4` | Multi-hop path completes without interruption |
| G | `run chained_upper_platform_etz` | No through-floor damage |

After all fixes: run full `suite leaping` and `suite chained`.

## Debug Aspects for Inspection

All pathing tests have debug profiles that log:
- `precog/platform_list` — platform detection and entity matching
- `precog/graph_edges` — graph connectivity and LEAP_PLAN_FAIL details
- `precog/current_path` — chosen path and execution
- `pathing/waypoints` — waypoint arrival and state
- `pathing/walk_run_path` — walk decisions during precog
- `pathing/platform_leap_path` — leap execution and end
- `leap_attack/attack_zone` — strike zone and damage
- `leap_attack/spots_considered` — arrival point evaluation
- `leap_attack/chosen_arc` — selected trajectory
- `leap_attack/rays_cast` — arc clearance checks and PLAN_FAIL reasons
