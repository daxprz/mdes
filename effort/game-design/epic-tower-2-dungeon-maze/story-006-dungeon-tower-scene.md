---
xid: STO-DSGN-006
parent: ./epic.md
kind: story
effort: dsgn
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-cij
shipped: 2026-06-07
tasks: 5
complete: 2
---

# Dungeon Tower Scene

## Summary

Build the maze-style dungeon tower scene and its driving script as a Tower 2 variant.

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

- [x] Create dungeon_tower.tscn - maze-style tower variant
- [x] Dungeon tower script (dungeon_tower.gd)


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

- **Source:** BACKLOG.md Story 17.1; git: 'Tower 2: Top-down dungeon maze replaces side-scrolling tower' (2026-03-15)
- **Shipped in:** v0.9.5
- **History:** Build the maze-style dungeon tower scene and its driving script as a Tower 2 variant.

## Status notes

- 2026-06-07: Closed with --force; 3/5 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
