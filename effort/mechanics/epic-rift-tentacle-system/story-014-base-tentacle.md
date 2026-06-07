---
xid: STO-MECH-014
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-71q
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Base Tentacle

## Summary

A 14-segment verlet tentacle with phased behavior (confused, hunt, grab) and a class-change lockout, spawned via a red portal with ghost and smoke VFX.

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

- [x] Verlet physics tentacle (14 segments, ~126px) with purple visual
- [x] Phase 0 (0-5s): confused wiggling
- [x] Phase 1 (5-15s): hunt nearest non-owner player, lunge at 1.5x reach
- [x] Phase 2 (grab): 4 smashes (8 dmg each) + smoke VFX + fling
- [x] Red portal + ghost + smoke poof on class change
- [x] 15-second class-change lockout during rift


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

- **Source:** BACKLOG Story 28.1
- **Shipped in:** v0.9.7
- **History:** A 14-segment verlet tentacle with phased behavior (confused, hunt, grab) and a class-change lockout, spawned via a red portal with ghost and smoke VFX.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.7
