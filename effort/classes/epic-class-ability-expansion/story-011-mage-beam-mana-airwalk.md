---
xid: STO-CLS-011
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-86a
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Mage - Beam of Light + Mana Potion + Air-Walk

## Summary

Rapid-fire bolts, a Mana Potion special, a charged Beam of Light, and an Air-Walk Circle ability.

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

- [x] Rapid-fire magic bolts (6 damage each, 450px/s, costs mana)
- [x] Special changed to Mana Potion (restores 60% max mana)
- [x] Charge attack: Beam of Light (raycast, 40-120 damage, multi-hit, scales with charge)
- [x] Air-Walk ability on Circle (5s duration, 10s cooldown, no gravity while active)


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

- **Source:** BACKLOG.md Story 15.3
- **Shipped in:** v0.9.5
- **History:** Rapid-fire bolts, a Mana Potion special, a charged Beam of Light, and an Air-Walk Circle ability.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
