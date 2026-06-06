# Feature: Modal Dialog + Test State Machine + Observations

## Collaboration Protocol

The observation flow is a collaboration between TUMU (AI) and the human:

```
1. TUMU initiates test via RCON
2. Test runs (setup, wait, checks)
3. Test reaches COMPLETE → modal appears (long timeout: 600s interactive, 10s automated)
4. TUMU sees COMPLETE, reads results.json, generates AI observations
5. TUMU does NOT dismiss yet — waits for the human
6. Human looks at the game, editor, violation markers, clicks things
7. Human optionally types observations to TUMU via Claude Code
8. TUMU consolidates AI + human observations into observations.md
9. TUMU dismisses the modal → test advances to FINALIZED
```

### Modal Modes
- **BLOCKING** — modal dialog with countdown, dismissable by click or RCON
- **TEST_EDITOR** — (future) control the editor to highlight specific things

### Timeout Behavior
- Interactive mode (default): 600s (10 min) — human has time to look
- Automated/suite mode: 10s — quick review
- Human or TUMU can dismiss at any time via click or `modal_dismiss`

### observations.md Structure
```markdown
# Observations — <test_name> — <timestamp>

## AI Observations (auto-generated)
- Test outcome: PASS/FAIL (N/M checks)
- Duration: Xs
- Per-check results with values
- Violations detected (positions, reasons)
- Breach events
- Suggested next steps

## Human Observations (from user input)
- (captured from Claude Code conversation)

## Consolidated Analysis
- (AI synthesis of both)
```

## Implementation Status

### Phase 1: Modal Dialog System ✓
- RCON: `modal <name> <message> <buttons_json> <timeout>`
- RCON: `modal_dismiss <button>`
- Visual overlay with countdown, clickable buttons

### Phase 2: Test State Machine ✓
- States: INITIALIZING → RUNNING → COMPLETE → FINALIZED
- `var`, `emit`, `modal` script commands
- State timestamps in results.json

### Phase 3: Suite Integration ✓
- Modal dismiss triggers queue advance
- `_waiting_for_modal` flag prevents stale dismiss

### Phase 4: TUMU Observation Flow
- [x] Results.json written with comprehensive data
- [ ] TUMU auto-reads results after COMPLETE
- [ ] TUMU generates AI observations section
- [ ] TUMU waits for human input
- [ ] TUMU consolidates and writes observations.md
- [ ] TUMU dismisses modal
