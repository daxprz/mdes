# Baseline Test Results — 2026-03-23 (with file output)

Commit: `316adc9` + auto-clear zones + test output files
Output dir: `user://test-output/0.9.25/`

## Suite Scores

| Suite | Score | Notes |
|-------|-------|-------|
| leaping | **1/5** | Only leap_cross_platforms passes all checks |
| combat | **7/12** | Floor/same-level tests pass; platform-to-platform tests fail |
| chained | **6/7** | Only chained_platform fails |
| **TOTAL** | **14/24 suites** | |

## Per-Test Results (from output files)

| Test | Score | Duration | All Pass | Failures |
|------|-------|----------|----------|----------|
| same_floor_near | 3/3 | 3.8s | YES | |
| same_floor_far | 3/3 | 5.5s | YES | |
| hunt_P1 | 3/3 | 3.9s | YES | |
| hunt_P2 | 3/3 | 4.3s | YES | |
| hunt_P3 | 2/3 | 18.8s | no | damage=0 |
| hunt_P4 | 2/3 | 18.6s | no | damage=0 |
| floor_to_upper | 2/3 | 19.3s | no | damage=0 |
| cross_lower | 3/3 | 5.7s | YES | |
| P1_to_P3 | 1/4 | 18.8s | no | damage=0, ik=2572, arc=0m/0v |
| P2_to_P4 | 1/4 | 18.8s | no | damage=0, ik=2035, arc=0m/0v |
| corner_left | 3/3 | 5.8s | YES | |
| corner_right | 3/3 | 5.9s | YES | |
| leap_floor_to_P1 | 2/3 | 6.1s | no | arc: 0m/1v (body r=55 disallow breach) |
| leap_floor_to_P2 | 2/3 | 7.8s | no | arc: 0m/0v (no candidates found) |
| leap_P2_to_P4 | 1/3 | 23.2s | no | damage=0, arc: 0m/0v |
| leap_cross_platforms | 3/3 | 5.4s | YES | |
| leap_floor_to_P4 | 1/4 | 23.9s | no | damage=0, etz=0, arc: 1m/1v |
| chained_wall_attack | 2/2 | 6.2s | YES | |
| chained_platform | 1/2 | 24.4s | no | damage=0 |
| chained_upper_platform | 3/3 | 13.8s | YES | |
| chained_upper_platform_etz | 2/3 | 28.8s | no | etz=0/2 |
| chained_floor | 2/2 | 4.5s | YES | |
| chained_reach | 2/2 | 18.4s | YES | |
| chained_above | 2/2 | 12.9s | YES | |

## Passing Tests (13/24)

same_floor_near, same_floor_far, hunt_P1, hunt_P2, cross_lower,
corner_left, corner_right, leap_cross_platforms, chained_wall_attack,
chained_upper_platform, chained_floor, chained_reach, chained_above

## Failure Categories

### Arc violations (body r=55 too close to disallow)
- leap_floor_to_P1 (1 violation), leap_floor_to_P4 (1 violation)
- **4A needed**: planner doesn't reject arcs that the monitor catches

### Arc 0 matched / 0 violations
- leap_floor_to_P2, P1_to_P3, P2_to_P4, leap_P2_to_P4
- Monitor finds no candidate edges — either graph doesn't have the arc or platform A/B mismatch

### Damage = 0 (monster doesn't attack in time)
- hunt_P3, hunt_P4, floor_to_upper, P1_to_P3, P2_to_P4, leap_P2_to_P4, leap_floor_to_P4, chained_platform
- Monster reaches platform but breach/exit_circle aborts before damage

### IK peak too high
- P1_to_P3 (2572), P2_to_P4 (2035) — threshold 2000

### ETZ not reached
- leap_floor_to_P4 (0/2), chained_upper_platform_etz (0/2)

## Next Steps
- 4A: Understand why r=55 body arcs aren't rejected by the planner
- 4B: Tune the sweet spot
