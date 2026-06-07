---
xid: STO-CLS-018
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-b0f
shipped: 2026-06-07
tasks: 11
complete: 8
---

# Base Balloonist Class

## Summary

Adds BALLOONIST with stats, sprites, physics-string balloon darts, Pop All special, giant-balloon charge, and self-float.

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

- [x] Add BALLOONIST to CharacterClass enum + stats (80 HP, 90 mana, 100 speed, 1.0 mana regen)
- [x] Create balloonist topdown + side spritesheets
- [x] Basic attack: balloon darts (physics string with 12 segments, teardrop-shaped balloons)
- [x] Balloon physics: repulsion between balloons, wind sensitivity, weight system
- [x] 3x fire rate, max 10 active balloons
- [x] Special: Pop All (Triangle) - pop all active balloons, release H2 gas
- [x] Charge attack: giant balloon (larger, more lift, scales with charge)
- [x] Circle ability: self-float (attach balloon to self for flight)


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

- **Source:** BACKLOG.md Story 21.1
- **Shipped in:** v0.9.5
- **History:** Adds BALLOONIST with stats, sprites, physics-string balloon darts, Pop All special, giant-balloon charge, and self-float.

## Status notes

- 2026-06-07: Closed with --force; 3/11 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
