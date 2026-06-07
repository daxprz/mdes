---
xid: STO-MECH-033
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-t2y
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Body Part Targeting

## Summary

Tether hooks snap to nearest attachment points on enemies, applying weight-aware forces and supporting same-enemy and cross-enemy tethers.

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

- [x] Hook snaps to nearest attachment point in range on enemy hit
- [x] Store attachment point name; forces applied at that skeleton position
- [x] Force at attachment point uses get_segment_weight()
- [x] Support tethering two parts on the same enemy
- [x] Support tethering parts across different enemies
- [x] Rope endpoints track attachment point world position each frame


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

- **Source:** EPIC_dual_grapple_tether.md Story 4
- **Shipped in:** v0.9.16
- **History:** Tether hooks snap to nearest attachment points on enemies, applying weight-aware forces and supporting same-enemy and cross-enemy tethers.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.16
