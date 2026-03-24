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

This means: changes near this code should trigger the `leaping` and `combat` suites.

These annotations are OPTIONAL. Without them, the system falls back to "any .gd change = all gate suites stale."

## Steps

### 1. Discover Gate Suites

Read all suite JSON files in `data/tests/suites/`. Filter to those with `"gate": true`.

### 2. Check Tag State

For each gate suite, check git tags:

```bash
git tag -l "ts/<suite>/*"
```

Determine state:
- **No tag exists** → NEVER_TESTED → must run
- **`ts/<suite>/pass` exists** → check if stale (step 3)
- **`ts/<suite>/fail` exists** → KNOWN_BROKEN → should run (might be fixed now)

### 3. Check Staleness

For suites with a `pass` tag, check if code changed since:

```bash
git log --oneline ts/<suite>/pass..HEAD -- "*.gd"
```

If commits exist that touch `.gd` files → suite is STALE.

**Refined check** (when `# TEST ts:<suite>` annotations exist in the codebase): only mark a suite stale if files that changed since its tag contain a `# TEST ts:<suite>` annotation for that specific suite. If no annotations exist anywhere, fall back to: any `.gd` change = all gate suites stale.

### 4. Print Status Table

Before running anything, print a table showing only gate suites:

```
Suite       | Tag State      | Stale? | Action
------------|----------------|--------|------------------
chained     | pass @ abc123  | NO     | SKIP
combat      | (none)         | -      | RUN (never tested)
leaping     | fail @ def456  | -      | RUN (known broken)
scaling     | pass @ abc123  | YES    | RUN
```

### 5. Run Stale/Needed Suites

For each gate suite that needs running:
1. Verify Godot is running: `echo "status" | nc -w2 localhost 9999`
2. If not running, warn and STOP — do NOT auto-launch
3. Run: `echo "suite <name> owait=0" | nc -w2 localhost 9999`
4. Wait: test count * 12s as baseline (suite runner handles sequencing)
5. Collect results: `scripts/run_test.sh` or parse Godot log for `=== X/Y PASSED ===`

### 6. Record Results

After each suite completes:

**If ALL tests passed:**
```bash
git tag -f "ts/<suite>/pass" HEAD
git tag -d "ts/<suite>/fail" 2>/dev/null
```

**If any test failed:**
```bash
git tag -f "ts/<suite>/fail" HEAD
git tag -d "ts/<suite>/pass" 2>/dev/null
```

### 7. Handle Failures

If any gate suite failed:
1. Create/update `.claude/agents/tumu/inbox/test_failures.md` with:
   - Suite name, which tests failed, timestamp, commit hash
2. Print failure summary

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
Failures tracked in: .claude/agents/tumu/inbox/test_failures.md
```

## Notes

- Tags are LOCAL only. Push with `git push origin --tags` if desired.
- Non-gate suites (`all`, `todo`) are never auto-run. Use them manually: `suite all owait=0` or `suite todo owait=600`.
- Gate suites must partition `all.json` — every test in exactly one gate suite.
- Estimated run time: ~5 min for all 4 gate suites (27 tests total at owait=0).
