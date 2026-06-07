---
xid: STO-MECH-016
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-b2u
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Tentacle Sub-Health

## Summary

A 50 HP sub-health absorbs damage before the enemy, scales the rift size, and on depletion restores the enemy and unlocks the owner.

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

- [x] 50 HP sub-health absorbs damage before enemy takes it
- [x] Rift size scales with tentacle health
- [x] At 0 HP: purple smoke puff, enemy restored, owner unlocked
- [x] Patched boss_base.gd + all 18 enemy take_damage functions


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

- **Source:** BACKLOG Story 28.3
- **Shipped in:** v0.9.7
- **History:** A 50 HP sub-health absorbs damage before the enemy, scales the rift size, and on depletion restores the enemy and unlocks the owner.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.7
