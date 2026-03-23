# Feature: Modal Dialog + Test State Machine + Observations

## Overview
Add a modal dialog system for test completion, test state machine with observer pattern,
and automatic observations capture by TUMU.

## Implementation Plan

### Phase 1: Modal Dialog System
1. RCON command: `modal <name> <message> <buttons_json> <timeout_seconds>`
   - Shows a modal dialog with message, buttons, countdown timer
   - Logs: `MODAL SHOW name=<name> buttons=["OK"] timeout=5`
   - Auto-dismisses after timeout
2. RCON command: `modal_dismiss <button_label>`
   - Programmatically clicks a button on the current modal
   - Logs: `MODAL DISMISS button=OK`
3. Render: centered overlay with message, countdown, clickable buttons

### Phase 2: Test State Machine
1. States: INITIALIZING → RUNNING → COMPLETE → FINALIZED
2. Script commands:
   - `emit <event_name> <value>` — fires a named event (e.g., `emit test_state RUNNING`)
   - `var <name> default=<value>` — declares a test variable (first line)
   - `modal <name> <message> <buttons> {var_name}` — uses variable for timeout
3. State transitions logged with timestamps
4. Test runner sets INITIALIZING at start, FINALIZED after modal dismissed

### Phase 3: Suite Runner Integration
- Suite runner listens for state transitions
- COMPLETE → modal shown → FINALIZED → suite advances to next test
- The 1.5s timer replaced by the modal timeout

### Phase 4: TUMU Observations
- When TUMU runs a test, after COMPLETE:
  1. Read the results.json output
  2. Generate observations.md with analysis
  3. Dismiss the modal via `modal_dismiss OK`
- observations.md stored alongside results.json in the test output dir

## Status: NOT STARTED
