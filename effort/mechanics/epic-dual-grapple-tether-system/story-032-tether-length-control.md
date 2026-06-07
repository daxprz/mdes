---
xid: STO-MECH-032
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-yal
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Tether Length Control

## Summary

D-pad sets the tether target length before the second hook launches, with min/max constraints and a numeric/marker indicator.

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

- [x] D-pad UP/DOWN adjusts and stores _tether_target_length
- [x] Default tether length = current rope length at L2 press
- [x] TETHER_ACTIVE immediately pulls anchors to target length
- [x] Visual length indicator while adjusting
- [x] Length adjust speed = GRAPPLE_ROPE_ADJUST_SPEED (80 px/s)
- [x] Min 30px, max 900px tether length


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

- **Source:** EPIC_dual_grapple_tether.md Story 3
- **Shipped in:** v0.9.16
- **History:** D-pad sets the tether target length before the second hook launches, with min/max constraints and a numeric/marker indicator.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.16
