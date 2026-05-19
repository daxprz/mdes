---
name: test
description: Run tests against the running Godot instance. Supports single tests, suites, gate checks, and sanity checks. Use when running or monitoring game tests.
disable-model-invocation: true
argument-hint: <run|suite|gate|sanity> [name] [options]
allowed-tools: Bash Read Glob Grep
---

# Test — Unified Test Runner

Run tests against the running Godot instance via RCON.

## Usage

- `/test run <name>` — Run a single test (e.g., `leap_floor_to_P1`)
- `/test suite <name>` — Run a test suite (e.g., `leaping`, `chained`, `combat`)
- `/test gate` — Run all stale gate suites, track results with git tags
- `/test sanity` — Quick check that Godot is running and systems work

## Arguments

Command: `$0`
Name/options: `$1`

## Common Preamble

Before any test, verify Godot is running:
```bash
echo "status" | nc -w1 localhost 9999
```
If no response, tell the user Godot is not running.

---

## `run` — Single Test

1. Read the test file: `data/tests/$1.json`
2. Run: `echo "run $1" | nc -w1 localhost 9999`
3. Wait for the test's `"wait"` duration + 10s buffer
4. Check results:
```bash
grep -E "PASS|FAIL|Result:|PRECOG|PATHFIND|LEAP|WALK|ARRIVED|DMG|debug:" /tmp/godot_debug.log | tail -40
```
5. Report: PASS/FAIL, check details, key diagnostic lines. If FAIL: identify likely root cause.

---

## `suite` — Test Suite

1. Run: `echo "suite $1 owait=0" | nc -w2 localhost 9999`
2. Poll at 1-second intervals (separate Bash calls, never blocking loops):
```bash
grep "SUITE_COMPLETE $1" /tmp/godot_debug.log | tail -1
```
3. When `SUITE_COMPLETE <name> X/Y` appears, report: which tests passed, which failed, diagnostic lines for failures.

---

## `gate` — Gate Suites

See [reference.md](reference.md) for the full gate protocol (staleness check, tag convention, suite discovery).

1. Read all suite JSONs in `data/tests/suites/`, filter to `"gate": true`
2. Check git tags: `git tag -l "ts/<suite>/*"`
3. Check staleness: `git log --oneline ts/<suite>/pass..HEAD -- "*.gd"`
4. Print status table (suite, tag state, stale?, action)
5. Run each stale suite via `echo "suite <name> owait=0" | nc -w2 localhost 9999`
6. Poll for `SUITE_COMPLETE` per suite
7. Tag results: `git tag -f "ts/<suite>/pass" HEAD` or `ts/<suite>/fail`
8. If failures, create/update `ai/agents/tumu/inbox/test_failures.md`
9. Print final report table

---

## `sanity` — Quick Health Check

1. `echo "status" | nc -w1 localhost 9999` — running?
2. `echo "debug list" | nc -w1 localhost 9999` — aspects registered?
3. `echo "enemies" | nc -w1 localhost 9999` — entity count
4. `echo "players" | nc -w1 localhost 9999` — player count
5. `echo "fps" | nc -w1 localhost 9999` — performance
6. `echo "tests" | nc -w1 localhost 9999` — available tests
7. Report summary.

## Rules

- **NEVER** sleep longer than 1 second when polling
- **NEVER** use blocking while/for loops for polling — use separate Bash tool calls
- **ALWAYS** use `nc -w1` or `nc -w2` (1-2 second timeouts)
- **ALWAYS** use `owait=0` for suite runs (instant test transitions)
