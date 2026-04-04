# Test Report — 2026-03-23T13:17 — suite all owait=0

## Summary: 25/26 ALL PASS (96%)

Previous: 22/26 (85%) → 13/24 (54%) original baseline

| # | Test | Score | Duration | Status |
|---|------|-------|----------|--------|
| 1 | quick | 3/3 | 3.6s | ALL PASS |
| 2 | same_floor_near | 3/3 | 3.0s | ALL PASS |
| 3 | same_floor_far | 3/3 | 5.3s | ALL PASS |
| 4 | corner_left | 3/3 | 5.6s | ALL PASS |
| 5 | corner_right | 3/3 | 5.6s | ALL PASS |
| 6 | hunt_P1 | 3/3 | 8.6s | ALL PASS |
| 7 | hunt_P2 | 3/3 | 4.5s | ALL PASS |
| 8 | hunt_P3 | 3/3 | 10.2s | ALL PASS |
| 9 | hunt_P4 | 3/3 | 8.9s | ALL PASS |
| 10 | floor_to_upper | 3/3 | 8.6s | ALL PASS |
| 11 | cross_lower | 3/3 | 7.5s | ALL PASS |
| 12 | leap_floor_to_P1 | 3/3 | 7.2s | ALL PASS |
| 13 | leap_floor_to_P2 | 3/3 | 6.7s | ALL PASS |
| 14 | leap_P2_to_P4 | 3/3 | 5.0s | ALL PASS |
| 15 | leap_cross_platforms | 3/3 | 5.1s | ALL PASS |
| 16 | leap_floor_to_P4 | 3/4 | 6.9s | FAIL: etz |
| 17 | P1_to_P3 | 4/4 | 5.4s | ALL PASS |
| 18 | P2_to_P4 | 4/4 | 5.7s | ALL PASS |
| 19 | verify_leap_graph_P0_P1 | 2/2 | 6.5s | ALL PASS |
| 20 | chained_wall_attack | 2/2 | 13.2s | ALL PASS |
| 21 | chained_platform | 2/2 | 7.3s | ALL PASS |
| 22 | chained_upper_platform | 3/3 | 8.2s | ALL PASS |
| 23 | chained_upper_platform_etz | 3/3 | 9.7s | ALL PASS |
| 24 | chained_floor | 2/2 | 18.2s | ALL PASS |
| 25 | chained_reach | 2/2 | 8.2s | ALL PASS |
| 26 | chained_above | 2/2 | 11.7s | ALL PASS |

## Remaining failure

**leap_floor_to_P4**: ETZ check fails — monster doesn't visit the expected zones
during the multi-hop (floor → P2 → P4). The arc checks and damage pass.
This is P5 in the fix plan.
