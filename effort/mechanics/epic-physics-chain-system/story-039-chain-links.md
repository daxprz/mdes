---
xid: STO-MECH-039
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-uyb4
shipped: 2026-06-07
tasks: 11
complete: 8
---

# Chain Links (Physics Bodies)

## Summary

Replaces chain rendering with physics-body links sized from a configurable link length, joint-connected with fixed endpoints, and the existing alternating-segment visual.

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

- [x] Define CHAIN_LINK_LENGTH constant (default 8px)
- [x] Link count from target_length / CHAIN_LINK_LENGTH
- [x] Spawn each link as a physics body with collision shape
- [x] Link collision layer excludes players, includes world
- [x] Connect links with joints (rotate, no stretch)
- [x] Endpoint A: joint to static anchor at attachment point
- [x] Endpoint B: same as A for other end
- [x] Render alternating thin/thick segments from link positions


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

- **Source:** EPIC_physics_chains.md Story 1
- **Shipped in:** v0.9.19
- **History:** Replaces chain rendering with physics-body links sized from a configurable link length, joint-connected with fixed endpoints, and the existing alternating-segment visual.

## Status notes

- 2026-06-07: Closed with --force; 3/11 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.19
