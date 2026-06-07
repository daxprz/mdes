---
xid: STO-DSGN-002
parent: ./epic.md
kind: story
effort: dsgn
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-3xb
shipped: 2026-06-07
tasks: 6
complete: 3
---

# Overworld Boundaries

## Summary

Constrain the playable overworld with walls, fences, and visual barriers, plus camera limits so players cannot see off the map.

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

- [x] Add proper walls/fences around the playable overworld area
- [x] Add visual boundaries (cliffs, water, dense forest)
- [x] Camera limits so players can't see outside the map


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

- **Source:** BACKLOG.md Story 3.2; git: 'Fix overworld: visible chasm blocker + smaller tower visuals'
- **Shipped in:** v0.9.5
- **History:** Constrain the playable overworld with walls, fences, and visual barriers, plus camera limits so players cannot see off the map.

## Status notes

- 2026-06-07: Closed with --force; 3/6 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
