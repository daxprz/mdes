---
description: Determine which test suites are stale, run them, and track results via git tags
---

# Test Gate

Determine which gate suites need to run based on code changes since last test, run them, and record pass/fail status as git tags.

## Suite Types

Each suite JSON in `data/tests/suites/` has a `"gate"` field:
- **`"gate": true`** — included in test-gate runs. These suites partition ALL tests with no overlaps.
- **`"gate": false`** — excluded from test-gate. Used for manual runs only (`all` = everything, `todo` = known failures).

Current gate suites: `chained`, `combat`, `leaping`, `scaling`
Non-gate suites: `all`, `todo`

Gate suites MUST collectively cover every test in `all.json` with NO overlaps. If a new test is added, it must go into exactly one gate suite.

## Tag Convention

Test suite results are tracked with local git tags under the `ts/` namespace:
- `ts/<suite>/pass` — suite passed at this commit
- `ts/<suite>/fail` — suite failed at this commit

Tags are force-moved (`git tag -f`) to HEAD after each run. Only one of pass/fail exists per suite at any time.

## Code Annotations

Source files can declare which suites they affect with trailing comments:

```gdscript
func _plan_leap_to_surface(...):  # TEST ts:leaping ts:combat
```

These are OPTIONAL. Without them, any `.gd` change = all gate suites stale.

## Steps

### 1. Discover Gate Suites

Read all suite JSON files in `data/tests/suites/`. Filter to those with `"gate": true`.

### 2. Check Tag State

For each gate suite, check git tags:

```bash
git tag -l "ts/<suite>/*"
```

- **No tag exists** → NEVER_TESTED → must run
- **`ts/<suite>/pass` exists** → check if stale (step 3)
- **`ts/<suite>/fail` exists** → KNOWN_BROKEN → should run

### 3. Check Staleness

For suites with a `pass` tag at HEAD → CLEAN, skip. Otherwise check if code changed:

```bash
git log --oneline ts/<suite>/pass..HEAD -- "*.gd"
```

If `.gd` files changed → STALE → must run.

### 4. Print Status Table

```
Suite       | Tag State      | Stale? | Action
------------|----------------|--------|------------------
chained     | pass @ abc123  | NO     | SKIP
combat      | (none)         | -      | RUN (never tested)
leaping     | fail @ def456  | -      | RUN (known broken)
scaling     | pass @ abc123  | YES    | RUN
```

### 5. Run Suites

Run each stale/needed gate suite via RCON suite command and poll for completion.

**IMPORTANT: Always use the suite API, never run tests individually.**

For each suite:
1. Verify Godot is running: `echo "status" | nc -w2 localhost 9999`
2. If not running, warn and STOP
3. Start the suite:
```bash
echo "suite <name> owait=0" | nc -w2 localhost 9999
```
4. Poll at 1-second intervals using SEPARATE Bash calls (never a blocking loop). Check the Godot log for the suite completion line:
```bash
# Each poll is a separate Bash tool call — never use while/loop
grep "SUITE_COMPLETE <name>" /tmp/godot_debug.log | tail -1
```
The line format is: `SUITE_COMPLETE <suite_name> X/Y` where X=passed, Y=total.
When this line appears for the current suite (that wasn't there before), the suite is done.
5. Parse the result: extract X and Y from `SUITE_COMPLETE <name> X/Y`.

The suite command also supports skipping tests:
```bash
echo "suite combat owait=0 skip leap_floor_to_P4" | nc -w2 localhost 9999
```

**IMPORTANT**: Never use `sleep` with values greater than 1.

### 6. Record Results

After each suite completes:

**If ALL tests passed (X == Y):**
```bash
git tag -f "ts/<suite>/pass" HEAD
git tag -d "ts/<suite>/fail" 2>/dev/null
```

**If any test failed (X < Y):**
```bash
git tag -f "ts/<suite>/fail" HEAD
git tag -d "ts/<suite>/pass" 2>/dev/null
```

### 7. Handle Failures

If any gate suite failed, create/update `.claude/agents/tumu/inbox/test_failures.md` with suite name, score, timestamp, commit hash.

### 8. Final Report

```
Test Gate Results @ <commit>
Suite       | Result  | Score
------------|---------|-------
chained     | PASS    | 7/7
combat      | PASS    | 14/14
leaping     | FAIL    | 4/5
scaling     | PASS    | 1/1

Tags updated: ts/chained/pass, ts/combat/pass, ts/leaping/fail, ts/scaling/pass
```

## Notes

- Tags are LOCAL only. Push with `git push origin --tags` if desired.
- Non-gate suites (`all`, `todo`) are never auto-run.
- Gate suites must partition `all.json` — every test in exactly one gate suite, no overlaps.
- Estimated run time: ~5 min for all 4 gate suites (27 tests at owait=0).
