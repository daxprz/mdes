---
description: Run a test suite and report results
argument-hint: <suite_name> (e.g., leaping, chained, combat)
---

# Run Test Suite

Run a test suite against the running Godot instance and report results.

## Steps

1. Verify Godot is running:
```bash
echo "status" | nc -w1 localhost 9999
```
If not running, tell the user to launch Godot first.

2. Run the suite via RCON:
```bash
echo "suite $ARGUMENTS" | nc -w1 localhost 9999
```

3. Look up the suite file to determine total wait time:
- Read `data/tests/suites/$ARGUMENTS.json` to get the test list
- Read each test to sum up wait times + setup delays
- Wait for the total duration plus buffer

4. Monitor by polling status every 10 seconds:
```bash
echo "status" | nc -w1 localhost 9999
```

5. After completion, check the Godot log for results:
```bash
grep -E "PASS|FAIL|RESULTS|===.*PASSED" /tmp/godot_debug.log | tail -20
```

6. Report a summary: which tests passed, which failed, and key diagnostic lines for failures.
