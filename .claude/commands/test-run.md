---
description: Run a single test and report results
argument-hint: <test_name> (e.g., leap_floor_to_P1, chained_upper_platform)
---

# Run Single Test

Run a single test against the running Godot instance and report detailed results.

## Steps

1. Verify Godot is running:
```bash
echo "status" | nc -w1 localhost 9999
```

2. Read the test file to understand what it does:
```
data/tests/$ARGUMENTS.json
```

3. Run the test:
```bash
echo "run $ARGUMENTS" | nc -w1 localhost 9999
```

4. Wait for the test's `"wait"` duration plus setup time (typically +10s buffer).

5. Grep the Godot log for results and diagnostics:
```bash
grep -E "PASS|FAIL|Result:|PRECOG|PATHFIND|LEAP|WALK|ARRIVED|DMG|debug:" /tmp/godot_debug.log | tail -40
```

6. Report:
   - PASS/FAIL status and check details
   - Key diagnostic lines (pathfinding decisions, leap planning, damage)
   - If FAIL: identify the likely root cause from debug output
