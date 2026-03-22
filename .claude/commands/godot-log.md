---
description: Show recent Godot output, optionally filtered
argument-hint: "[filter_pattern] [line_count]" (e.g., "PRECOG 30" or "FAIL")
---

# Show Godot Log

Display recent Godot output from the debug log.

## Steps

1. If arguments contain a filter pattern, grep for it:
```bash
grep -E "<pattern>" /tmp/godot_debug.log | tail -<count>
```

2. If no arguments, show last 40 lines:
```bash
tail -40 /tmp/godot_debug.log
```

3. Common filter patterns:
   - `PRECOG|PATHFIND` — precognition pathfinding decisions
   - `LEAP|PLAN_FAIL` — leap planning and failures
   - `PASS|FAIL|Result` — test results
   - `DMG|BLOCKED` — damage dealt/blocked
   - `WALK|ARRIVED|HOP` — pathing execution
   - `debug:` — debug profile apply/clear events
