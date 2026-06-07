---
xid: STO-TOOLS-036
parent: ./epic.md
kind: story
effort: tools
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-w8vi
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Multi-Creature Splay

## Summary

A pose can reference multiple creatures with world and inter-creature tethers, per-creature behavior, and partial breakaway.

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

- [x] creatures array with per-entry offset + connections
- [x] Connections target world or creature:<i>:<point>
- [x] Spawn all + create world and inter-creature tethers
- [x] Aggregate vs partial breakaway
- [x] Editor + library multi-creature support


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

- **Source:** docs/epics/EPIC_splay_system.md Story 11
- **Shipped in:** 0.9.21
- **History:** A pose can reference multiple creatures with world and inter-creature tethers, per-creature behavior, and partial breakaway.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU 0.9.21
