# RCA Test Failures

Root-cause analyze and fix failing tests through iterative triage.

## Steps

### 1. Identify Failures

Collect all failing tests from the last test-gate run. Check:
- `.claude/agents/tumu/inbox/test_failures.md` for recorded failures
- `git tag -l "ts/*/fail"` for failed suites
- Run `suite todo owait=0` if the todo suite has entries

### 2. Populate TODO Suite

Add all failing test names to `data/tests/suites/todo.json`. This is the working list.

### 3. Run TODO Suite

```bash
echo "suite todo owait=0" | nc -w3 localhost 9999
```

Poll for `SUITE_COMPLETE todo` in `/tmp/godot_debug.log`.

### 4. For Each Failure — RCA

For each test that failed:

1. **Read the test JSON** — understand what it checks
2. **Read the test output** — check `user://test-output/` for results.json with check values, violations, breach details
3. **Check the logs** — grep for the test name in `/tmp/godot_debug.log` to find PASS/FAIL lines with values
4. **Classify the failure**:
   - **FLAKY** — non-deterministic, passes sometimes. Cause: timing, monster AI randomness, platform positioning
   - **BUG** — consistent failure caused by a code defect
   - **TEST_ISSUE** — the test's expectations are wrong or outdated
5. **Fix it**:
   - FLAKY: increase wait time, widen thresholds, or add retry logic
   - BUG: fix the code, not the test
   - TEST_ISSUE: update the test expectations

### 5. Re-run TODO After Each Fix

After fixing a test, re-run the TODO suite to verify:
- The fixed test now passes
- No other tests regressed

### 6. Evict Fixed Tests

Remove passing tests from `todo.json`. Only failures remain.

### 7. Repeat

Loop steps 3-6 until `todo.json` is empty (all tests pass).

### 8. Re-run Gate Suites

Once TODO is empty, run the full test-gate to verify all gate suites pass:

```
/test-gate
```

### 9. Report

Print a summary of what was found and fixed:
- Which tests were flaky vs bugs vs test issues
- What code changes were made
- Final gate suite scores
