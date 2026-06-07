---
xid: STO-MECH-031
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-359
shipped: 2026-06-07
tasks: 12
complete: 9
---

# Tether Rope Entity

## Summary

A standalone tether.gd entity applies mass-weighted spring pull between two anchors, interacts with balloon float, and cleans up when either anchor is freed.

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

- [x] New script tether.gd: Node2D with anchor A/B, length, HP, segments
- [x] Per-frame distance check: pull force when distance > target length
- [x] Strong spring pull scaled by (distance - target_length)
- [x] Force divided by each anchor's mass (wall = infinite mass)
- [x] Enemy mass lookup with default 50.0
- [x] Apply force at enemy attachment points via segment weight
- [x] Tether interacts with balloon float (holds floating enemies down)
- [x] Tether entity added to "tethers" group
- [x] Tether cleans up if either anchor is freed


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

- **Source:** EPIC_dual_grapple_tether.md Story 2
- **Shipped in:** v0.9.16
- **History:** A standalone tether.gd entity applies mass-weighted spring pull between two anchors, interacts with balloon float, and cleans up when either anchor is freed.

## Status notes

- 2026-06-07: Closed with --force; 3/12 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.16
