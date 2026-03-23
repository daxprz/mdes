# Fix Plan — Stack-Ranked Problem Categories

Based on baseline results (13/24 tests pass, 11 fail).

## Problem Categories (stack-ranked by impact)

### P1: Body circle clips collision objects (5 tests)
**Tests:** leap_floor_to_P1, leap_cross_platforms, leap_floor_to_P4, P1_to_P3(?), P2_to_P4(?)
**Symptom:** Arc check shows violations — body r=55 clips platform corners
**Root cause:** Planner doesn't check body circle against physics colliders at arc points
**Fix:** Use `intersect_shape` with `CircleShape2D(r=effective_radius)` at each arc_c point.
Skip first 3 and last 3 points (inside launch/landing platforms). Skip ignore_rect (destination).
This replaces `_check_arc_platform_edge_clearance` and `_check_arc_circle_sweep` with a single
unified physics check.
**Impact:** Fixes arc violations across all tests. Planner produces wider arcs that clear corners.

### P2: Monster doesn't reach target platform in time (8 tests)
**Tests:** hunt_P3, hunt_P4, floor_to_upper, P1_to_P3, P2_to_P4, leap_P2_to_P4, leap_floor_to_P4, chained_platform
**Symptom:** damage=0, exit_circle/breach aborts before monster attacks
**Root cause:** Multiple — gap detection not triggering, arc planning too restrictive (P1 fix
may help by offering more valid arcs), multi-hop taking too long
**Fix:** After P1 fix, re-evaluate. Some may be fixed by better arcs. Others may need gap
detection improvements or longer wait times.
**Impact:** Most common failure category.

### P3: No arc candidates found (4 tests)
**Tests:** leap_floor_to_P2, P1_to_P3, P2_to_P4, leap_P2_to_P4
**Symptom:** Arc check: 0 matched, 0 violations
**Root cause:** Monitor finds no edges between platform A and B. Either the graph doesn't
contain the edge, or the platform A/B circle matching fails.
**Fix:** After P1 fix, check if new arcs appear. If not, investigate the precog graph
building — are edges being rejected by the stricter clearance? Might need to log which
arcs are rejected and why.
**Impact:** Overlaps significantly with P2.

### P4: IK peak too high (2 tests)
**Tests:** P1_to_P3 (2572), P2_to_P4 (2035) — threshold 2000
**Symptom:** ik_peak check fails
**Root cause:** Leap execution causes IK spikes — skeleton stretches during flight
**Fix:** Separate from arc planning. May need IK damping during leap states.
**Impact:** Low — only 2 tests, and the threshold may need adjustment.

### P5: ETZ not reached (2 tests)
**Tests:** leap_floor_to_P4 (0/2), chained_upper_platform_etz (0/2)
**Symptom:** Monster doesn't visit expected platforms
**Root cause:** Multi-hop path not executing, or chain constraint prevents reaching
**Fix:** After P1/P2 fixes, re-evaluate. May resolve with better arc planning.
**Impact:** Low — secondary to P2.

## Execution Order

1. **Fix P1** (body circle vs collision objects) → regression test ALL suites
2. **Re-evaluate P2/P3** with improved arcs → identify remaining failures
3. **Fix remaining P2** (gap detection, timing) → regression test
4. **Fix P4** (IK damping) → regression test
5. **Fix P5** (ETZ) → final regression

### P6: Arc distance optimization (low priority)
**Tests:** leap_floor_to_P1 (observed)
**Symptom:** Monster chooses a long-distance arc when a shorter one would clear better
**Root cause:** Scoring favors proximity to target over clearance distance
**Fix:** Improve arc scoring to prefer shorter travel distance when multiple arcs are valid
**Impact:** Low — arcs work, just suboptimal

## Current Status: P1 IN PROGRESS — body circle clearance via intersect_shape
- `_check_arc_body_clearance` implemented but landing zone ignore rect needs tuning
- The check correctly rejects arcs that clip corners
- User confirmed: violation renders correctly, body circle shows the clip
- Next: ensure the planner rejects these arcs so the monitor finds 0 violations
