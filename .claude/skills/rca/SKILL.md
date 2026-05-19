---
name: rca
description: Root cause analysis for failing game tests. Triages failures from test-gate, analyzes each via RCON debug output and test results, fixes issues, and re-runs until clean. Use when tests are failing.
disable-model-invocation: true
allowed-tools: Bash Read Edit Write Glob Grep Skill
context: fork
---

# RCA — Root Cause Analysis for Test Failures

Iteratively triage, analyze, and fix all failing tests.

## Steps

### 1. Identify Failures

Collect failing tests from:
- `ai/agents/tumu/inbox/test_failures.md` — recorded failures from `/test gate`
- `git tag -l "ts/*/fail"` — failed gate suites
- Run `echo "suite todo owait=0" | nc -w3 localhost 9999` if todo suite has entries

### 2. Populate TODO Suite

Add all failing test names to `data/tests/suites/todo.json`.

### 3. Run TODO Suite

```bash
echo "suite todo owait=0" | nc -w3 localhost 9999
```

Poll for `SUITE_COMPLETE todo` in `/tmp/godot_debug.log`.

### 4. For Each Failure — RCA

1. **Read the test JSON** — understand what it checks
2. **Read test output** — check `user://test-output/` for results.json
3. **Check logs** — grep `/tmp/godot_debug.log` for the test name
4. **Classify**:
   - **FLAKY** — passes sometimes. Cause: timing, AI randomness
   - **BUG** — consistent failure from code defect
   - **TEST_ISSUE** — expectations wrong or outdated
5. **Fix**:
   - FLAKY: widen thresholds, increase wait time
   - BUG: fix the code, NOT the test
   - TEST_ISSUE: update test expectations

### 5. Re-run TODO After Each Fix

Verify fix and check for regressions.

### 6. Evict Fixed Tests

Remove passing tests from `todo.json`.

### 7. Repeat

Loop steps 3-6 until `todo.json` is empty.

### 8. Re-run Gate

Run `/test gate` to verify all gate suites pass.

### 9. Report

Summary:
- Which tests were flaky vs bugs vs test issues
- What code changes were made
- Final gate suite scores
