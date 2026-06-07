---
xid: STO-SND-009
parent: ./epic.md
kind: story
effort: snd
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-udgs
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Bar Scheduler + Movement Transitions

## Summary

Add a BarScheduler that detects cycle boundaries, advances the Record, and hot-swaps the cyclist pattern; wire MusicManager's new API (load/play/transition_to/activate_turnaround). Game events transition movements through bridges, with CPS ramping at boundaries.

## Context

_(Why is this story needed? What does it depend on? Link to the parent
epic. If this is a discovered-from another story, surface the link.)_

## Problem

_(What specific problem does this story solve? Concrete; the reader
should be able to verify completion without re-reading the epic.)_

## Design

### Approach

_(How will this be implemented? Reference HUGs that constrain the
implementation choice; cite alternatives only when they shaped the
final pick.)_

### Changes

| File | Change |
|------|--------|
| `path/to/file` | _(add / modify / extract)_ |
| `path/to/test` | _(add tests for the new behavior)_ |

## Definition of Done

- [x] BarScheduler: process(), transition_to_movement, activate_turnaround
- [x] MusicManager new API: load/play_composition, transition_to, get_record
- [x] Wire title_screen.gd to composition API; remove old segment queue
- [x] Composition reset button + per-note velocity + boundary fix
- [x] CPS ramping and battle-movement transitions


## Testing

### Unit / fixture tests

- [ ] _(Specific case.)_
- [ ] _(Edge case.)_

### Integration

- [ ] _(Scenario.)_

## Out of scope

- _(Things deliberately deferred to a later story. Be explicit — the
  reader should know what's *not* changing.)_

## Implementation Notes

_(Fill in during / after implementation. Capture what diverged from
the original design and why — useful for the retrospective + for
operators reading this story in a year.)_

### What Changed

_(Actual implementation. May differ from § Design above.)_

### Files Modified

- `path/to/file` — _(what changed)_

### Gotchas

_(Anything surprising or worth noting for future readers.)_


## TUMU Provenance

- **Source:** composition_architecture.md Phases 4-5; commits 'composition architecture' (v0.10.72), 'CPS ramping, battle movement' (v0.10.75)
- **Shipped in:** v0.10.72
- **History:** Add a BarScheduler that detects cycle boundaries, advances the Record, and hot-swaps the cyclist pattern; wire MusicManager's new API (load/play/transition_to/activate_turnaround). Game events transition movements through bridges, with CPS ramping at boundaries.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.72
