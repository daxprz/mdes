# Task: Arc Planning & Precog Pathfinding Fixes

**EPIC:** `docs/epics/EPIC_arc_planning_fixes.md`
**Priority:** High
**Status:** In Progress — Arc bounding width fix in progress

---

## Current Issue

The bounded leap tests reveal that the monster's arc planner produces arcs whose body width clips platform edges. The test framework correctly detects these violations.

### Root Cause
The bounding arcs (`arc_l`/`arc_r`) now use horizontal offsets (body stays upright during flight), which correctly represents the monster's width at every point. The planner's clearance check (`_check_arc_clear_ignore`) only tests physics raycasts — it doesn't ensure the body width clears platform edges mid-flight.

### Specific Violations (leaping suite)
1. `leap_floor_to_P1`: edge 778,890→463,745 — bounding arc clips P1 left edge
2. `leap_floor_to_P2`: edge 1610,890→1302,745 — bounding arc clips P2 right edge
3. `leap_P2_to_P4`: edge 1460,750→1336,520 — bounding arc clips P4 right edge
4. `leap_floor_to_P4`: violations propagate from above

### Changes Made
- `arc_l`/`arc_r` now computed as horizontal offsets at each arc point (was: perpendicular to launch velocity)
- Added `_check_arc_lateral_clearance()` — raycasts left/right at each arc point to verify body-width clearance
- Both `_plan_leap_to_surface` and the attack leap planner updated

### Next Steps
The lateral clearance check catches walls/platforms near the arc, but the planner needs to:
1. Try more launch positions to find arcs that route around obstacles
2. Reject arcs where the horizontal bounding width clips known platform edges
3. Prefer arcs with maximum clearance from platform edges (the scoring already does this for vertical clearance above destination, needs to also score horizontal clearance)

### Suite Results (latest)
- `=== 5/16 PASSED ===` (leaping suite)
- 5 fps checks pass, all damage checks fail (exit_circle too tight), all arc checks fail (violations)
