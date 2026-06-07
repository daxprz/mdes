---
xid: STO-MECH-025
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-yah
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Power Control

## Summary

Trigger-hold power scaling with a lockable power level, direction reversal, and a charge-bar lock indicator.

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

- [x] Pull strength scales with L2 hold time (300-1800 px/s)
- [x] Partial trigger pull = proportional max power cap
- [x] RB reverses power direction, release RB locks power level
- [x] Locked power persists across shots, charges up to lock level
- [x] Lock indicator (white tick + gold diamond) on charge bar


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

- **Source:** BACKLOG Story 31.2
- **Shipped in:** v0.9.7
- **History:** Trigger-hold power scaling with a lockable power level, direction reversal, and a charge-bar lock indicator.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.7
