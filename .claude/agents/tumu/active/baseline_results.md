# Baseline Test Results — 2026-03-23 (post-P1 fix)

Commit: `778d89e` (all suite + observations_wait=0 default)

## Score: 22/26 ALL PASS (85%)

Previous baseline: 13/24 (54%) → **+31% improvement**

| Test | Score | Status |
|------|-------|--------|
| quick | 3/3 | ALL PASS |
| same_floor_near | 3/3 | ALL PASS |
| same_floor_far | 3/3 | ALL PASS |
| corner_left | 3/3 | ALL PASS |
| corner_right | 3/3 | ALL PASS |
| hunt_P1 | 3/3 | ALL PASS |
| hunt_P2 | 3/3 | ALL PASS |
| hunt_P3 | 3/3 | ALL PASS |
| hunt_P4 | 3/3 | ALL PASS |
| floor_to_upper | 3/3 | ALL PASS |
| cross_lower | 3/3 | ALL PASS |
| leap_floor_to_P1 | 3/3 | ALL PASS |
| leap_floor_to_P2 | 3/3 | ALL PASS |
| leap_P2_to_P4 | 3/3 | ALL PASS |
| leap_cross_platforms | 3/3 | ALL PASS |
| leap_floor_to_P4 | 3/4 | FAIL: etz, order |
| P1_to_P3 | 4/4 | ALL PASS |
| P2_to_P4 | 4/4 | ALL PASS |
| verify_leap_graph_P0_P1 | 1/2 | FAIL: arc check |
| chained_wall_attack | 2/2 | ALL PASS |
| chained_platform | 2/2 | ALL PASS |
| chained_upper_platform | 2/3 | FAIL: no_damage |
| chained_upper_platform_etz | 2/3 | FAIL: no_damage |
| chained_floor | 2/2 | ALL PASS |
| chained_reach | 2/2 | ALL PASS |
| chained_above | 2/2 | ALL PASS |

## Remaining 4 failures

1. **leap_floor_to_P4**: ETZ not reached — multi-hop, monster doesn't visit zones in time
2. **verify_leap_graph_P0_P1**: arc check violation — body r=55 clips P1 corner (same P1 issue, different test constraints)
3. **chained_upper_platform**: no_damage FAIL — expects damage=0 (chain should prevent attack) but monster dealt damage. Chain constraint bug — monster reaches dummy despite chain length.
4. **chained_upper_platform_etz**: no_damage FAIL — same chain constraint bug
