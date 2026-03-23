# Baseline Test Results — 2026-03-23

Commit: `4dbfc16` (WIP: Arc edge penalty scoring)

## Suite Scores

| Suite | Score | Details |
|-------|-------|---------|
| leaping | **8/16** | 5 damage fails, 4 arc check fails, 2 ETZ fails |
| combat | **29/38** | 9 failures across 5 tests |
| chained | **13/15** | 2 failures across 2 tests |
| **TOTAL** | **50/69** | |

## Per-Test Breakdown

### Leaping Suite (8/16)

| Test | damage | fps | arc check | Other | Notes |
|------|--------|-----|-----------|-------|-------|
| leap_floor_to_P1 | PASS | PASS | **FAIL (0m 1v)** | | Arc violation: body r=55 too close to P1 edge disallow |
| leap_floor_to_P2 | PASS | PASS | **FAIL (0m 0v)** | | 0 matched — no arcs found? Or monitor issue |
| leap_P2_to_P4 | **FAIL (0)** | PASS | **FAIL (0m 0v)** | | No damage + no arc match |
| leap_cross_platforms | PASS | PASS | **FAIL (1m 1v)** | | 1 matched but 1 violation |
| leap_floor_to_P4 | **FAIL (0)** | PASS | **FAIL (1m 1v)** | ETZ: FAIL (0/2) | Multi-hop: damage=0, ETZ not reached |

### Combat Suite (29/38)

| Test | damage | fps | ik_peak | arc check | Notes |
|------|--------|-----|---------|-----------|-------|
| same_floor_near | PASS | PASS | PASS | — | |
| same_floor_far | PASS | PASS | PASS | — | |
| hunt_P1 | PASS | PASS | PASS | — | |
| hunt_P2 | PASS | PASS | PASS | — | |
| hunt_P3 | **FAIL (0)** | PASS | PASS | — | Monster doesn't reach P3 in time |
| hunt_P4 | **FAIL (0)** | PASS | PASS | — | Monster doesn't reach P4 in time |
| floor_to_upper | **FAIL (0)** | PASS | PASS | — | Monster doesn't reach upper platform |
| cross_lower | PASS | PASS | PASS | — | |
| P1_to_P3 | **FAIL (0)** | PASS | **FAIL (2572)** | **FAIL (0m 0v)** | IK spike + no arc match |
| P2_to_P4 | **FAIL (0)** | PASS | **FAIL (2035)** | **FAIL (0m 0v)** | IK spike + no arc match |
| corner_left | PASS | PASS | PASS | — | |
| corner_right | PASS | PASS | PASS | — | |

### Chained Suite (13/15)

| Test | damage | fps | Other | Notes |
|------|--------|-----|-------|-------|
| chained_wall_attack | PASS | PASS | — | |
| chained_platform | **FAIL (0)** | — | — | Only 1 check, damage=0 |
| chained_upper_platform | PASS | PASS | PASS (no_damage=0, bounded) | |
| chained_upper_platform_etz | PASS | **FAIL ETZ (0/2)** | PASS | ETZ not reached |
| chained_floor | PASS | PASS | — | |
| chained_reach | PASS | PASS | — | |
| chained_above | PASS | PASS | — | |

## Failure Categories

### 1. Arc check violations (body r=55 too close to disallow zones)
- leap_floor_to_P1, leap_cross_platforms, leap_floor_to_P4
- **Root cause**: monitor uses `body_radius + disallow_radius` for circle-capsule intersection. The planner produces arcs that clear physics but are within this combined radius of test disallow zones.
- **Fix needed**: understand why the planner doesn't reject these arcs given the body radius. The edge penalty scoring should push arcs away, but the disallow zones are tighter than the platform edge check catches.

### 2. Arc check 0 matched / 0 violations
- leap_floor_to_P2, P1_to_P3, P2_to_P4
- **Root cause**: no candidate edges found by the monitor — either no arcs exist between those platforms, or platform A/B circles don't match.

### 3. Damage = 0 (monster doesn't reach target)
- hunt_P3, hunt_P4, floor_to_upper, P1_to_P3, P2_to_P4, leap_P2_to_P4, leap_floor_to_P4, chained_platform
- **Root cause**: monster doesn't leap to the target platform in time. Exit_circle or breach aborts before damage.

### 4. IK peak too high
- P1_to_P3 (2572), P2_to_P4 (2035) — threshold is 2000
- **Root cause**: leap execution causes IK spikes

### 5. ETZ not reached
- leap_floor_to_P4 (0/2), chained_upper_platform_etz (0/2)
- **Root cause**: monster doesn't visit the expected platforms

## Next Steps (DO NOT START YET)

### 4A. Understand why r=55 isn't being rejected during planning
The planner's platform edge clearance check uses a surface_rect that may not cover the exact area where the disallow zones are placed. Need to verify the planner's circle sweep / edge check rejects arcs that the monitor's circle check catches.

### 4B. Tune the body radius clearance
After fixing 4A, incrementally adjust clearance until tests pass reliably. Find the "sweet spot" where arcs have enough clearance for the body width without being rejected unnecessarily.

### ETZ/DAZ cleanup
User reports: ETZ-1, ETZ-2, DAZ-1 zones persist visually after tests. Need `clearzones` at the start of each test or zone cleanup between suite tests.
