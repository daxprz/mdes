---
xid: STO-MECH-002
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-flq
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Trap Types

## Summary

Core damaging traps with tuned damage and cooldowns, plus signal-based pressure plates that trigger linked traps.

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

- [x] Spike floors (deal damage on contact) - 15 dmg, 0.5s cooldown
- [x] Swinging pendulum blades (timed obstacle) - 20 dmg, sin() swing
- [x] Arrow traps (shoot from walls on a timer) - 10 dmg, 2.5s interval
- [x] Lava/acid pools (instant kill or heavy damage) - 30 dmg/0.3s + knockback
- [x] Pressure plates that trigger traps - signal-based, links to other traps


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

- **Source:** BACKLOG Story 7.1
- **Shipped in:** v0.9.4
- **History:** Core damaging traps with tuned damage and cooldowns, plus signal-based pressure plates that trigger linked traps.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.4
