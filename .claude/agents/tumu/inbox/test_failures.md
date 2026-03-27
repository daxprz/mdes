# Test Gate Failures — 2026-03-27

**Commit:** 1e4b511 (v0.10.20)

## chained — 7/8 FAIL
- `chained_leap_bounds`: `no_leaps` check found 2 leap edges (expected 0). Chain doesn't filter leap planning from precog.

## combat — 13/14 FAIL
- `cross_lower`: damage=0. Monster didn't deal damage to the dummy crossing lower platforms.

## scaling — 0/1 FAIL
- `giant_floor_to_P3`: damage=0. Scaled monster didn't deal damage.

## Notes
- `cross_lower` and `giant_floor_to_P3` are non-deterministic — monster may not reach the dummy within the time limit. May be flaky.
- `chained_leap_bounds` is a genuine bug — leap planner doesn't respect chain bounds.
