---
xid: STO-ENMY-019
parent: ./epic.md
kind: story
effort: enmy
status: in-progress
date: 2026-06-07
depends-on: []
bd-id: mdes-799
---

# Capture Official Baseline

## Summary

Record pre-EPIC baseline metrics for full, baseline, and edge-case suites as the measurement snapshot.

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

- [x] Run test_all.sh — 17/18 hit, 3757 dmg baseline
- [x] Run test_baseline.sh — 5/10 hit, 865 dmg (debug on)
- [x] Run test_edge_cases.sh — 8/8 hit
- [x] Record Pre-EPIC row in Baseline History
- [ ] Add updated row after each story completes


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

- **Source:** docs/epics/EPIC_monster_damage_and_weak_spots.md Story 9
- **Shipped in:** v0.9.18
- **History:** Record pre-EPIC baseline metrics for full, baseline, and edge-case suites as the measurement snapshot.
