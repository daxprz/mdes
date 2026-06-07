---
xid: STO-MECH-043
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-mqln
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Creature Attachment

## Summary

Chains attach to creatures via a tracking kinematic anchor, freeze with the creature, and trigger a breakaway sequence when all chains break.

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

- [x] Creature endpoint joint tracks attachment point position
- [x] Kinematic anchor moves with creature; chain responds
- [x] Anchor stays fixed when creature is physics_frozen
- [x] Breakaway sequence when all creature chains break


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

- **Source:** EPIC_physics_chains.md Story 5
- **Shipped in:** v0.9.21
- **History:** Chains attach to creatures via a tracking kinematic anchor, freeze with the creature, and trigger a breakaway sequence when all chains break.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.21
