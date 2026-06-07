---
xid: STO-PROG-006
parent: ./epic.md
kind: story
effort: prog
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-861x
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Profile Creation Flow

## Summary

A controller-driven choose-or-create flow: name entry with on-screen keyboard, stack-ranking class preferences, optional sub-character naming, and a confirm summary, with profile select showing level and preferred class icon.

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

- [x] When controller connects: show 'Choose Profile' or 'Create New' screen
- [x] Create new profile step 1: Enter name (3-16 chars), on-screen keyboard, keyboard typing, name validation
- [x] Create new profile step 2: Stack-rank class preferences (drag/reorder, D-pad grab/move/drop)
- [x] Create new profile step 3: Optionally name each sub-character per class (skip for defaults)
- [x] Create new profile step 4: Accept/confirm screen showing summary
- [x] Profile select screen shows existing profiles with level + preferred class icon


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

- **Source:** BACKLOG.md Story 13.2; commit 'Profiles bound per-controller, name entry with D-pad grid' (2026-03-14)
- **Shipped in:** v0.9.0
- **History:** A controller-driven choose-or-create flow: name entry with on-screen keyboard, stack-ranking class preferences, optional sub-character naming, and a confirm summary, with profile select showing level and preferred class icon.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.0
