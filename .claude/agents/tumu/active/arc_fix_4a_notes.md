# 4A Notes: Why r=55 body arcs aren't rejected by the planner

## Visual Confirmation
- The test editor now shows body circles (r=55) at each breach point
- Two circles visually clip the corner of P1 (lower-left platform)
- The arc from (1028,890) to (540,745) approaches P1 from the right
- The body center passes at x≈770, the body edge at x≈715 clips P1's right edge (x=749)

## Why the planner misses it

### Current checks in `_plan_leap_to_surface`:
1. **Forward raycasts on arc_c/arc_l/arc_r** (`_check_arc_clear_ignore`)
   - arc_l/arc_r are horizontal offsets (x ± 55)
   - The raycasts go point-to-point along each arc
   - They miss the CORNER because the body clips the corner diagonally, not along the arc path

2. **Lateral raycasts** (`_check_arc_circle_sweep`)
   - Raycasts left and right from arc_c points
   - Only detect walls to the SIDE, not platforms above/below
   - P1's surface is above the arc point — the lateral ray goes horizontal and misses it

3. **Platform edge clearance rect** (`_check_arc_platform_edge_clearance`)
   - Surface rect: `Rect2(px_min, py-30, width, 180)`
   - Checks if arc_l/arc_r points fall INSIDE the rect
   - The body center at x=770 is OUTSIDE P1's x range (330-749)
   - But the body EDGE at x=715 IS inside — the check doesn't expand the rect by body_radius

## The correct fix

**Expand the platform edge clearance rect by `effective_radius` on each side.**

Current: `Rect2(px_min, py - 30, px_max - px_min, 180)`
Fixed:   `Rect2(px_min - effective_radius, py - 30, px_max - px_min + 2 * effective_radius, 180)`

This catches arcs where the body center is just outside the platform but the body edge clips inside.

### Why NOT reduce the radius
- A smaller radius would let the current arc pass, but the body would STILL physically clip the corner
- A lower/flatter arc would then be chosen, which would also clip for the same reason
- The root cause is the clearance check doesn't account for body width at platform edges

### Alternative: Use `intersect_shape` with CircleShape2D
- At each arc_c point near a known platform, do a physics shape query with CircleShape2D(r=55)
- This directly answers "does the body overlap any collider at this position?"
- Previous attempt had issues with one-way platforms — but platforms are solid StaticBody2D
- Could limit to points where arc_c is within effective_radius of any platform's edge

### What to change
1. In `_check_arc_platform_edge_clearance`: expand the rect by effective_radius
2. OR: replace with `intersect_shape` at arc points near platform edges
3. The scoring already penalizes edge proximity — but the check should REJECT, not just penalize

## DO NOT IMPLEMENT YET — waiting for user direction
