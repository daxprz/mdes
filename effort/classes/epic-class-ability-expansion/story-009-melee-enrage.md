---
xid: STO-CLS-009
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-37z
shipped: 2026-06-07
tasks: 6
complete: 3
---

# Melee - Enrage

## Summary

Circle ability granting a temporary speed and damage boost with red-tint VFX.

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

- [x] Enrage ability on Circle (interact) - 10s duration, 45s cooldown
- [x] Enraged: 1.5x speed multiplier, 1.8x damage multiplier
- [x] Red tint VFX, "ENRAGE!" floating text


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

- **Source:** BACKLOG.md Story 15.1
- **Shipped in:** v0.9.5
- **History:** Circle ability granting a temporary speed and damage boost with red-tint VFX.

## Status notes

- 2026-06-07: Closed with --force; 3/6 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
