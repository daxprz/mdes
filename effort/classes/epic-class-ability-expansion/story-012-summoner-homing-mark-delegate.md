---
xid: STO-CLS-012
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-40b
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Summoner - Homing Mark + Delegate Mode

## Summary

Homing-mark basic attack and a Delegate Mode where the summoner freezes and controls a faster ghost.

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

- [x] Basic attack changed to Homing Mark (slow homing orb, marks target for +damage from buddies, 6s duration)
- [x] Delegate Mode on Circle (30s cooldown, 10s duration) - summoner freezes, ghost moves freely
- [x] Ghost: 1.5x speed, 1.5x jump, can dash. Buddies follow ghost
- [x] Summoner takes 1.5x damage while delegating; hit >= 15 cancels it
- [x] Aether rift teleport VFX on enter/exit delegate mode


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

- **Source:** BACKLOG.md Story 15.4
- **Shipped in:** v0.9.5
- **History:** Homing-mark basic attack and a Delegate Mode where the summoner freezes and controls a faster ghost.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
