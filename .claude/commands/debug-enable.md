---
description: Enable debug logging for a group of aspects
argument-hint: <group> (e.g., pathing, precog, leap_attack, body_mechanics, chain)
---

# Enable Debug Logging

Enable textual logging for all aspects in a debug group.

## Steps

1. Enable logging for the group:
```bash
echo "debug log $ARGUMENTS" | nc -w1 localhost 9999
```

2. Verify with debug list (filtered):
```bash
echo "debug list" | nc -w1 localhost 9999
```

3. Report which aspects were enabled.

## Common Groups

- `pathing` — waypoints, walk/run path, platform leaps
- `precog` — platform detection, graph edges, pathfinding, ball landings
- `leap_attack` — strike zone, arc planning, ray casts, chosen arc
- `body_mechanics` — skeleton, IK, collision shapes
- `state_info` — state text, target indicator, IK metrics
- `chain` — tether arc, chain barrier
- `splay_poses` — pre/post physics poses, chain/anchor points
